#!/usr/bin/env bash
# libXxf86vm 1.1.5 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.1.5"
PKG_NAME="libXxf86vm-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXxf86vm-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxxf86vm.tar.xz && tar xf libxxf86vm.tar.xz; }
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXxf86vm.so" 2>/dev/null || true

log "  libXxf86vm $VER: $(ls $PREFIX/lib/libXxf86vm.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
