#!/usr/bin/env bash
# Vulkan-Loader 1.4.313 — cmake (依赖 vulkan-headers)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.4.313"
PKG_NAME="Vulkan-Loader-$VER"
SRC_URL="https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/v$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" vulkan-loader.tar.gz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# Bionic 无 libdl, 用 -ldl 映射到 libc
# 参考 MiceWine: -DBUILD_TESTS=OFF
#
# BUILD_WSI_XLIB_XRANDR_SUPPORT 上游默认 ON, 且 CMakeLists.txt:132 对它做
# pkg_check_modules(XRANDR REQUIRED ...), 没有 xrandr.pc 就整包 configure 失败。
# 它启用的是 VK_EXT_acquire_xlib_display (独占显示器的 direct display), 在
# Android 上没有意义, 所以关掉 —— 这也让 imagefs 真正不必带 libxrandr。
# 注意 libvulkan_wrapper / libvulkan_freedreno 需要的是 libxcb-randr (由 libxcb
# 提供), 与 libXrandr 是两回事。
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DBUILD_TESTS=OFF \
    -DBUILD_WSI_XCB_SUPPORT=ON \
    -DBUILD_WSI_XLIB_SUPPORT=ON \
    -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF \
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF \
    -DVULKAN_HEADERS_INSTALL_DIR=$PREFIX ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libvulkan.so" 2>/dev/null || true

log "  Vulkan-Loader $VER: $(ls $PREFIX/lib/libvulkan.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
