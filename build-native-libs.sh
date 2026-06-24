#!/usr/bin/env bash
# =============================================================================
# build-native-libs.sh — 编译 Winlator Android 原生库 (jniLibs)
#
# 从 winlator-app 源码编译所有 Android JNI 原生库:
#   - libadrenotools.so + 4 个 hook 库
#   - libwinlator.so
#   - libgladiorenderer.so
#   - libvortekrenderer.so
#   - libvirglrenderer.so
#   - libmidihandler.so
#
# 用法:
#   ./build-native-libs.sh                    # 编译全部
#   ./build-native-libs.sh adrenotools        # 仅编译 adrenotools
#   NDK=/path/to/ndk ./build-native-libs.sh   # 指定 NDK 路径
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ---- NDK 路径 ----
NDK="${NDK:-$CACHE_DIR/android-ndk-r29}"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
STRIP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "ERROR: NDK toolchain not found at $TOOLCHAIN"
    echo "Set NDK env var to your NDK path"
    exit 1
fi

# ---- winlator-app 源码 ----
WINLATOR_APP_SRC="${WINLATOR_APP_SRC:-/workspace/winlator-app/app/src/main/cpp}"

if [ ! -d "$WINLATOR_APP_SRC" ]; then
    echo "ERROR: winlator-app source not found at $WINLATOR_APP_SRC"
    echo "Clone: git clone --recursive https://github.com/brunodev85/winlator-app.git"
    exit 1
fi

# ---- 输出目录 ----
OUTPUT_DIR="$SCRIPT_DIR/output/native-libs"
BUILD_DIR="/tmp/build-native-libs"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

# ---- 构建配置 ----
ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-26"
BUILD_TYPE="Release"

# ---- 包列表 ----
ALL_TARGETS=(
    adrenotools
    winlator-native
)

if [ $# -gt 0 ]; then
    SELECTED=("$@")
else
    SELECTED=("${ALL_TARGETS[@]}")
fi

# ---- helper ----
log() { echo -e "\033[32m[build-native]\033[0m $*"; }
err() { echo -e "\033[31m[ERROR]\033[0m $*"; }

# ---- 构建 adrenotools ----
build_adrenotools() {
    log "Building adrenotools + hook libraries..."
    local SRC="$WINLATOR_APP_SRC/libadrenotools"
    local BUILD="$BUILD_DIR/adrenotools"

    rm -rf "$BUILD" && mkdir -p "$BUILD"
    cd "$BUILD"

    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI="$ANDROID_ABI" \
        -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
        -DBUILD_SHARED_LIBS=ON \
        -DGEN_INSTALL_TARGET=ON \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        "$SRC" 2>&1

    make -j"$JOBS" 2>&1

    # Strip and collect
    local libs=(
        "$BUILD/libadrenotools.so"
        "$BUILD/src/hook/libhook_impl.so"
        "$BUILD/src/hook/libmain_hook.so"
        "$BUILD/src/hook/libfile_redirect_hook.so"
        "$BUILD/src/hook/libgsl_alloc_hook.so"
    )

    for lib in "${libs[@]}"; do
        if [ -f "$lib" ]; then
            "$STRIP" --strip-all "$lib"
            cp "$lib" "$OUTPUT_DIR/"
            log "  ✅ $(basename $lib) ($(ls -lh "$lib" | awk '{print $5}'))"
        fi
    done
}

# ---- 构建 winlator-native (全部渲染器) ----
build_winlator_native() {
    log "Building winlator native libraries (all renderers + midihandler)..."
    local BUILD="$BUILD_DIR/winlator-native"

    rm -rf "$BUILD" && mkdir -p "$BUILD"
    cd "$BUILD"

    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI="$ANDROID_ABI" \
        -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
        -DBUILD_SHARED_LIBS=ON \
        -DGEN_INSTALL_TARGET=ON \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_C_FLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types" \
        -DCMAKE_CXX_FLAGS="-Wno-error=implicit-function-declaration" \
        "$WINLATOR_APP_SRC" 2>&1

    make -j"$JOBS" 2>&1

    # Strip and collect
    local libs=(
        "$BUILD/winlator/libwinlator.so"
        "$BUILD/gladiorenderer/libgladiorenderer.so"
        "$BUILD/vortekrenderer/libvortekrenderer.so"
        "$BUILD/virglrenderer/libvirglrenderer.so"
        "$BUILD/midihandler/libmidihandler.so"
    )

    for lib in "${libs[@]}"; do
        if [ -f "$lib" ]; then
            "$STRIP" --strip-all "$lib"
            cp "$lib" "$OUTPUT_DIR/"
            log "  ✅ $(basename $lib) ($(ls -lh "$lib" | awk '{print $5}'))"
        fi
    done
}

# ---- 主流程 ----
log "Winlator Android Native Libraries Build"
log "NDK: $NDK"
log "ABI: $ANDROID_ABI"
log "Platform: android-$ANDROID_PLATFORM"
log "Source: $WINLATOR_APP_SRC"
log "Output: $OUTPUT_DIR"
echo ""

TOTAL=${#SELECTED[@]}
CURRENT=0
SUCCESS=0
FAILED=0

for target in "${SELECTED[@]}"; do
    CURRENT=$((CURRENT + 1))
    log "[$CURRENT/$TOTAL] Building $target..."

    case "$target" in
        adrenotools)
            if build_adrenotools; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILED=$((FAILED + 1))
                err "Failed to build adrenotools"
            fi
            ;;
        winlator-native)
            if build_winlator_native; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILED=$((FAILED + 1))
                err "Failed to build winlator-native"
            fi
            ;;
        *)
            err "Unknown target: $target"
            FAILED=$((FAILED + 1))
            ;;
    esac
done

echo ""
log "Build Summary: $SUCCESS success, $FAILED failed"
log "Output directory: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR/" 2>/dev/null
