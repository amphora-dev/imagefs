#!/usr/bin/env bash
# harfbuzz 10.2.0 — meson
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="10.2.0"
PKG_NAME="harfbuzz-$VER"
SRC_URL="https://github.com/harfbuzz/harfbuzz/releases/download/$VER/harfbuzz-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o harfbuzz.tar.xz && tar xf harfbuzz.tar.xz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Dfreetype=enabled -Dglib=disabled -Dicu=disabled \
    -Dcairo=disabled -Dgobject=disabled \
    -Dtests=disabled -Dbenchmark=disabled -Ddocs=disabled ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libharfbuzz.so" 2>/dev/null || true

log "  harfbuzz $VER: $(ls $PREFIX/lib/libharfbuzz.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
