#!/usr/bin/env bash
# libX11 1.8.10 — autotools (release tarball 不含 meson.build)
#
# Bionic 适配 (参考 MiceWine-Packages/packages/libX11):
#   1. host_alias=$TRIPLE   — 确保 configure 正确识别交叉主机
#   2. -lsysvshm            — 链接 ashmem 版 System V 共享内存 (Bionic 无 shmget/shmat)
#                             libsysvshm.so 由 android-sysvshm 包提供 (构建顺序已提前)
#   3. XTHREADLIB -pthread  — Bionic 把 pthread 内建在 libc, 不存在独立 libpthread
#   4. libXcursor SONAME    — 去版本号 (winlator imagefs 不带 .so.N 版本号)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.8.10"
PKG_NAME="libX11-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libX11-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o libx11.tar.xz && tar xf libx11.tar.xz; }
cd "$PKG_NAME"

# ---- Bionic 补丁 (幂等 sed) ----
# CrGlCur.c: dlopen 的 libXcursor 去版本号
if [ -f src/CrGlCur.c ]; then
    sed -i 's/"libXcursor\.so\.1"/"libXcursor.so"/' src/CrGlCur.c
fi

# ---- configure ----
# host_alias 显式指定; LDFLAGS 追加 -lsysvshm 提供 SysV 共享内存符号
./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android \
    --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --disable-specs \
    --without-xmlto --without-fop --without-xsltproc \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS -lsysvshm"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libX11.so" 2>/dev/null || true

log "  libX11 $VER: $(ls $PREFIX/lib/libX11.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
