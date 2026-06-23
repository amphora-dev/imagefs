#!/usr/bin/env bash
# libXinerama 1.1.5 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.1.5"
PKG_NAME="libXinerama-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXinerama-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxinerama.tar.xz && tar xf libxinerama.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXinerama.so" 2>/dev/null || true

log "  libXinerama $VER: $(ls $PREFIX/lib/libXinerama.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
