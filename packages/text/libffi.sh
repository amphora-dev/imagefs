#!/usr/bin/env bash
# libffi 3.4.6 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="3.4.6"
PKG_NAME="libffi-$VER"
SRC_URL="https://github.com/libffi/libffi/releases/download/v$VER/libffi-$VER.tar.gz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libffi.tar.gz && tar xzf libffi.tar.gz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

../configure --host=${ARCH}-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libffi.so" 2>/dev/null || true

log "  libffi $VER: $(ls $PREFIX/lib/libffi.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
