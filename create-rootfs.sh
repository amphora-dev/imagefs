#!/usr/bin/env bash
# =============================================================================
# create-rootfs.sh — 创建 merged-usr 布局 + Bionic libc 软链
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

section "创建 merged-usr rootfs 布局"

# ---- 清理策略 ----
# 默认增量 (保留已安装产物, 配合 build-all.sh 的 .done 缓存)。
# REBUILD_ROOTFS=1 时全清重建 (用于干净构建或缓存损坏时)。
if [ "${REBUILD_ROOTFS:-0}" = "1" ]; then
    log "REBUILD_ROOTFS=1: 全清重建 rootfs"
    rm -rf "$ROOTFS"
fi
mkdir -p "$ROOTFS"

# ---- usr 子目录 ----
mkdir -p "$PREFIX"/{bin,lib,etc,share,tmp,include,var/{cache,run}}
mkdir -p "$PREFIX/lib/pkgconfig"
mkdir -p "$PREFIX/include"

# ---- merged-usr 软链 (ln -sf 幂等) ----
cd "$ROOTFS"
ln -sf usr/bin   bin
ln -sf usr/etc   etc
ln -sf usr/lib   lib
ln -sf usr/share share
ln -sf usr/tmp   tmp

# ---- 顶层目录 ----
mkdir -p "$ROOTFS"/{home,opt,storage,proc,sys,dev}
mkdir -p "$ROOTFS/home/xuser"

# ---- Bionic 核心: 复用宿主 Android /system/lib64 (ln -sf 幂等) ----
ln -sf /system/lib64/libc.so    "$PREFIX/lib/libc.so"
ln -sf /system/lib64/libdl.so   "$PREFIX/lib/libdl.so"
ln -sf /system/lib64/libm.so    "$PREFIX/lib/libm.so"
ln -sf /system/lib64/liblog.so  "$PREFIX/lib/liblog.so"
ln -sf /system/lib64/libEGL.so  "$PREFIX/lib/libEGL.so"
ln -sf /system/lib64/libGLESv2.so "$PREFIX/lib/libGLESv2.so"
ln -sf /system/lib64/libandroid.so "$PREFIX/lib/libandroid.so"
ln -sf /system/lib64/libOpenSLES.so "$PREFIX/lib/libOpenSLES.so"

# ---- Bionic 兼容: pthread/rt 内置于 libc (ln -sf 幂等) ----
ln -sf /system/lib64/libc.so  "$PREFIX/lib/libpthread.so"
ln -sf /system/lib64/libc.so  "$PREFIX/lib/libpthread.so.0"
ln -sf /system/lib64/libc.so  "$PREFIX/lib/librt.so"
ln -sf /system/lib64/libc.so  "$PREFIX/lib/librt.so.1"

# ---- tmp 子目录 ----
mkdir -p "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.sound" "$PREFIX/tmp/.sysvshm"
printf 'adapter=mock\n' > "$PREFIX/tmp/adapterinfo"

# ---- etc 配置 ----
cat > "$PREFIX/etc/os-release" <<EOF
NAME="Winlator Bionic ImageFS"
ID=winlator-bionic
PRETTY_NAME="Winlator Bionic ImageFS"
VERSION_ID="7.1.4"
EOF

# ---- fonts 目录 ----
mkdir -p "$PREFIX/etc/fonts"/conf.d
mkdir -p "$PREFIX/share/fonts"

# ---- alsa 配置占位 ----
mkdir -p "$PREFIX/etc/alsa/conf.d"
mkdir -p "$PREFIX/lib/alsa-lib"

# ---- vulkan 层目录 ----
mkdir -p "$PREFIX/share/vulkan"/{explicit_layer.d,implicit_layer.d}

# ---- gstreamer 插件目录 ----
mkdir -p "$PREFIX/lib/gstreamer-1.0"

log "rootfs 布局创建完成: $ROOTFS"
log "  merged-usr: $(ls -la "$ROOTFS" | grep '\->' | wc -l) 个软链"
log "  Bionic libc: $(ls -la "$PREFIX/lib/libc.so" 2>/dev/null | awk '{print $NF}')"
