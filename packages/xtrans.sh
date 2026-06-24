#!/usr/bin/env bash
# xtrans 1.5.2 — autotools (X11 传输层, libX11 硬依赖)
# 提供 xtrans.pc, libX11/libXext/etc 的 configure 通过 pkg-config 查找
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.5.2"
PKG_NAME="xtrans-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/xtrans-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o xtrans.tar.xz && tar xf xtrans.tar.xz; }
cd "$PKG_NAME"

# xtrans 是纯头文件/辅助脚本包, 无需交叉编译特殊处理
./configure --host=$ARCH-linux-android --prefix=$PREFIX \
    --enable-shared --disable-static \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install

log "  xtrans $VER: $(ls $PREFIX/share/pkgconfig/xtrans.pc 2>/dev/null && echo 'xtrans.pc installed')"
