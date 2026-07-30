#!/usr/bin/env bash
# gst-plugins-base 1.26.1 — meson。补齐 winegstreamer.so 剩下的 5 个 NEEDED:
#   libgstapp-1.0  libgstaudio-1.0  libgstvideo-1.0  libgsttag-1.0  libgstgl-1.0
#
# libgstgl 需要 GL/EGL, 走 imagefs 里的 libglvnd (Tier 4) + Bionic 的 libEGL 软链。
#
# 注意 audio / video / tag **不是** meson option (1.26.1 实测: 只有 app / alsa /
# gl / gl_api / gl_platform / gl_winsys / ogg / opus / theora / vorbis / pango /
# x11 ... 这些)。libgstaudio / libgstvideo / libgsttag 是核心库, 无条件构建。
# 之前误加 -Daudio=enabled 导致 "ERROR: Unknown option: audio" 整包失败。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.26.1"
PKG_NAME="gst-plugins-base-$VER"
SRC_URL="https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" gst-plugins-base.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 只要 winegstreamer 需要的那几个库, 编解码插件交给 Wine 自己的 DirectShow /
# Media Foundation 路径, 不在这里堆 codec (那是官方 imagefs 体积失控的原因之一)。
meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Dintrospection=disabled \
    -Ddoc=disabled \
    -Dtests=disabled \
    -Dexamples=disabled \
    -Dnls=disabled \
    -Dorc=disabled \
    -Dgl=enabled \
    -Dgl_platform=egl \
    -Dgl_winsys=egl \
    -Dgl_api=gles2 \
    -Dapp=enabled \
    -Dalsa=enabled \
    -Dpango=disabled \
    -Dcdparanoia=disabled \
    -Dlibvisual=disabled \
    -Dogg=disabled \
    -Dopus=disabled \
    -Dtheora=disabled \
    -Dvorbis=disabled \
    -Dx11=disabled ..
ninja -j$JOBS
ninja install

$STRIP "$PREFIX"/lib/libgst{app,audio,video,tag,gl,pbutils,riff,rtp,rtsp,sdp,allocators}-1.0.so 2>/dev/null || true

log "  gst-plugins-base $VER: $(ls $PREFIX/lib/libgst{app,audio,video,tag,gl}-1.0.so 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
