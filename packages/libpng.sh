#!/usr/bin/env bash
# libpng 1.6.44 — cmake (改用 cmake 避免 NDK sysroot zlib.h 冲突)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.6.44"
PKG_NAME="libpng-$VER"
SRC_URL="https://download.sourceforge.net/libpng/libpng-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libpng.tar.xz && tar xf libpng.tar.xz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 使用 cmake 确保 ZLIB_ROOT 指向我们编译的 zlib, 避免 NDK sysroot 冲突
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_INSTALL_INCLUDEDIR=$PREFIX/include \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_FIND_ROOT_PATH=$PREFIX \
    -DZLIB_ROOT=$PREFIX \
    -DPNG_SHARED=ON \
    -DPNG_STATIC=OFF \
    -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF \
    -DPNG_ARM_NEON=on \
    ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libpng16.so" 2>/dev/null || true

log "  libpng $VER: $(ls $PREFIX/lib/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
