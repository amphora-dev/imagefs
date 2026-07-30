#!/usr/bin/env bash
# libXfixes 6.0.1 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="6.0.1"
PKG_NAME="libXfixes-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXfixes-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libxfixes.tar.xz "$SRC_URL" \
    "$(echo "$SRC_URL" | sed s#xorg.freedesktop.org#ftp.x.org#)"
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXfixes.so" 2>/dev/null || true

log "  libXfixes $VER: $(ls $PREFIX/lib/libXfixes.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
