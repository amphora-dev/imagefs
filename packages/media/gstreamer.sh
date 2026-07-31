#!/usr/bin/env bash
# GStreamer 1.26.1 (core) — meson。给 Wine 的 winegstreamer.so 提供核心库。
#
# winegstreamer.so 的 NEEDED 要求 7 个库, 其中 libgstreamer-1.0 / libgstbase-1.0
# 来自 core, 另外 5 个 (app/audio/video/tag/gl) 来自 gst-plugins-base, 见
# gst-plugins-base.sh。GStreamer 1.x 的 soname 一直是 .so.0, 所以小版本差异
# 不会像 FFmpeg 那样撞 soname (官方 imagefs 用的是同一个 1.26.1)。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.26.1"
PKG_NAME="gstreamer-$VER"
SRC_URL="https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" gstreamer.tar.xz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# Bionic 无 ptrace-based 的 gst-ptp-helper 需求, 也不需要注册表以外的工具;
# introspection/doc/tests/examples 全关, 只出核心库。
meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Dintrospection=disabled \
    -Ddoc=disabled \
    -Dtests=disabled \
    -Dexamples=disabled \
    -Dbenchmarks=disabled \
    -Dtools=disabled \
    -Dptp-helper-permissions=none \
    -Dgst_debug=false \
    -Dnls=disabled ..
ninja -j$JOBS
ninja install

$STRIP "$PREFIX"/lib/libgstreamer-1.0.so "$PREFIX"/lib/libgstbase-1.0.so \
       "$PREFIX"/lib/libgstcontroller-1.0.so "$PREFIX"/lib/libgstnet-1.0.so 2>/dev/null || true

log "  gstreamer $VER: $(ls $PREFIX/lib/libgst*-1.0.so 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
