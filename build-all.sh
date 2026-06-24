#!/usr/bin/env bash
# =============================================================================
# build-all.sh — winlator bionic imagefs 完整构建主控
#
# 参考:
#   - MiceWine-Packages build-all.sh (包管理系统结构)
#   - 官方 imagefs ELF 取证 (Bionic libc + merged-usr + NDK r29)
#   - termux-packages (Bionic port 补丁方法论)
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
ALL_PACKAGES=(
    # Tier 1: 无依赖的基础库
    zlib
    libffi
    libexpat
    libpng
    brotli

    # Tier 2: 依赖 Tier 1
    pcre2
    freetype
    libiconv
    libxml2

    # Tier 3: 依赖 Tier 2
    fontconfig
    harfbuzz
    glib

    # Tier 4: 图形/显示
    xorgproto
    libxcb
    xtrans
    libx11
    libxext
    libxfixes
    libxrender
    libxrandr
    libxcomposite
    libxcursor
    libxi
    libxinerama
    libxxf86vm
    libxshmfence
    libdrm
    vulkan-headers
    vulkan-loader
    libglvnd

    # Tier 5: 音频
    alsa-lib
    libsndfile
    libltdl
    pulseaudio
    alsa-android-aserver

    # Tier 6: 网络/加密
    openssl
    curl

    # Tier 7: 多媒体
    sdl2

    # Tier 8: Bionic 兼容库 (box64 依赖)
    android-spawn
    android-sysv-semaphore
    android-sysvshm

    # Tier 9: 模拟器
    box64
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

    # 检查是否已构建
    MARKER="$BUILT_DIR/${package}.done"
    if [ -f "$MARKER" ]; then
        log "[$CURRENT/$TOTAL] $package: 已构建, 跳过"
        SUCCESS=$((SUCCESS + 1))
        continue
    fi

    echo ""
    log "[$CURRENT/$TOTAL] 编译 $package..."

    # 执行构建
    LOG_FILE="$LOGS_DIR/${package}.log"
    ERR_FILE="$LOGS_DIR/${package}.err"

    if bash "$PKG_SCRIPT" > "$LOG_FILE" 2> "$ERR_FILE"; then
        touch "$MARKER"
        SUCCESS=$((SUCCESS + 1))
        # 显示产物
        NEW_LIBS=$(find "$PREFIX/lib" -name "*.so*" -newer "$MARKER" 2>/dev/null | wc -l)
        log "[$CURRENT/$TOTAL] ✅ $package 完成"
    else
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        error "[$CURRENT/$TOTAL] ❌ $package 失败 (见 $ERR_FILE)"
        # 显示错误详情 (stderr 前 60 行 + stdout 末尾 30 行, 便于 CI 诊断)
        echo "    ----- stderr (前 60 行) -----"
        head -60 "$ERR_FILE" 2>/dev/null | sed 's/^/    /'
        echo "    ----- stdout (末尾 30 行) -----"
        tail -30 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
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
SO_COUNT=$(find "$PREFIX/lib" -name "*.so*" -type f 2>/dev/null | wc -l)
SO_LINK_COUNT=$(find "$PREFIX/lib" -name "*.so*" -type l 2>/dev/null | wc -l)
BIN_COUNT=$(find "$PREFIX/bin" -type f 2>/dev/null | wc -l)
PC_COUNT=$(find "$PREFIX/lib/pkgconfig" -name "*.pc" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$ROOTFS" 2>/dev/null | awk '{print $1}')

echo ""
echo "  .so 文件:     $SO_COUNT"
echo "  .so 软链:     $SO_LINK_COUNT"
echo "  可执行文件:   $BIN_COUNT"
echo "  pkgconfig:    $PC_COUNT"
echo "  总大小:       $TOTAL_SIZE"

# ---- 5. 打包 ----
if [ $FAILED -eq 0 ] || [ $SUCCESS -gt 5 ]; then
    bash "$SCRIPT_DIR/package-imagefs.sh"
else
    warn "失败包过多, 跳过打包。请检查日志后重试。"
fi

section "完成"
