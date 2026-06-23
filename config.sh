# =============================================================================
# config.sh — winlator bionic imagefs 构建系统全局配置
# =============================================================================
# 参考: MiceWine-Packages build-all.sh + 官方 imagefs ELF 取证
# 目标: aarch64-linux-android (Bionic libc), merged-usr 布局
# =============================================================================

# ---- Android NDK ----
NDK_VERSION="r29"
NDK_URL="https://dl.google.com/android/repository/android-ndk-r29-linux.zip"
NDK_FILENAME="android-ndk-r29-linux.zip"

# ---- 目标架构 ----
ARCH="${ARCH:-aarch64}"
ANDROID_API="${ANDROID_API:-26}"

# ---- 路径 ----
BUILD_DIR="${BUILD_DIR:-/tmp/imagefs-build}"
CACHE_DIR="$BUILD_DIR/cache"
SRC_DIR="$BUILD_DIR/src"
WORK_DIR="$BUILD_DIR/workdir"
LOGS_DIR="$BUILD_DIR/logs"
ROOTFS="$BUILD_DIR/imagefs"
PREFIX="$ROOTFS/usr"
BUILT_DIR="$BUILD_DIR/built-pkgs"

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
