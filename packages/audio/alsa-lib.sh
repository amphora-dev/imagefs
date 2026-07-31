#!/usr/bin/env bash
# alsa-lib 1.2.13 — autotools (参考 MiceWine packages/alsa-lib)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.2.13"
PKG_NAME="alsa-lib-$VER"
SRC_URL="https://www.alsa-project.org/files/pub/lib/alsa-lib-$VER.tar.bz2"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" alsa-lib.tar.bz2 "$SRC_URL"
cd "$PKG_NAME"

# 参考 MiceWine: --with-alsa-ucm-confdir=no, 禁用 python
# Bionic 无 ipc.h, 但 alsa-lib 用户态部分不需要它
./configure \
    --host=$ARCH-linux-android$ANDROID_API \
    --prefix=$PREFIX \
    --libdir=$PREFIX/lib \
    --enable-shared \
    --disable-static \
    --with-alsa-ucm-confdir=no \
    --with-alsa-ucm-prefix=no \
    --with-tmpdir=$PREFIX/tmp \
    --with-pcm-plugins="hw,dmix,dsnoop,plug,route,softvol" \
    --with-ctl-plugins="hw" \
    PYTHON=:
make -j$JOBS LDFLAGS="$LDFLAGS -Wl,--undefined-version"
make install LDFLAGS="$LDFLAGS -Wl,--undefined-version"

# 安装 ALSA 插件开发头文件 (make install 不包含这些)
for hdr in pcm_external.h pcm_ioplug.h pcm_extplug.h pcm_rate.h; do
    [ -f "include/$hdr" ] && cp -f "include/$hdr" "$PREFIX/include/alsa/"
done

$STRIP "$PREFIX/lib/libasound.so" 2>/dev/null || true

log "  alsa-lib $VER: $(ls $PREFIX/lib/libasound.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
