#!/usr/bin/env bash
# Vulkan-Headers 1.4.313 — cmake (仅头文件, 无需编译)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.4.313"
PKG_NAME="Vulkan-Headers-$VER"
SRC_URL="https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" vulkan-headers.tar.gz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

cmake -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_BUILD_TYPE=Release ..
make -j$JOBS
make install

log "  Vulkan-Headers $VER: $(ls $PREFIX/include/vulkan/ 2>/dev/null | wc -l) headers"
