#!/usr/bin/env bash
# libX11 1.8.10 — autotools (release tarball 不含 meson.build)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.8.10"
PKG_NAME="libX11-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libX11-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libx11.tar.xz && tar xf libx11.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --disable-specs \
    --without-xmlto --without-fop --without-xsltproc \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libX11.so" 2>/dev/null || true

log "  libX11 $VER: $(ls $PREFIX/lib/libX11.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
