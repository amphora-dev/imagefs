#!/usr/bin/env bash
# =============================================================================
# create-rootfs.sh — 创建 merged-usr 布局 + Bionic libc 软链
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

section "创建 staging sysroot 布局 (merged-usr)"

# ---- 清理策略 ----
# 默认增量 (保留已安装产物, 配合 build-all.sh 的 content stamp)。
# REBUILD_ROOTFS=1 必须同时清掉共享 sysroot、host 工具、workdir 和成功 stamp。
# 只删 staging 会让 build-all 继续命中旧 stamp，最终得到一个近乎空的 rootfs。
if [ "${REBUILD_ROOTFS:-0}" = "1" ]; then
    log "REBUILD_ROOTFS=1: 清理所有非下载/ccache 构建状态"
    for path in "$STAGING_DIR" "$TARGET_DIR" "$HOST_DIR" "$WORK_DIR" "$BUILT_DIR"; do
        case "$path" in
            "$BUILD_DIR"/*) rm -rf "$path" ;;
            *)
                error "拒绝清理 BUILD_DIR 外的路径: $path"
                exit 1
                ;;
        esac
    done
fi
mkdir -p "$STAGING_DIR" "$HOST_DIR" "$TARGET_DIR"

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

# ---- Bionic 核心 + 兼容名: 复用宿主 Android /system/lib64 (ln -sf 幂等) ----
# 同一份清单在 package-imagefs.sh 的 staging→target 里复核, 见 config.sh。
link_android_system_libs "$PREFIX/lib"

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

log "staging sysroot 布局创建完成: $STAGING_DIR"
log "  HOST_DIR=$HOST_DIR  TARGET_DIR=$TARGET_DIR"
log "  merged-usr: $(find "$STAGING_DIR" -maxdepth 1 -type l | wc -l) 个软链"
log "  Bionic libc: $(ls -la "$PREFIX/lib/libc.so" 2>/dev/null | awk '{print $NF}')"
