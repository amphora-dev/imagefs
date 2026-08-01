#!/usr/bin/env bash
# =============================================================================
# setup-env.sh — NDK 解析 + 交叉编译环境变量
# =============================================================================
# 优先使用环境里已有的 NDK（GitHub Actions runner 自带；或本机 ANDROID_NDK_*）。
# 仅在都找不到时才下载到 $CACHE_DIR（本地开发兜底）。
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/ndk.sh"

# ---- 1. NDK ----
if NDK_DIR="$(ndk_resolve_dir "${NDK_DIR:-}" "$CACHE_DIR/android-ndk-$NDK_VERSION")"; then
    log "NDK 路径: $NDK_DIR (已有，跳过下载)"
else
    section "下载 Android NDK $NDK_VERSION（未检测到 ANDROID_NDK_*）"
    NDK_DIR="$CACHE_DIR/android-ndk-$NDK_VERSION"
    mkdir -p "$CACHE_DIR"
    curl -fsSL --retry 3 --retry-delay 2 -o "$CACHE_DIR/$NDK_FILENAME" "$NDK_URL"
    log "解压 NDK..."
    unzip -q "$CACHE_DIR/$NDK_FILENAME" -d "$CACHE_DIR"
    mv "$CACHE_DIR/android-ndk-$NDK_VERSION" "$NDK_DIR" 2>/dev/null || true
    # sdk-style layout: ndk/29.0.x
    if [ ! -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
        found="$(find "$CACHE_DIR" -path '*/toolchains/llvm/prebuilt/linux-x86_64/bin/clang' 2>/dev/null | head -1 || true)"
        if [ -n "$found" ]; then
            NDK_DIR="$(cd "$(dirname "$found")/../../../../.." && pwd)"
        fi
    fi
    rm -f "$CACHE_DIR/$NDK_FILENAME"
    chmod -R +x "$NDK_DIR"
    log "NDK 路径: $NDK_DIR"
fi

export NDK_DIR
export ANDROID_NDK_ROOT="$NDK_DIR"
export ANDROID_NDK_HOME="$NDK_DIR"
export TC="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"

if [ ! -x "$TC/bin/clang" ]; then
    error "NDK clang 不可用: $TC/bin/clang"
    exit 1
fi

# ---- 2. 交叉编译工具链 ----
export PATH="$TC/bin:$PATH"

# Host-usable scripts installed into the staging prefix (glib-mkenums,
# glib-compile-resources, …) must be on PATH for meson find_program() during
# later packages (gst-plugins-base). Cross-compiled ELF bins in the same dir
# are not executed on the build machine.
export PATH="$PREFIX/bin:$HOST_DIR/bin:$PATH"
REAL_CC="$TC/bin/${ARCH}-linux-android${ANDROID_API}-clang"
REAL_CXX="$TC/bin/${ARCH}-linux-android${ANDROID_API}-clang++"
export AR="$TC/bin/llvm-ar"
export STRIP="$TC/bin/llvm-strip"
export RANLIB="$TC/bin/llvm-ranlib"
export NM="$TC/bin/llvm-nm"
export LD="$TC/bin/ld.lld"
export AS="$TC/bin/llvm-as"

# ---- 2b. ccache (optional) ----
export CCACHE_DIR="${CCACHE_DIR:-$CACHE_DIR/ccache}"
if command -v ccache >/dev/null 2>&1; then
    mkdir -p "$CCACHE_DIR" "$CACHE_DIR/ccache-wrappers"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
    export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
    export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"
    export CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS:-pch_defines,time_macros,include_file_mtime,include_file_ctime}"
    ccache --set-config "cache_dir=$CCACHE_DIR" 2>/dev/null || true
    ccache --set-config "max_size=$CCACHE_MAXSIZE" 2>/dev/null || true
    ccache --set-config "compiler_check=$CCACHE_COMPILERCHECK" 2>/dev/null || true
    ccache --set-config "sloppiness=$CCACHE_SLOPPINESS" 2>/dev/null || true
    ccache --set-config "compression=true" 2>/dev/null || true

    cat > "$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang" <<EOF
#!/usr/bin/env bash
exec ccache "$REAL_CC" "\$@"
EOF
    cat > "$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang++" <<EOF
#!/usr/bin/env bash
exec ccache "$REAL_CXX" "\$@"
EOF
    chmod +x \
        "$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang" \
        "$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang++"

    export CC="$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang"
    export CXX="$CACHE_DIR/ccache-wrappers/${ARCH}-linux-android${ANDROID_API}-clang++"
    export CMAKE_C_COMPILER_LAUNCHER=ccache
    export CMAKE_CXX_COMPILER_LAUNCHER=ccache
    log "ccache 已启用 (CCACHE_DIR=$CCACHE_DIR, max=$CCACHE_MAXSIZE)"
    ccache -z 2>/dev/null || true
else
    export CC="$REAL_CC"
    export CXX="$REAL_CXX"
    warn "ccache 未安装 — 交叉编译将无对象缓存"
fi

# ---- 3. 编译 flags ----
# LDFLAGS_BASE: safe default for versioned SONAMEs (PNG16_0, etc.).
# LDFLAGS_PERMISSIVE: opt-in for packages whose version-scripts need
# Android lld's --undefined-version (set locally in that package script).
export LDFLAGS_BASE="-Wl,-rpath,/usr/lib -L$PREFIX/lib -Wl,--allow-shlib-undefined"
export LDFLAGS_PERMISSIVE="$LDFLAGS_BASE -Wl,--undefined-version"
# Keep historical default for existing packages; prefer LDFLAGS_BASE in new/fixed recipes.
export LDFLAGS="${LDFLAGS:-$LDFLAGS_PERMISSIVE}"
export CFLAGS="-fPIC -O2 -I$PREFIX/include"
export CXXFLAGS="-fPIC -O2 -I$PREFIX/include"

# ---- 4. pkg-config 交叉编译 ----
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG="pkg-config"

# ---- 5. 验证 ----
log "CC = $CC"
"$CC" --version | head -1

# ---- 6. 生成 meson cross-file ----
CROSS_FILE="$BUILD_DIR/cross-${ARCH}-bionic.ini"
cat > "$CROSS_FILE" <<EOF
[binaries]
c         = '$CC'
cpp       = '$CXX'
ar        = '$AR'
as        = '$AS'
ld        = '$LD'
strip     = '$STRIP'
ranlib    = '$RANLIB'
nm        = '$NM'
pkgconfig = 'pkg-config'

[built-in options]
c_args         = ['-fPIC', '-O2', '-I$PREFIX/include']
cpp_args       = ['-fPIC', '-O2', '-I$PREFIX/include']
c_link_args    = ['-Wl,-rpath,/usr/lib', '-L$PREFIX/lib', '-Wl,--allow-shlib-undefined', '-Wl,--undefined-version']
cpp_link_args  = ['-Wl,-rpath,/usr/lib', '-L$PREFIX/lib', '-Wl,--allow-shlib-undefined', '-Wl,--undefined-version']

[properties]
needs_exe_wrapper = false

[host_machine]
system     = 'android'
cpu_family = 'aarch64'
cpu        = 'aarch64'
endian     = 'little'
EOF

log "meson cross-file: $CROSS_FILE"
export CROSS_FILE
