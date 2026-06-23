#!/usr/bin/env bash
# brotli 1.1.0 — cmake
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.1.0"
PKG_NAME="brotli-$VER"
SRC_URL="https://github.com/google/brotli/archive/refs/tags/v$VER.tar.gz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o brotli.tar.gz && tar xf brotli.tar.gz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DBUILD_SHARED_LIBS=ON ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libbrotli"*.so* 2>/dev/null || true

log "  brotli $VER: $(ls $PREFIX/lib/libbrotli*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
