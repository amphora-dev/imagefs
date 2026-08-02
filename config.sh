# shellcheck shell=bash
# =============================================================================
# config.sh — winlator bionic imagefs 构建系统全局配置
# =============================================================================
# 参考: MiceWine-Packages build-all.sh + 官方 imagefs ELF 取证
# 目标: aarch64-linux-android (Bionic libc), merged-usr 布局
# =============================================================================

# ---- Android NDK ----
# CI：用 GitHub runner 自带的 NDK（ANDROID_NDK_LATEST_HOME / ANDROID_NDK_HOME）。
# 本地：可 export ANDROID_NDK_HOME；都没有时 setup-env.sh 才下载下面这份。
NDK_VERSION="r29"
NDK_URL="https://dl.google.com/android/repository/android-ndk-r29-linux.zip"
NDK_FILENAME="android-ndk-r29-linux.zip"

# ---- 目标架构 ----
ARCH="${ARCH:-aarch64}"
ANDROID_API="${ANDROID_API:-26}"

# ---- 路径 (Buildroot-inspired layout) ----
#   host/     — host tools (do not ship in imagefs.txz)
#   staging/  — cross-compile sysroot (headers + libs + pkgconfig)
#   target/   — runtime rootfs assembled for packaging
BUILD_DIR="${BUILD_DIR:-/tmp/imagefs-build}"
CACHE_DIR="$BUILD_DIR/cache"
SRC_DIR="$BUILD_DIR/src"
WORK_DIR="$BUILD_DIR/workdir"
LOGS_DIR="$BUILD_DIR/logs"
HOST_DIR="$BUILD_DIR/host"
STAGING_DIR="$BUILD_DIR/staging"
TARGET_DIR="$BUILD_DIR/target"
# Back-compat aliases: package scripts still use ROOTFS / PREFIX.
ROOTFS="$STAGING_DIR"
PREFIX="$STAGING_DIR/usr"
BUILT_DIR="$BUILD_DIR/built-pkgs"

# Migrate leftover path from pre-Buildroot-lite layout.
if [ -d "$BUILD_DIR/imagefs" ] && [ ! -e "$STAGING_DIR" ]; then
    mv "$BUILD_DIR/imagefs" "$STAGING_DIR"
fi

# ---- imagefs 打包 ----
IMAGEFS_NAME="imagefs.txz"
IMAGEFS_PART_SIZE=52428800  # 50MB 分卷

# ---- 并发 ----
JOBS="${JOBS:-$(nproc)}"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()   { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARN:${NC} $*"; }
error()  { echo -e "${RED}[$(date +%H:%M:%S)] ERROR:${NC} $*" >&2; }
section(){ echo -e "\n${CYAN}══════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}\n"; }

# ---- soname 软链补齐 ----
# ensure_soname_link <期望文件名> [实体候选 ...]
#
# 交叉编译到 Android 时, cmake (CMAKE_SYSTEM_NAME=Android) 与部分 configure 不生成
# libFoo.so.N 版本软链, 因为 Android 的 linker 忽略版本号。但**别人的 DT_NEEDED 里
# 写的就是带版本的文件名**, 比如 winedmo.so 要 libavutil.so.60、Turnip 要
# libzstd.so.1, 找不到该文件名就加载失败。官方 imagefs 里这些软链都在
# (libzstd.so -> libzstd.so.1 -> libzstd.so.1.5.8), 所以这里补齐。
ensure_soname_link() {
    local want="$1"
    shift
    local dst="$PREFIX/lib/$want"

    [ -e "$dst" ] && return 0

    local cand
    for cand in "$@"; do
        if [ -e "$PREFIX/lib/$cand" ]; then
            ln -sf "$cand" "$dst"
            log "  软链: $want -> $cand"
            return 0
        fi
    done

    # 没给候选或候选都不在: 退回按前缀找同名实体 (libavutil.so.60 -> libavutil.so*)
    local base="${want%%.so*}.so"
    local real
    local candidate
    for candidate in "$PREFIX/lib/$base"*; do
        [ -e "$candidate" ] || continue
        [ "$(basename "$candidate")" = "$want" ] && continue
        real="$candidate"
        break
    done
    if [ -n "$real" ]; then
        ln -sf "$(basename "$real")" "$dst"
        log "  软链: $want -> $(basename "$real")"
        return 0
    fi

    error "  无法为 '$want' 建软链: 找不到实体 (候选: $* ; 前缀: $base*)"
    return 1
}

# ---- 源码获取 ----
# fetch_source <解压后应得到的目录> <本地 tarball 名> <url> [备用 url ...]
#
# 取代原来的 `[ -d "$DIR" ] || { curl -sL "$URL" -o T && tar xf T; }`。那个写法有
# 两个坑, 都真实咬过:
#   1. curl 没有 --fail, HTTP 404/5xx 时 curl 仍返回 0, 把错误页写进 tarball,
#      于是失败点被推迟到后面的 `cd "$PKG_NAME"`, 报成
#      "cd: xxx: No such file or directory" —— 完全看不出是下载问题。
#   2. 只有单一源。部分 CI 出口对 xorg.freedesktop.org / gmplib.org / ffmpeg.org
#      不通 (本地全部 200), 一旦源码缓存未命中就整批失败, 且 xorgproto 一挂会
#      连锁带倒 14 个 X 包 + vulkan-loader + libglvnd。
#
# 因此: --fail 让 HTTP 错误立刻可见, 多候选逐个尝试, 并校验解压后的目录名。
fetch_source() {
    local expect_dir="$1" tarball="$2"
    shift 2

    if [ -d "$expect_dir" ]; then
        log "  源码已缓存: $expect_dir"
        return 0
    fi

    # 解压前的顶层目录快照, 用于识别本次新增的目录。
    local before
    before=$(ls -d -- */ 2>/dev/null | sort || true)

    local url
    for url in "$@"; do
        log "  下载: $url"
        if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$tarball" "$url"; then
            warn "  下载失败, 尝试下一个源"
            rm -f "$tarball"
            continue
        fi
        if ! tar --no-same-owner -xf "$tarball"; then
            warn "  解压失败 (下载内容可能不是归档), 尝试下一个源"
            rm -f "$tarball"
            continue
        fi
        rm -f "$tarball"

        if [ -d "$expect_dir" ]; then
            return 0
        fi

        # 顶层目录名与预期不符。GitHub 的 archive/refs/tags 包普遍如此
        # (例: FFmpeg 的 n8.0 标签解出 FFmpeg-n8.0/ 而非 ffmpeg-8.0/)。
        # 只在「恰好新增一个顶层目录」时纠正, 避免掩盖真正的解压异常。
        local after new
        after=$(ls -d -- */ 2>/dev/null | sort || true)
        new=$(comm -13 <(echo "$before") <(echo "$after"))
        if [ "$(echo "$new" | grep -c .)" = "1" ]; then
            new="${new%/}"
            log "  顶层目录为 '$new', 重命名为 '$expect_dir'"
            mv -- "$new" "$expect_dir"
            return 0
        fi

        error "  解压后未得到 '$expect_dir'; 新增顶层: $(echo "$new" | tr '\n' ' ')"
        return 1
    done

    error "  全部下载源均失败, 无法获取 '$expect_dir'"
    return 1
}
