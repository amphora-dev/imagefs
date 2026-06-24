#!/usr/bin/env bash
# libxshmfence 1.3.2 — autotools
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.3.2"
PKG_NAME="libxshmfence-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libxshmfence-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxshmfence.tar.xz && tar xf libxshmfence.tar.xz; }
cd "$PKG_NAME"

# Bionic 无 <linux/futex.h> (用 <sys/futex.h>), configure 的 AC_CHECK_HEADER 会失败
# 直接禁用 futex 后端, 回退到 pollfd 实现 (功能等价, 不依赖内核 futex 头)
./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    --disable-futex \
    xorg_cv_malloc0_returns_null=yes \
    --with-pic \
    CFLAGS="$CFLAGS -D_GNU_SOURCE" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libxshmfence.so" 2>/dev/null || true

log "  libxshmfence $VER: $(ls $PREFIX/lib/libxshmfence.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
