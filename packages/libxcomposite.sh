#!/usr/bin/env bash
# libXcomposite 0.4.6 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="0.4.6"
PKG_NAME="libXcomposite-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXcomposite-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxcomposite.tar.xz && tar xf libxcomposite.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXcomposite.so" 2>/dev/null || true

log "  libXcomposite $VER: $(ls $PREFIX/lib/libXcomposite.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
