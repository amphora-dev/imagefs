#!/usr/bin/env bash
# xorgproto 2024.1 — autotools (提供 X11 头文件 + .pc)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2024.1"
PKG_NAME="xorgproto-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/proto/xorgproto-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" xorgproto.tar.xz "$SRC_URL" \
    "$(echo "$SRC_URL" | sed s#xorg.freedesktop.org#ftp.x.org#)"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

../configure --host=${ARCH}-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install

log "  xorgproto $VER: headers installed"
