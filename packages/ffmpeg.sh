#!/usr/bin/env bash
# FFmpeg 8.0 — 自定义 configure。给 Wine 的 winedmo.so 提供解复用/解码。
#
# 版本必须是 8.0: Proton-10.0-4 的 winedmo.so NEEDED 写死了
#   libavutil.so.60  libavcodec.so.62  libavformat.so.62
# 官方 imagefs 带的是 FFmpeg 7.1 (libavutil.so.59 / libavcodec.so.61 /
# libavformat.so.61), soname 不匹配, 所以官方镜像里 winedmo 本来就加载不了。
# 换 FFmpeg 大版本前先核对 winedmo.so 的 NEEDED, 别再错配一轮。
#
# winedmo 只做解复用+解码, 所以关掉 encoder/muxer/programs/avdevice/avfilter,
# 体积远小于官方那份 (官方还捎带了 ffmpeg/ffprobe 可执行文件与全套编码器)。
#
# 选项按 FFmpeg 8.0 的 ./configure --help 实测校对过。注意几个不存在的写法:
#   --disable-postproc  8.0 已无此开关 (postproc 需 GPL, 默认不编)
#   --enable-decoders / --enable-demuxers / --enable-parsers  不是有效选项;
#     这三类默认全开, 无需显式启用 (要裁剪得用 --disable-everything 再逐个 enable)。
# 之前误加这四个导致 "Unknown option --disable-postproc" 整包失败。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="8.0"
PKG_NAME="ffmpeg-$VER"
SRC_URL="https://ffmpeg.org/releases/ffmpeg-$VER.tar.xz"

cd "$SRC_DIR"
# ffmpeg.org 在 CNB runner 上不通 (本地 200), 且没有保持目录名的镜像, 所以备用源
# 用 GitHub 的标签归档 —— 它解出的顶层是 FFmpeg-n8.0/, 由 fetch_source 自动
# 纠正为 $PKG_NAME。
fetch_source "$PKG_NAME" ffmpeg.tar.xz \
    "$SRC_URL" \
    "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$VER.tar.gz"
cd "$PKG_NAME"

# FFmpeg 自带 configure (非 autotools), 交叉编译参数是它自己的一套。
./configure \
    --prefix=$PREFIX \
    --libdir=$PREFIX/lib \
    --enable-cross-compile \
    --target-os=android \
    --arch=aarch64 \
    --cpu=armv8-a \
    --cc="$CC" \
    --cxx="$CXX" \
    --ar="$AR" \
    --nm="$NM" \
    --ranlib="$RANLIB" \
    --strip="$STRIP" \
    --extra-cflags="-fPIC -O2 -I$PREFIX/include" \
    --extra-ldflags="-Wl,-rpath,/usr/lib -L$PREFIX/lib" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-avdevice \
    --disable-avfilter \
    --disable-swscale \
    --disable-encoders \
    --disable-muxers \
    --disable-network \
    --disable-debug \
    --enable-protocol=file \
    --enable-pic

make -j$JOBS
make install

$STRIP "$PREFIX"/lib/libav*.so "$PREFIX"/lib/libsw*.so 2>/dev/null || true

# winedmo.so 的 NEEDED 写死这三个带版本的文件名 (8.0 的 soname major:
# avutil=60, avcodec=62, avformat=62 —— 已对源码 version.h 核对)。Android target
# 下不一定生成版本软链, 缺了 winedmo 就加载不到。
ensure_soname_link "libavutil.so.60"   "libavutil.so"
ensure_soname_link "libavcodec.so.62"  "libavcodec.so"
ensure_soname_link "libavformat.so.62" "libavformat.so"

log "  ffmpeg $VER: $(ls $PREFIX/lib/libav*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
