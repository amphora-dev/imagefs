#!/usr/bin/env bash
# libXxf86vm 1.1.6 — autotools
#
# 只有 mesa-gl 需要它, 而且只在 -Dglx=dri 下: Mesa 的 meson.build 在
# `with_glx == 'dri'` + `with_dri_platform == 'drm'` + `with_glx_direct` 时
# 无条件 `dependency('xxf86vm')`, libGL 用它做 XF86VidMode 的 gamma/伽马斜坡查询。
# 走 -Dglx=disabled 可以省掉本包, 但那样就不产 libGL.so.1, 旧 Wine (<10.17,
# 走 GLX 而非 EGL) 会连 dlopen 的目标都没有。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.1.6"
PKG_NAME="libXxf86vm-$VER"
SRC_URL="https://xorg.freedesktop.org/archive/individual/lib/libXxf86vm-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libxxf86vm.tar.xz "$SRC_URL" \
    "$(echo "$SRC_URL" | sed s#xorg.freedesktop.org#ftp.x.org#)"
cd "$PKG_NAME"

./configure --host=$ARCH-linux-android host_alias=$ARCH-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static \
    --enable-malloc0returnsnull \
    xorg_cv_malloc0_returns_null=yes \
    CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libXxf86vm.so" 2>/dev/null || true

log "  libXxf86vm $VER: $(ls $PREFIX/lib/libXxf86vm.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
