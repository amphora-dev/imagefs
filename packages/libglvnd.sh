#!/usr/bin/env bash
# libglvnd 1.7.0 — meson (EGL/GL dispatch)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.7.0"
PKG_NAME="libglvnd-v$VER"
SRC_URL="https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v$VER/libglvnd-v$VER.tar.gz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libglvnd.tar.gz && tar xf libglvnd.tar.gz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Ddefault_library=shared \
    -Dglx=enabled \
    -Degl=true \
    -Dgles1=true \
    -Dgles2=true \
    -Dasm=disabled \
    -Dtls=false \
    -Dheaders=true ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libEGL.so" "$PREFIX/lib/libGL.so" \
       "$PREFIX/lib/libGLESv2.so" "$PREFIX/lib/libGLdispatch.so" 2>/dev/null || true

log "  libglvnd $VER: $(ls $PREFIX/lib/lib{EGL,GL,GLES*,GLdispatch}.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
