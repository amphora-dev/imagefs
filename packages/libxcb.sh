#!/usr/bin/env bash
# libxcb 1.17.0 — autotools (依赖 xorgproto, xcb-proto)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.17.0"
PKG_NAME="libxcb-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libxcb-$VER.tar.xz"

cd "$SRC_DIR"

# 1. 先构建 xcb-proto (Python 代码生成器, 宿主端运行)
if [ ! -d "xcb-proto-1.17.0" ]; then
    curl -sL "https://xorg.freedesktop.org/archive/individual/proto/xcb-proto-1.17.0.tar.xz" -o xcb-proto.tar.xz
    tar xf xcb-proto.tar.xz
fi
cd "xcb-proto-1.17.0"
./configure --prefix=$PREFIX --enable-shared --disable-static
make -j$JOBS
make install
cd "$SRC_DIR"

# 2. 构建 libxcb (autotools)
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libxcb.tar.xz && tar xf libxcb.tar.xz; }
cd "$PKG_NAME"

# 需要 libXau (xorgproto 提供 headers, 但 libXau 需要单独编译)
cd "$SRC_DIR"
if [ ! -d "libXau-1.0.12" ]; then
    curl -sL "https://xorg.freedesktop.org/archive/individual/lib/libXau-1.0.12.tar.xz" -o libxau.tar.xz
    tar xf libxau.tar.xz
fi
cd "libXau-1.0.12"
./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXau.so" 2>/dev/null || true
cd "$SRC_DIR"

# 2b. 构建 libXdmcp (libxcb 硬依赖, 提供 XDMCP 协议)
if [ ! -d "libXdmcp-1.1.5" ]; then
    curl -sL "https://xorg.freedesktop.org/archive/individual/lib/libXdmcp-1.1.5.tar.xz" -o libxdmcp.tar.xz
    tar xf libxdmcp.tar.xz
fi
cd "libXdmcp-1.1.5"
./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXdmcp.so" 2>/dev/null || true
cd "$SRC_DIR"

# 3. libxcb 本体
cd "$PKG_NAME"
./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --disable-static \
    --without-xcb-proto-datadir \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PYTHON=python3
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libxcb.so" 2>/dev/null || true

log "  libxcb $VER: $(ls $PREFIX/lib/libxcb*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
