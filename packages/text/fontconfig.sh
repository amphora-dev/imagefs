#!/usr/bin/env bash
# fontconfig 2.15.0 — meson
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.15.0"
PKG_NAME="fontconfig-$VER"
SRC_URL="https://www.freedesktop.org/software/fontconfig/release/fontconfig-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" fontconfig.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Ddefault-fonts-dirs=/usr/share/fonts \
    -Dcache-dir=/usr/var/cache/fontconfig \
    -Dtests=disabled -Ddoc=disabled ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libfontconfig.so" 2>/dev/null || true

log "  fontconfig $VER: $(ls $PREFIX/lib/libfontconfig.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
