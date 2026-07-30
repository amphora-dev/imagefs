#!/usr/bin/env bash
# zstd 1.5.6 — cmake。图形栈的硬依赖, 不是可选压缩库。
#
# libvulkan_freedreno.so (Turnip, extra_libs.tzst) 与 libGL.so.1 (Mesa/Zink,
# extra_libs.tzst) 的 NEEDED 都写着 libzstd.so.1 —— Mesa 用它做 shader cache。
# 首轮 42 包漏了它, 官方 imagefs 是有的, 所以换自建 imagefs 会让 OpenGL/Vulkan
# 驱动加载失败。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.5.6"
PKG_NAME="zstd-$VER"
SRC_URL="https://github.com/facebook/zstd/releases/download/v$VER/zstd-$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" zstd.tar.gz "$SRC_URL"
cd "$PKG_NAME/build/cmake"

rm -rf build_dir && mkdir -p build_dir && cd build_dir

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE="$CACHE_DIR/android-ndk-$NDK_VERSION/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-$ANDROID_API \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DZSTD_BUILD_SHARED=ON \
    -DZSTD_BUILD_STATIC=OFF \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_LEGACY_SUPPORT=OFF

make -j$JOBS
make install

$STRIP "$PREFIX/lib/libzstd.so" 2>/dev/null || true

# Turnip 与 libGL.so.1 的 NEEDED 写的是 libzstd.so.1, 而 cmake 在
# CMAKE_SYSTEM_NAME=Android 下不生成版本软链 —— 官方 imagefs 里是
# libzstd.so -> libzstd.so.1 -> libzstd.so.1.5.8。
ensure_soname_link "libzstd.so.1" "libzstd.so"

log "  zstd $VER: $(ls $PREFIX/lib/libzstd.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
