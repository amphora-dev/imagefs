#!/usr/bin/env bash
# =============================================================================
# mesa-gl — Mesa 桌面 OpenGL (gallium xlib GLX + zink), 产出 libGL.so.1
# =============================================================================
# 取代 WinNative graphics_driver/extra_libs.tzst 里的预编译 libGL/libglapi:
# imagefs 自建后 extra_libs 整包废止 (Turnip / vkBasalt / bcn_layer 均不需要 --
# 默认走 wrapper ICD, 完整 Turnip 是可选 WN-Turnip zip)。
#
# Wine opengl32 / ddraw → WineD3D → 本 libGL (GALLIUM_DRIVER=zink) → Vulkan
# (imagefs 的 libvulkan.so + wrapper ICD)。Amphora 侧 env 见
# XServerWineSessionPreparer: GALLIUM_DRIVER=zink / LIBGL_KOPPER_DISABLE=true。
#
# 链接画像必须与 Termux/官方 libGL 一致 (与 ci/wrapper/build-tzst.sh 同源教训):
#   - meson host system=linux + -D__TERMUX__ + patch 0003 → DETECT_OS_ANDROID
#     关闭, 于是不会 DT_NEEDED liblog/libcutils/libsync 这些 android-stub;
#     那些名字一旦进 imagefs/usr/lib 就会遮蔽 /system 的真实实现。
#   - XShm 走 libandroid-shmem (Bionic 无 SysV shm 实现, NDK 只给了头文件)。
#   - 不开 -Dandroid-stub (25.3 起它要求 platforms=android); 改用
#     vendor/mesa-gl-patches/0001 让 vk_android_native_buffer.h 在 __TERMUX__
#     下走通用 buffer_handle_t, 从而完全不碰 AOSP 的 cutils 头。
#   - gallium 驱动只要 zink + softpipe: xlib GLX 强制要一个软件光栅化器
#     (meson.build "xlib based GLX requires softpipe or llvmpipe"), 取不依赖
#     LLVM 的 softpipe; sw_helper 的探测顺序里 zink 排在软件驱动之前, 加上
#     Amphora 显式下发 GALLIUM_DRIVER=zink, 实际永远走 zink。
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="${MESA_GL_VER:-25.3.6}"
PKG_NAME="mesa-$VER"
SRC_URL="https://archive.mesa3d.org/mesa-$VER.tar.xz"
ALT_URL="https://mesa.freedesktop.org/archive/mesa-$VER.tar.xz"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$WORK_DIR/mesa-gl"
CROSS="$WORK/cross-termux-aarch64.ini"
NATIVE="$WORK/native.ini"
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"

mkdir -p "$WORK"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" mesa-gl.tar.xz "$SRC_URL" "$ALT_URL"
cd "$PKG_NAME"

# ---- patches ----
# 0003 与 wrapper 共用 (__TERMUX__ 时不认 DETECT_OS_ANDROID);
# mesa-gl-patches/* 是 GL 侧独有的。源码目录会被缓存复用, 故补丁需幂等。
apply_patch() {
    local p="$1"
    [ -f "$p" ] || { error "  缺少补丁: $p"; exit 1; }
    if patch -p1 --forward --batch --dry-run < "$p" >/dev/null 2>&1; then
        patch -p1 --forward --batch < "$p"
        log "  已应用 $(basename "$p")"
    elif patch -p1 --reverse --batch --dry-run < "$p" >/dev/null 2>&1; then
        log "  补丁已在源码中: $(basename "$p")"
    else
        error "  补丁无法应用: $p"
        exit 1
    fi
}

apply_patch "$REPO_ROOT/vendor/wrapper-patches/0003-termux-not-detect-os-android.patch"
for p in "$REPO_ROOT"/vendor/mesa-gl-patches/*.patch; do
    [ -e "$p" ] || continue
    apply_patch "$p"
done

# ---- 交叉编译 cross-file (Termux 画像, 不用 graph 的 system=android) ----
cat > "$CROSS" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
c_ld = '$TC/bin/ld.lld'
cpp_ld = '$TC/bin/ld.lld'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-I$PREFIX/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__']
cpp_args = ['-I$PREFIX/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__']
# --undefined-version: libGL 的 version script 会导出 _mesa_glapi_tls_Dispatch,
# 但 Bionic 上 Mesa 走 __thread 而非 TLS dispatch, 该符号不存在 → lld 默认报错。
c_link_args = ['-L$PREFIX/lib', '-landroid-shmem', '-lc++_shared', '-Wl,-rpath,/usr/lib', '-Wl,--as-needed', '-Wl,--undefined-version']
cpp_link_args = ['-L$PREFIX/lib', '-landroid-shmem', '-lc++_shared', '-Wl,-rpath,/usr/lib', '-Wl,--as-needed', '-Wl,--undefined-version']

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig'
needs_exe_wrapper = true

[host_machine]
# Termux 式: 工具链仍是 aarch64-linux-android*, 但 meson host system 报 linux
# (platforms=x11, 不是 android)。
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

cat > "$NATIVE" <<'EOF'
[binaries]
c = 'clang'
cpp = 'clang++'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

BUILD="$WORK/build"
rm -rf "$BUILD"

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
unset PKG_CONFIG_PATH || true

meson setup "$BUILD" \
    --cross-file "$CROSS" \
    --native-file "$NATIVE" \
    --prefix "$PREFIX" \
    --libdir "$PREFIX/lib" \
    -Dbuildtype=release \
    -Db_ndebug=true \
    -Dplatforms=x11 \
    -Dglx=xlib \
    -Dopengl=true \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Degl=disabled \
    -Dgbm=disabled \
    -Dgallium-drivers=zink,softpipe \
    -Dvulkan-drivers= \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dglvnd=disabled \
    -Dxmlconfig=disabled \
    -Dzstd=enabled \
    -Dvideo-codecs= \
    -Dandroid-libbacktrace=disabled \
    -Dxlib-lease=disabled \
    -Dvalgrind=disabled \
    -Dbuild-tests=false \
    || { tail -120 "$BUILD/meson-logs/meson-log.txt" 2>/dev/null || true; exit 1; }

ninja -C "$BUILD" -j"$JOBS"
ninja -C "$BUILD" install

# ---- 产物校验 + soname 补齐 ----
GL_REAL="$(ls -1 "$PREFIX/lib"/libGL.so.1.* 2>/dev/null | head -1 || true)"
[ -n "$GL_REAL" ] || { error "  未生成 libGL.so.1.*"; exit 1; }
"$STRIP" --strip-unneeded "$GL_REAL" 2>/dev/null || true
ensure_soname_link "libGL.so.1" "$(basename "$GL_REAL")"

# android-stub 一旦被 DT_NEEDED 就会在 imagefs 里遮蔽 /system 的真实实现。
NEEDED="$(readelf -dW "$GL_REAL" | awk -F'[][]' '/NEEDED/{print $2}')"
for stub in liblog.so libcutils.so libsync.so libhardware.so libnativewindow.so; do
    if echo "$NEEDED" | grep -qx "$stub"; then
        error "  libGL DT_NEEDED 含 android-stub $stub (Termux 画像失效)"
        exit 1
    fi
done
echo "$NEEDED" | grep -qx 'libX11.so' || warn "  libGL 未 NEEDED libX11.so: $(echo "$NEEDED" | tr '\n' ' ')"

log "  mesa-gl $VER: $(ls "$PREFIX/lib"/libGL.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
log "  NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
