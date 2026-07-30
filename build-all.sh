#!/usr/bin/env bash
# =============================================================================
# build-all.sh — winlator bionic imagefs 完整构建主控
#
# 用法:
#   ./build-all.sh              # 构建全部包
#   ./build-all.sh zlib glib    # 仅构建指定包
#   JOBS=8 ./build-all.sh       # 指定并发数
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ---- 包列表 (按依赖拓扑排序) ----
# 不构建: box64 (WCP)、curl、多余 X 扩展、pulseaudio 栈、ffmpeg (可选 winedmo)、
#         libglvnd (SDL 关桌面 GL；Mesa libGL 来自 extra_libs)
ALL_PACKAGES=(
    # Tier 1
    zlib
    zstd
    libffi
    libexpat
    libpng
    brotli

    # Tier 2
    pcre2
    freetype
    libiconv

    # Tier 3
    fontconfig
    glib

    # Tier 3.5 Bionic / 图形垫片
    android-sysvshm
    libandroid-shmem
    libcxx-shared

    # Tier 4 图形/显示（libxfixes/libxrender 为 libxcursor/libxi 构建依赖）
    xorgproto
    libxcb
    xtrans
    libx11
    libxext
    libxfixes
    libxrender
    libxcursor
    libxi
    libxshmfence
    libdrm
    vulkan-headers
    vulkan-loader

    # Tier 5 加密 + Wine TLS (gnutls)
    openssl
    gmp
    nettle
    gnutls

    # Tier 6 音频 — Amphora 仅 ALSA + android_aserver
    alsa-lib
    alsa-android-aserver

    # Tier 7 输入/多媒体
    sdl2

    # Tier 7.5 Wine 媒体默认路径 (winegstreamer)
    gstreamer
    gst-plugins-base

    # Tier 8 Box64.wcp 垫片
    android-spawn
    android-sysv-semaphore
)

# ---- 命令行参数: 仅构建指定包 ----
if [ $# -gt 0 ]; then
    SELECTED_PACKAGES=("$@")
else
    SELECTED_PACKAGES=("${ALL_PACKAGES[@]}")
fi

# ---- 初始化 ----
section "winlator bionic imagefs 构建系统"
log "架构: $ARCH-linux-android$ANDROID_API"
log "包数量: ${#SELECTED_PACKAGES[@]}"
log "并发: $JOBS"
log "构建目录: $BUILD_DIR"

mkdir -p "$CACHE_DIR" "$SRC_DIR" "$WORK_DIR" "$LOGS_DIR" "$BUILT_DIR"

# ---- 1. 设置 NDK + 交叉编译环境 ----
source "$SCRIPT_DIR/setup-env.sh"

# ---- 2. 创建 rootfs 布局 ----
bash "$SCRIPT_DIR/create-rootfs.sh"

# 增量缓存可能留下已移出包列表的产物 / marker
rm -f "$PREFIX/bin/box64" "$BUILT_DIR"/box64.done
rm -f "$BUILT_DIR"/{pulseaudio,libsndfile,libltdl,ffmpeg,libglvnd,curl,harfbuzz,libxml2}.done
rm -f "$BUILT_DIR"/{libxcomposite,libxinerama,libxxf86vm,libxrandr}.done

# ---- 3. 逐包构建 ----
section "开始编译 ${#SELECTED_PACKAGES[@]} 个包"

TOTAL=${#SELECTED_PACKAGES[@]}
CURRENT=0
SUCCESS=0
FAILED=0
FAILED_PACKAGES=()

for package in "${SELECTED_PACKAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    PKG_SCRIPT="$SCRIPT_DIR/packages/${package}.sh"

    if [ ! -f "$PKG_SCRIPT" ]; then
        error "[$CURRENT/$TOTAL] $package: 构建脚本不存在 ($PKG_SCRIPT)"
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        continue
    fi

    # 增量缓存: marker = 包脚本 sha256
    MARKER="$BUILT_DIR/${package}.done"
    PKG_HASH=$(sha256sum "$PKG_SCRIPT" 2>/dev/null | awk '{print $1}')
    if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$PKG_HASH" ]; then
        log "[$CURRENT/$TOTAL] $package: 已构建 (缓存命中), 跳过"
        SUCCESS=$((SUCCESS + 1))
        continue
    fi

    echo ""
    log "[$CURRENT/$TOTAL] 编译 $package..."

    LOG_FILE="$LOGS_DIR/${package}.log"
    ERR_FILE="$LOGS_DIR/${package}.err"

    if bash "$PKG_SCRIPT" > "$LOG_FILE" 2> "$ERR_FILE"; then
        echo "$PKG_HASH" > "$MARKER"
        SUCCESS=$((SUCCESS + 1))
        log "[$CURRENT/$TOTAL] ✅ $package 完成"
    else
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        error "[$CURRENT/$TOTAL] ❌ $package 失败 (见 $ERR_FILE)"
        echo "    ----- 关键错误行 (grep) -----"
        grep -nEi "error:|undefined reference|cannot find|No package |No such file|fatal|\*\*\* |Permission denied|not found" \
            "$ERR_FILE" "$LOG_FILE" 2>/dev/null | tail -40 | sed 's/^/    /' || echo "    (无匹配关键错误行)"
        echo "    ----- stderr (末尾 50 行) -----"
        tail -50 "$ERR_FILE" 2>/dev/null | sed 's/^/    /'
        echo "    ----- stdout (末尾 20 行) -----"
        tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
        echo "    ----- 错误详情结束 -----"
    fi
done

# ---- 4. 汇总 ----
section "构建汇总"
log "成功: $SUCCESS / $TOTAL"
if [ $FAILED -gt 0 ]; then
    warn "失败: $FAILED (${FAILED_PACKAGES[*]})"
fi

# 统计产物
log "产物统计:"
log "  .so 文件: $(find "$PREFIX/lib" -name "*.so*" 2>/dev/null | wc -l)"
log "  可执行文件: $(find "$PREFIX/bin" -type f 2>/dev/null | wc -l)"
log "  总大小: $(du -sh "$ROOTFS" 2>/dev/null | cut -f1)"

if [ $FAILED -gt 0 ]; then
    error "构建未完全成功，跳过打包"
    exit 1
fi

# ---- 5. 打包 ----
if [ -f "$SCRIPT_DIR/package-imagefs.sh" ]; then
    bash "$SCRIPT_DIR/package-imagefs.sh"
fi

if command -v ccache >/dev/null 2>&1; then
    section "ccache 统计"
    ccache -s || true
fi

section "全部完成"
log "imagefs 构建成功"
exit 0
