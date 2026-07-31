#!/usr/bin/env bash
# libdrm 2.4.124 — meson (参考 MiceWine packages/libdrm)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.4.124"
PKG_NAME="libdrm-$VER"
SRC_URL="https://dri.freedesktop.org/libdrm/libdrm-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libdrm.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 参考 MiceWine: 禁用 intel/radeon/amdgpu/exynos/freedreno/vc4/nouveau/vmwgfx
# 仅启用 kgsl (Adreno) + 无效能 backend
meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Ddefault_library=shared \
    -Dintel=disabled \
    -Dradeon=disabled \
    -Damdgpu=disabled \
    -Dexynos=disabled \
    -Dfreedreno=disabled \
    -Dvc4=disabled \
    -Dvmwgfx=disabled \
    -Dnouveau=disabled \
    -Dman-pages=disabled \
    -Dvalgrind=disabled \
    -Dtests=false ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libdrm.so" 2>/dev/null || true

log "  libdrm $VER: $(ls $PREFIX/lib/libdrm*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
