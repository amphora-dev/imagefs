#!/usr/bin/env bash
# nettle 3.10.1 — autotools. 提供 libnettle + libhogweed (gnutls 的密码学后端)。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="3.10.1"
PKG_NAME="nettle-$VER"
SRC_URL="https://ftp.gnu.org/gnu/nettle/nettle-$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" nettle.tar.gz "$SRC_URL"
cd "$PKG_NAME"

# libhogweed 需要 gmp 的头文件与库 (已在 Tier 前置构建)。
export CFLAGS="$CFLAGS -I$PREFIX/include"
export LDFLAGS="$LDFLAGS -L$PREFIX/lib"

./configure \
    --host=${ARCH}-linux-android${ANDROID_API} \
    --prefix=$PREFIX \
    --libdir=$PREFIX/lib \
    --enable-shared \
    --disable-static \
    --disable-documentation \
    --disable-openssl \
    --with-include-path=$PREFIX/include \
    --with-lib-path=$PREFIX/lib

make -j$JOBS
make install

$STRIP "$PREFIX/lib/libnettle.so" "$PREFIX/lib/libhogweed.so" 2>/dev/null || true

# libhogweed 是公钥部分, 只在 configure 找到 gmp 时才构建, 而缺了它 nettle 仍会
# "构建成功"。gnutls 随后会以
#   "configure: error: Nettle lacks the required rsa_sec_decrypt function"
# 失败 —— 报错指向 nettle, 根因却在 gmp。所以这里直接断言, 让失败落在正确的包上。
if [ ! -e "$PREFIX/lib/libhogweed.so" ]; then
    error "  缺 libhogweed.so: configure 未找到 gmp, 检查 gmp 包是否构建成功"
    exit 1
fi

log "  nettle $VER: $(ls $PREFIX/lib/lib{nettle,hogweed}.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
