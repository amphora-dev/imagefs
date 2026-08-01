#!/usr/bin/env bash
# =============================================================================
# build-all.sh — winlator bionic imagefs 完整构建主控
#
# Buildroot-lite:
#   - STAGING_DIR (sysroot) vs TARGET_DIR (runtime image)
#   - packages/depends.conf + topo order + content stamps
#   - selecting a package pulls transitive DEPENDS
#
# 用法:
#   ./build-all.sh              # 构建全部包
#   ./build-all.sh zlib glib    # 构建指定包及其依赖
#   JOBS=8 ./build-all.sh       # 指定并发数
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/pkg.sh"

# ---- 包列表 (默认全集；实际构建顺序由 depends.conf topo 决定) ----
# 不构建: box64 (WCP)、curl、多余 X 扩展、pulseaudio 栈、ffmpeg、libglvnd…
ALL_PACKAGES=(
    zlib
    zstd
    libffi
    libexpat
    libpng
    brotli

    pcre2
    freetype
    libiconv

    fontconfig
    glib

    android-sysvshm
    libandroid-shmem
    libcxx-shared

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

    openssl
    gmp
    nettle
    gnutls

    alsa-lib
    alsa-android-aserver

    sdl2

    gstreamer
    gst-plugins-base

    android-spawn
    android-sysv-semaphore
)

pkg_load_depends

# ---- 命令行: 指定包时自动带上传递依赖，再 topo 排序 ----
if [ $# -gt 0 ]; then
    mapfile -t _expanded < <(pkg_expand_with_deps "$@")
    mapfile -t SELECTED_PACKAGES < <(pkg_topo_sort "${_expanded[@]}")
else
    mapfile -t SELECTED_PACKAGES < <(pkg_topo_sort "${ALL_PACKAGES[@]}")
fi

# ---- 初始化 ----
section "winlator bionic imagefs 构建系统 (Buildroot-lite)"
log "架构: $ARCH-linux-android$ANDROID_API"
log "包数量: ${#SELECTED_PACKAGES[@]}"
log "并发: $JOBS"
log "构建目录: $BUILD_DIR"
log "  HOST_DIR    = $HOST_DIR"
log "  STAGING_DIR = $STAGING_DIR  (sysroot / 增量编译)"
log "  TARGET_DIR  = $TARGET_DIR   (runtime → imagefs.txz)"

mkdir -p "$CACHE_DIR" "$SRC_DIR" "$WORK_DIR" "$LOGS_DIR" "$BUILT_DIR" \
    "$HOST_DIR" "$STAGING_DIR" "$TARGET_DIR"

# ---- 1. 设置 NDK + 交叉编译环境 ----
source "$SCRIPT_DIR/setup-env.sh"

# ---- 2. 创建 staging rootfs 布局 ----
bash "$SCRIPT_DIR/create-rootfs.sh"

# 增量缓存可能留下已移出包列表的产物 / marker
rm -f "$PREFIX/bin/box64" "$BUILT_DIR"/box64.done
rm -f "$BUILT_DIR"/{pulseaudio,libsndfile,libltdl,ffmpeg,libglvnd,curl,harfbuzz,libxml2}.done
rm -f "$BUILT_DIR"/{libxcomposite,libxinerama,libxxf86vm,libxrandr}.done

# ---- 3. 逐包构建 (topo 序；content stamp 含 DEPENDS) ----
section "开始编译 ${#SELECTED_PACKAGES[@]} 个包"

TOTAL=${#SELECTED_PACKAGES[@]}
CURRENT=0
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_PACKAGES=()

for package in "${SELECTED_PACKAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    PKG_SCRIPT="$(pkg_recipe_path "$package")" || {
        error "[$CURRENT/$TOTAL] $package: 构建脚本不存在 (packages/*/${package}.sh)"
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        continue
    }

    if [ ! -f "$PKG_SCRIPT" ]; then
        error "[$CURRENT/$TOTAL] $package: 构建脚本不存在 ($PKG_SCRIPT)"
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        continue
    fi

    if pkg_is_up_to_date "$package"; then
        log "[$CURRENT/$TOTAL] $package: 已构建 (content stamp 命中), 跳过"
        SUCCESS=$((SUCCESS + 1))
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo ""
    deps="$(pkg_deps_of "$package")"
    if [ -n "$deps" ]; then
        log "[$CURRENT/$TOTAL] 编译 $package (depends: $deps)..."
    else
        log "[$CURRENT/$TOTAL] 编译 $package..."
    fi

    LOG_FILE="$LOGS_DIR/${package}.log"
    ERR_FILE="$LOGS_DIR/${package}.err"

    if bash "$PKG_SCRIPT" > "$LOG_FILE" 2> "$ERR_FILE"; then
        pkg_write_stamp "$package"
        SUCCESS=$((SUCCESS + 1))
        log "[$CURRENT/$TOTAL] ✅ $package 完成"
    else
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        rm -f "$(pkg_stamp_path "$package")"
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
log "成功: $SUCCESS / $TOTAL (缓存跳过: $SKIPPED)"
if [ $FAILED -gt 0 ]; then
    warn "失败: $FAILED (${FAILED_PACKAGES[*]})"
fi

log "产物统计 (staging sysroot):"
log "  .so 文件: $(find "$PREFIX/lib" -name "*.so*" 2>/dev/null | wc -l)"
log "  可执行文件: $(find "$PREFIX/bin" -type f 2>/dev/null | wc -l)"
log "  staging 大小: $(du -sh "$STAGING_DIR" 2>/dev/null | cut -f1)"

if [ $FAILED -gt 0 ]; then
    error "构建未完全成功，跳过打包"
    exit 1
fi

# ---- 5. staging → target 裁剪打包 ----
# L1 leaves (e.g. wrapper) only need staging as a sysroot — set SKIP_IMAGEFS_PACKAGE=1.
if [ "${SKIP_IMAGEFS_PACKAGE:-0}" = "1" ]; then
    log "SKIP_IMAGEFS_PACKAGE=1 — not packing imagefs.txz"
elif [ -f "$SCRIPT_DIR/package-imagefs.sh" ]; then
    bash "$SCRIPT_DIR/package-imagefs.sh"
fi

if command -v ccache >/dev/null 2>&1; then
    section "ccache 统计"
    ccache -s || true
fi

section "全部完成"
log "imagefs 构建成功"
exit 0
