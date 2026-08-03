#!/usr/bin/env bash
# zstd 1.5.6 — cmake。图形栈的硬依赖, 不是可选压缩库。
#
# 自建的 libGL.so.1 (packages/graphics/mesa-gl.sh) 与可选 Turnip
# (libvulkan_freedreno.so) 的 NEEDED 都写着 libzstd.so.1 —— Mesa 用它做 shader cache。
# 首轮 42 包漏了它, 官方 imagefs 是有的, 所以换自建 imagefs 会让 OpenGL/Vulkan
# 驱动加载失败。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.5.6"
PKG_NAME="zstd-$VER"
SRC_URL="https://github.com/facebook/zstd/releases/download/v$VER/zstd-$VER.tar.gz"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" zstd.tar.gz "$SRC_URL"
cd "$PKG_NAME"

# CMake's Android platform disables versioned SONAMEs globally. zstd already
# declares SOVERSION=1; this patch lets that upstream metadata reach the linker.
source "$REPO_ROOT/lib/util.sh"
status=0
apply_patch "$REPO_ROOT/vendor/zstd-patches/0001-android-versioned-soname.patch" || status=$?
case $status in
    0|1) ;;
    *) error "  zstd versioned-SONAME patch failed"; exit 1 ;;
esac

cd build/cmake
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

# Turnip / libGL NEEDED 写的是 libzstd.so.1。SONAME 必须在链接时写入；
# 事后 patchelf 会重排 Android linker 实际读取的 ELF LOAD/.dynstr 布局。
ensure_soname_link "libzstd.so.1" "libzstd.so"
soname=$(readelf -dW "$PREFIX/lib/libzstd.so" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ "$soname" != "libzstd.so.1" ]; then
    error "  libzstd SONAME='$soname' (expected libzstd.so.1)"
    exit 1
fi

log "  zstd $VER: SONAME=$soname $(ls $PREFIX/lib/libzstd.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
