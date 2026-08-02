#!/usr/bin/env bash
# =============================================================================
# mesa-gl — Mesa 桌面 OpenGL (DRI 前端: EGL + GLX), 产出 libEGL/libGL + megadriver
# =============================================================================
# 取代 WinNative graphics_driver/extra_libs.tzst 里的预编译 libGL/libglapi:
# imagefs 自建后 extra_libs 整包废止 (Turnip / vkBasalt / bcn_layer 均不需要 --
# 默认走 wrapper ICD, 完整 Turnip 是可选 WN-Turnip zip)。
#
# Wine (>=10.17, 含 Proton 11) opengl32 → win32u dlopen libEGL.so.1 →
# 本 Mesa 的 EGL x11 平台 → zink → Vulkan (imagefs libvulkan.so + wrapper ICD),
# 呈现走 DRI3 + Present, 即 DXVK 已在用的那条 AHB 通路。
#
# 为什么不是 -Dglx=xlib (2026-08 改): xlib GLX 是 Mesa 的遗留兼容前端, 结构上
# 走不通我们的场景 --
#   - targets/libgl-xlib 的 meson 依赖不含 driver_zink, zink 根本编不进去;
#     即使补上, zink 的呈现完全绑定 kopper displaytarget, 而那只有 DRI 前端会
#     提供 loader_private, 所以 xlib 下 zink 能渲染但永远呈现不出来。WinNative
#     是靠 Pipetto zink-mesa-xlib fork 把 zink_flush_frontbuffer 改成整帧读回
#     CPU 再 XPutImage 才绕过去的, 代价是每帧一次 GPU→CPU 同步。
#   - 更致命的是 fakeglx 本身: glXCreateWindow 直接 `return win` (源码注释
#     "A hack for now"), GLXWindow 与 X Window 同 ID; glXMakeContextCurrent 只按
#     drawable 查 XMesaFindBuffer, 不比对 context 的 visual。于是同一窗口换
#     fbconfig 必然命中旧 buffer → _mesa_make_current 的 check_compatible 在
#     depthBits/stencilBits 上失配 → "MakeCurrent: incompatible visuals" →
#     此后所有 GL 调用 "called without a rendering context"。这在 X server 侧
#     无法修复。
# DRI 前端两者皆无: targets/dri 本来就列了 driver_zink, kopper 是原生呈现路径,
# 且 Mesa 的 EGL x11 平台从不查询 GLX 扩展 (src/egl 全树只有一行注释掉的 glx),
# 所以内置 Java X server 不需要实现 GLX 扩展。DRI3/Present 不可用时 Mesa 会自动
# 退到 swrast (core X + MIT-SHM), 仍然可用。
#
# 链接画像必须与 Termux/官方 libGL 一致 (与 ci/wrapper/build-tzst.sh 同源教训):
#   - meson host system=linux + -D__TERMUX__ + patch 0003 → DETECT_OS_ANDROID
#     关闭, 于是不会 DT_NEEDED liblog/libcutils/libsync 这些 android-stub;
#     那些名字一旦进 imagefs/usr/lib 就会遮蔽 /system 的真实实现。
#     system=linux 同时让 with_dri_platform=drm, platform_x11_dri3.c 才会编。
#   - XShm 走 libandroid-shmem (Bionic 无 SysV shm 实现, NDK 只给了头文件)。
#   - 不开 -Dandroid-stub (25.3 起它要求 platforms=android); 改用
#     vendor/mesa-gl-patches/0001 让 vk_android_native_buffer.h 在 __TERMUX__
#     下走通用 buffer_handle_t, 从而完全不碰 AOSP 的 cutils 头。
#   - gallium 驱动 zink + softpipe: zink 是加速路径, softpipe 是 Mesa 在
#     DRI3 不可用时自动回退的软件光栅化器 (不依赖 LLVM)。
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

# 本包单独抬到 API 30, 不用全局的 ANDROID_API=26。ci/wrapper/build-tzst.sh 同样
# 用 API 30, 两边的 Mesa 源码树保持同一个 bionic 画像。
MESA_GL_API="${MESA_GL_API:-30}"
CC="$TC/bin/${ARCH}-linux-android${MESA_GL_API}-clang"
CXX="$TC/bin/${ARCH}-linux-android${MESA_GL_API}-clang++"
[ -x "$CC" ] || { error "  缺少 $CC (MESA_GL_API=$MESA_GL_API)"; exit 1; }

mkdir -p "$WORK"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" mesa-gl.tar.xz "$SRC_URL" "$ALT_URL"
cd "$PKG_NAME"

# ---- patches ----
# 0003 与 wrapper 共用 (__TERMUX__ 时不认 DETECT_OS_ANDROID);
# mesa-gl-patches/* 是 GL 侧独有的。源码目录会被缓存复用, 故补丁需幂等。
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/util.sh"

require_patch() {
    local p="$1" status=0
    # `|| status=$?` rather than a bare call: under `set -e` a non-zero simple
    # command aborts the script before `case $?` ever runs.
    apply_patch "$p" || status=$?
    case $status in
        0) log "  已应用 $(basename "$p")" ;;
        1) log "  补丁已在源码中: $(basename "$p")" ;;
        *) error "  补丁无法应用: $p"; exit 1 ;;
    esac
}

