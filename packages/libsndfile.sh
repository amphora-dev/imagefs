#!/usr/bin/env bash
# libsndfile 1.2.2 — cmake (PulseAudio 硬依赖)
# 依赖: zlib (已构建)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.2.2"
PKG_NAME="libsndfile-$VER"
SRC_URL="https://github.com/libsndfile/libsndfile/releases/download/$VER/libsndfile-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libsndfile.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 禁用所有可选编解码器, 仅保留基本格式 (WAV, AIFF, etc.)
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_FIND_ROOT_PATH=$PREFIX \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_PROGRAMS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DENABLE_EXTERNAL_LIBS=OFF \
    -DENABLE_MPEG=OFF ..
make -j$JOBS
make install

# 修正 SONAME 为 libsndfile.so (原始 winlator bionic 不使用版本号)
ACTUAL=$(readlink -f "$PREFIX/lib/libsndfile.so")
patchelf --set-soname libsndfile.so "$ACTUAL"
# 重建符号链接: libsndfile.so 为真实文件, 移除版本号符号链接
cp -f "$ACTUAL" "$PREFIX/lib/libsndfile.so.tmp"
rm -f "$PREFIX/lib/libsndfile.so" "$PREFIX/lib/libsndfile.so.1" "$PREFIX/lib/libsndfile.so.1.0.37"
mv "$PREFIX/lib/libsndfile.so.tmp" "$PREFIX/lib/libsndfile.so"
$STRIP "$PREFIX/lib/libsndfile.so" 2>/dev/null || true

log "  libsndfile $VER: SONAME=libsndfile.so (匹配原始 winlator bionic)"
