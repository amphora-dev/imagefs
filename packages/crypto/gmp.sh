#!/usr/bin/env bash
# GMP 6.3.0 — autotools. nettle/gnutls 的大数运算依赖。
# Wine 的 bcrypt/secur32 dlopen libgnutls.so, 这条链缺任一环 TLS 就不可用。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="6.3.0"
PKG_NAME="gmp-$VER"
SRC_URL="https://gmplib.org/download/gmp/gmp-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" gmp.tar.xz "https://ftp.gnu.org/gnu/gmp/gmp-$VER.tar.xz" \
    "$SRC_URL"
cd "$PKG_NAME"

# 交叉编译时 GMP 的 CPU 探测会跑目标二进制, 显式给 host/build 跳过。
#
# 不能同时给 --enable-fat 与 --disable-assembly: GMP 会直接报
# "when doing a fat build, disabling assembly will not work"。--enable-fat 本来
# 也是 x86 的运行期 CPU 分派特性, 对 aarch64 没意义, 所以只保留
# --disable-assembly (交叉编译下最稳, 代价是大数运算慢一些; gnutls 的用量不敏感)。
./configure \
    --host=${ARCH}-linux-android${ANDROID_API} \
    --build="$(./configfsf.guess)" \
    --prefix=$PREFIX \
    --libdir=$PREFIX/lib \
    --enable-shared \
    --disable-static \
    --disable-assembly

make -j$JOBS
make install

$STRIP "$PREFIX/lib/libgmp.so" 2>/dev/null || true

log "  gmp $VER: $(ls $PREFIX/lib/libgmp.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