require_patch "$REPO_ROOT/vendor/wrapper-patches/0003-termux-not-detect-os-android.patch"
for p in "$REPO_ROOT"/vendor/mesa-gl-patches/*.patch; do
    [ -e "$p" ] || continue
    require_patch "$p"
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
# Keep every GL frontend and the DRI megadriver on native ELF TLS. With the
# NDK's emulated TLS default, libgallium exports __emutls_v.* while libEGL and
# libGL retain dynamic references to the plain _mesa_glapi_tls_* symbols; both
# then fail dlopen before OpenGL starts. Rootfs v35 and the device-verified
# DirectDraw fix use this native-TLS profile.
c_args = ['-I$PREFIX/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__', '-fno-emulated-tls']
cpp_args = ['-I$PREFIX/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__', '-fno-emulated-tls']
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
    -Dglx=dri \
    -Degl=enabled \
    -Dopengl=true \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dgbm=disabled \
    -Dgallium-drivers=zink,softpipe \
    -Dvulkan-drivers= \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dglvnd=disabled \
    -Dxmlconfig=enabled \
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
# DRI 前端的产物分三块: libEGL (Wine >=10.17 dlopen 的那个)、libGL (遗留 GLX
# 消费者)、以及承载全部 gallium 驱动的 megadriver libgallium-<ver>.so。
GL_REAL="$(ls -1 "$PREFIX/lib"/libGL.so.1.* 2>/dev/null | head -1 || true)"
[ -n "$GL_REAL" ] || { error "  未生成 libGL.so.1.*"; exit 1; }
"$STRIP" --strip-unneeded "$GL_REAL" 2>/dev/null || true
ensure_soname_link "libGL.so.1" "$(basename "$GL_REAL")"

EGL_REAL="$(ls -1 "$PREFIX/lib"/libEGL.so.1.* 2>/dev/null | head -1 || true)"
[ -n "$EGL_REAL" ] || { error "  未生成 libEGL.so.1.* (Wine >=10.17 靠它做 GL)"; exit 1; }
"$STRIP" --strip-unneeded "$EGL_REAL" 2>/dev/null || true
ensure_soname_link "libEGL.so.1" "$(basename "$EGL_REAL")"

MEGADRIVER="$(ls -1 "$PREFIX/lib"/libgallium*.so 2>/dev/null | head -1 || true)"
[ -n "$MEGADRIVER" ] || { error "  未生成 libgallium*.so megadriver"; exit 1; }
"$STRIP" --strip-unneeded "$MEGADRIVER" 2>/dev/null || true

# 旧的 xlib GLX 构建产的是 libGL.so.1.5.0, DRI 前端产的是 libGL.so.1.2.0。
# staging 是增量复用的, 残留的旧实体会让 soname 软链指向错的那个。
for stale in "$PREFIX/lib"/libGL.so.1.* "$PREFIX/lib"/libEGL.so.1.*; do
    [ -e "$stale" ] || continue
    case "$stale" in
        "$GL_REAL"|"$EGL_REAL") continue ;;
    esac
    log "  清理旧构建残留: $(basename "$stale")"
    rm -f "$stale"
done

# android-stub 一旦被 DT_NEEDED 就会在 imagefs 里遮蔽 /system 的真实实现。
for so in "$GL_REAL" "$EGL_REAL" "$MEGADRIVER"; do
    so_needed="$(readelf -dW "$so" | awk -F'[][]' '/NEEDED/{print $2}')"
    for stub in liblog.so libcutils.so libsync.so libhardware.so libnativewindow.so; do
        if echo "$so_needed" | grep -qx "$stub"; then
            error "  $(basename "$so") DT_NEEDED 含 android-stub $stub (Termux 画像失效)"
            exit 1
        fi
    done
done

# zink 是加速路径。DRI 前端下它由 targets/dri 链进 megadriver (不像 xlib 前端
# 那样根本没有 driver_zink), 缺了就只剩 softpipe, 必须硬断言而不是 warn。
# 只能按 .rodata 里的字符串判: zink 的函数都不导出, --strip-unneeded 之后符号表
# 里查不到。libGL/libEGL 都 DT_NEEDED 这个 megadriver, 25.3 没有 dri/*_dri.so 那
# 一层 (那是 dril 桩, 只在 with_gbm 时给 X server 用)。
if ! grep -q 'ZINK:' "$MEGADRIVER"; then
    error "  megadriver 未链接 zink, GL 只会退到软件光栅化"
    exit 1
fi

# Amphora 只在看到该标记时才下发 GALLIUM_DRIVER=zink
# (XServerWineSessionPreparer.applyGalliumDriver)。
: > "$PREFIX/lib/.libgl-zink"

# 这里装出来的 libEGL.so -> libEGL.so.1 是 meson 的开发软链, 只服务 staging 里的
# -lEGL。它和 Android 系统 EGL 同名, 打进 imagefs 就会顶掉系统实现, 所以由
# package-imagefs.sh 在 staging→target 时按清单复核 (config.sh)。
# Wine 认的是带版本号的 libEGL.so.1, 不受影响。

log "  mesa-gl $VER: $(ls "$PREFIX/lib"/lib{GL,EGL,gallium}*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
log "  libEGL NEEDED: $(readelf -dW "$EGL_REAL" | awk -F'[][]' '/NEEDED/{print $2}' | tr '\n' ' ')"
