#!/usr/bin/env bash
# Vulkan-Loader 1.4.313 — cmake (依赖 vulkan-headers)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.4.313"
PKG_NAME="Vulkan-Loader-$VER"
SRC_URL="https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/v$VER.tar.gz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o vulkan-loader.tar.gz && tar xf vulkan-loader.tar.gz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# Bionic 无 libdl, 用 -ldl 映射到 libc
# 参考 MiceWine: -DBUILD_TESTS=OFF
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DBUILD_TESTS=OFF \
    -DBUILD_WSI_XCB_SUPPORT=ON \
    -DBUILD_WSI_XLIB_SUPPORT=ON \
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF \
    -DVULKAN_HEADERS_INSTALL_DIR=$PREFIX ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libvulkan.so" 2>/dev/null || true

log "  Vulkan-Loader $VER: $(ls $PREFIX/lib/libvulkan.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
