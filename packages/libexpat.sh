#!/usr/bin/env bash
# libexpat 2.6.4 — cmake
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.6.4"
PKG_NAME="expat-$VER"
SRC_URL="https://github.com/libexpat/libexpat/releases/download/R_${VER//./_}/expat-$VER.tar.bz2"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o expat.tar.bz2 && tar xf expat.tar.bz2; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DEXPAT_BUILD_SHARED=ON -DEXPAT_BUILD_STATIC=OFF \
    -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_EXAMPLES=OFF ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libexpat.so" 2>/dev/null || true

log "  expat $VER: $(ls $PREFIX/lib/libexpat.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
