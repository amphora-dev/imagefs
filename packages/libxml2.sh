#!/usr/bin/env bash
# libxml2 2.13.5 — cmake
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.13.5"
PKG_NAME="libxml2-$VER"
SRC_URL="https://download.gnome.org/sources/libxml2/${VER%.*}/libxml2-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxml2.tar.xz && tar xf libxml2.tar.xz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DBUILD_SHARED_LIBS=ON \
    -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF \
    -DLIBXML2_WITH_ZLIB=ON -DLIBXML2_WITH_ICU=OFF \
    -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PROGRAMS=OFF ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libxml2.so" 2>/dev/null || true

log "  libxml2 $VER: $(ls $PREFIX/lib/libxml2.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
