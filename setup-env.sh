#!/usr/bin/env bash
# =============================================================================
# setup-env.sh — NDK 下载 + 交叉编译环境变量设置
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

# ---- 1. NDK 下载 ----
NDK_DIR="$CACHE_DIR/android-ndk-$NDK_VERSION"
export TC="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"

if [ ! -x "$TC/bin/clang" ]; then
    section "下载 Android NDK $NDK_VERSION"
    mkdir -p "$CACHE_DIR"
    curl -L -o "$CACHE_DIR/$NDK_FILENAME" "$NDK_URL"
    log "解压 NDK..."
    unzip -q "$CACHE_DIR/$NDK_FILENAME" -d "$CACHE_DIR"
    # NDK zip 解压后目录名可能是 android-ndk-r29
    mv "$CACHE_DIR/android-ndk-$NDK_VERSION" "$NDK_DIR" 2>/dev/null || true
    rm -f "$CACHE_DIR/$NDK_FILENAME"
    chmod -R +x "$NDK_DIR"
fi

log "NDK 路径: $NDK_DIR"

# ---- 2. 交叉编译工具链 ----
export PATH="$TC/bin:$PATH"
export CC="$TC/bin/${ARCH}-linux-android${ANDROID_API}-clang"
export CXX="$TC/bin/${ARCH}-linux-android${ANDROID_API}-clang++"
export AR="$TC/bin/llvm-ar"
export STRIP="$TC/bin/llvm-strip"
export RANLIB="$TC/bin/llvm-ranlib"
export NM="$TC/bin/llvm-nm"
export LD="$TC/bin/ld.lld"
export AS="$TC/bin/llvm-as"

# ---- 3. 编译 flags ----
export CFLAGS="-fPIC -O2 -I$PREFIX/include"
export CXXFLAGS="-fPIC -O2 -I$PREFIX/include"
export LDFLAGS="-Wl,-rpath,/usr/lib -L$PREFIX/lib -Wl,--allow-shlib-undefined -Wl,--undefined-version"

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

log "Meson cross-file: $CROSS_FILE"
export CROSS_FILE="$CROSS_FILE"

echo "$CROSS_FILE"
