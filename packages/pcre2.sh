#!/usr/bin/env bash
# pcre2 10.44 — cmake
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="10.44"
PKG_NAME="pcre2-$VER"
SRC_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$VER/pcre2-$VER.tar.bz2"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o pcre2.tar.bz2 && tar xf pcre2.tar.bz2; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
    -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF \
    -DPCRE2_SUPPORT_UNICODE=ON -DPCRE2_SUPPORT_JIT=ON ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libpcre2-8.so" 2>/dev/null || true

log "  pcre2 $VER: $(ls $PREFIX/lib/libpcre2*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
