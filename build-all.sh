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

    # Tier 3.5: Bionic 兼容垫片 (X11/图形库依赖)
    # android-sysvshm 提供 libsysvshm.so (shmget/shmat/shmdt/shmctl),
    # Bionic 无 System V 共享内存, libX11 的 MIT-SHM 路径链接期需要这些符号。
    # 必须在 libx11 之前构建。
    android-sysvshm

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

    # Tier 5: 网络/加密 (pulseaudio 的 RAOP 模块依赖 openssl 头文件, 须在音频之前)
    openssl
    curl

    # Tier 6: 音频
    alsa-lib
    libsndfile
    libltdl
    pulseaudio
    alsa-android-aserver

    # Tier 7: 多媒体
    sdl2

    # Tier 8: Bionic 兼容库 (box64 依赖)
    android-spawn
    android-sysv-semaphore

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
        # ---- 诊断输出 ----
        # 关键: 真正的 make/install/link 错误在 stderr/stdout **末尾**, 不是开头
        # (开头通常是大量 configure warning, head 会把真错误挤掉)
        # 1) 先 grep 出所有关键错误行 (最快定位根因)
        echo "    ----- 关键错误行 (grep) -----"
        grep -nEi "error:|undefined reference|cannot find|No package |No such file|fatal|\*\*\* |Permission denied|not found" \
            "$ERR_FILE" "$LOG_FILE" 2>/dev/null | tail -40 | sed 's/^/    /' || echo "    (无匹配关键错误行)"
        # 2) stderr 末尾 50 行 (真正的失败点)
        echo "    ----- stderr (末尾 50 行) -----"
        tail -50 "$ERR_FILE" 2>/dev/null | sed 's/^/    /'
        # 3) stdout 末尾 20 行 (失败时正在执行的步骤)
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
