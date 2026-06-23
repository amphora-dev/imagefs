#!/usr/bin/env bash
# libXi 1.8.2 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.8.2"
PKG_NAME="libXi-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXi-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxi.tar.xz && tar xf libxi.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXi.so" 2>/dev/null || true

log "  libXi $VER: $(ls $PREFIX/lib/libXi.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
