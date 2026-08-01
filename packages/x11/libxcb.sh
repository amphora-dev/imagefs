#!/usr/bin/env bash
# libxcb 1.17.0 — autotools (依赖 xorgproto, xcb-proto)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.17.0"
PKG_NAME="libxcb-$VER"

# libxcb 的三个硬依赖跟着它一起构建, 上游各自独立发版。
XCB_PROTO_VER="1.17.0"
LIBXAU_VER="1.0.12"
LIBXDMCP_VER="1.1.5"

# xorg.freedesktop.org 在部分 CI 出口不通, 统一带上 ftp.x.org 备用源。
xorg_urls() {
    local path="$1"
    printf '%s\n' \
        "https://xorg.freedesktop.org/archive/individual/$path" \
        "https://ftp.x.org/archive/individual/$path"
}

cd "$SRC_DIR"

# 1. 先构建 xcb-proto (Python 代码生成器, 宿主端运行)
mapfile -t _urls < <(xorg_urls "proto/xcb-proto-$XCB_PROTO_VER.tar.xz")
fetch_source "xcb-proto-$XCB_PROTO_VER" xcb-proto.tar.xz "${_urls[@]}"
cd "xcb-proto-$XCB_PROTO_VER"
./configure --prefix=$PREFIX --enable-shared --disable-static
make -j$JOBS
make install
cd "$SRC_DIR"

# 2. 构建 libxcb (autotools)
mapfile -t _urls < <(xorg_urls "lib/libxcb-$VER.tar.xz")
fetch_source "$PKG_NAME" libxcb.tar.xz "${_urls[@]}"

# 需要 libXau (xorgproto 提供 headers, 但 libXau 需要单独编译)
mapfile -t _urls < <(xorg_urls "lib/libXau-$LIBXAU_VER.tar.xz")
fetch_source "libXau-$LIBXAU_VER" libxau.tar.xz "${_urls[@]}"
cd "libXau-$LIBXAU_VER"
./configure --host=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXau.so" 2>/dev/null || true
cd "$SRC_DIR"

# 2b. 构建 libXdmcp (libxcb 硬依赖, 提供 XDMCP 协议)
mapfile -t _urls < <(xorg_urls "lib/libXdmcp-$LIBXDMCP_VER.tar.xz")
fetch_source "libXdmcp-$LIBXDMCP_VER" libxdmcp.tar.xz "${_urls[@]}"
cd "libXdmcp-$LIBXDMCP_VER"
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
    --without-xcb-proto-datadir \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PYTHON=python3
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libxcb.so" 2>/dev/null || true

log "  libxcb $VER: $(ls $PREFIX/lib/libxcb*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
