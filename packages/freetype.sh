#!/usr/bin/env bash
# freetype 2.13.3 — meson
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.13.3"
PKG_NAME="freetype-$VER"
SRC_URL="https://downloads.sourceforge.net/freetype/freetype-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" freetype.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Dbrotli=enabled -Dbzip2=disabled -Dharfbuzz=disabled \
    -Dpng=enabled -Dzlib=enabled ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libfreetype.so" 2>/dev/null || true

log "  freetype $VER: $(ls $PREFIX/lib/libfreetype.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
