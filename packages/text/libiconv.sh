#!/usr/bin/env bash
# libiconv 1.17 — autotools (静态库, glib 依赖)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.17"
PKG_NAME="libiconv-$VER"
SRC_URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libiconv.tar.gz "$SRC_URL" \
    "https://ftpmirror.gnu.org/libiconv/libiconv-$VER.tar.gz"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# libiconv 只构建静态库 (Bionic 自带 iconv, 但 glib 需要 libiconv.a)
../configure --host=${ARCH}-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-static --disable-shared \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install

log "  libiconv $VER: $(ls $PREFIX/lib/libiconv.a 2>/dev/null && echo 'static OK')"
