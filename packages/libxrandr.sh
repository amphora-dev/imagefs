#!/usr/bin/env bash
# libXrandr 1.5.4 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.5.4"
PKG_NAME="libXrandr-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXrandr-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxrandr.tar.xz && tar xf libxrandr.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXrandr.so" 2>/dev/null || true

log "  libXrandr $VER: $(ls $PREFIX/lib/libXrandr.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
