#!/usr/bin/env bash
# libXcursor 1.2.2 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.2.2"
PKG_NAME="libXcursor-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXcursor-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxcursor.tar.xz && tar xf libxcursor.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXcursor.so" 2>/dev/null || true

log "  libXcursor $VER: $(ls $PREFIX/lib/libXcursor.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
