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
    -DCMAKE_TOOLCHAIN_FILE="$NDK_DIR/build/cmake/android.toolchain.cmake" \
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

# Turnip / libGL NEEDED 写的是 libzstd.so.1。Android cmake 常把 SONAME 写成
# 裸名 libzstd.so，只靠软链不够稳妥 —— 强制 SONAME 与 NEEDED 一致。
if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-soname libzstd.so.1 "$PREFIX/lib/libzstd.so"
elif [ -x "$TC/bin/llvm-patchelf" ]; then
    "$TC/bin/llvm-patchelf" --set-soname libzstd.so.1 "$PREFIX/lib/libzstd.so"
fi
ensure_soname_link "libzstd.so.1" "libzstd.so"
soname=$(readelf -dW "$PREFIX/lib/libzstd.so" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ "$soname" != "libzstd.so.1" ]; then
    error "  libzstd SONAME='$soname' (expected libzstd.so.1)"
    exit 1
fi

log "  zstd $VER: SONAME=$soname $(ls $PREFIX/lib/libzstd.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
