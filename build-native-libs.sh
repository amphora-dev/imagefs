#!/usr/bin/env bash
# =============================================================================
# build-native-libs.sh — 编译 Winlator Android 原生库 (jniLibs)
#
# 从 Pipetto-crypto/winlator (winlator_bionic 分支) 源码编译所有原生库:
#   - libadrenotools.so + 4 个 hook 库 (libhook_impl, libmain_hook, libfile_redirect_hook, libgsl_alloc_hook)
#   - libwinlator.so (含 OpenXR、ALSA、Vulkan、EGL 渲染器)
#   - libopenxr_loader.so (OpenXR Loader)
#   - libpatchelf.so
#   - adrenoutils_extra.so (从 adrenotools-v819.tzst 提取的源码编译)
#
# 构建配置匹配 wrapper.tzst 预编译版本:
#   - ANDROID_STL=c++_shared (链接 libc++_shared.so)
#   - --as-needed (避免不必要的 NEEDED 条目)
#   - -Wl,-s (链接时 strip 符号)
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
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "ERROR: NDK toolchain not found at $TOOLCHAIN"
    echo "Set NDK env var to your NDK path"
    exit 1
fi

# ---- winlator-bionic 源码 ----
WINLATOR_SRC="${WINLATOR_SRC:-/workspace/winlator-bionic/app/src/main/cpp}"

if [ ! -d "$WINLATOR_SRC" ]; then
    echo "ERROR: winlator-bionic source not found at $WINLATOR_SRC"
    echo "Clone: git clone --recursive -b winlator_bionic https://github.com/Pipetto-crypto/winlator.git"
    exit 1
fi

# ---- 输出目录 ----
OUTPUT_DIR="$SCRIPT_DIR/output/native-libs"
BUILD_DIR="/tmp/build-bionic-native"

mkdir -p "$OUTPUT_DIR"

# ---- 构建配置 (匹配 wrapper.tzst) ----
ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-26"
ANDROID_STL="c++_shared"
BUILD_TYPE="Release"

# ---- 包列表 ----
ALL_TARGETS=(
    adrenotools
    winlator-native
    adrenoutils-extra
)

if [ $# -gt 0 ]; then
    SELECTED=("$@")
else
    SELECTED=("${ALL_TARGETS[@]}")
fi

# ---- helper ----
log() { echo -e "\033[32m[build-native]\033[0m $*"; }
err() { echo -e "\033[31m[ERROR]\033[0m $*"; }

# ---- 构建 adrenotools + hook 库 ----
build_adrenotools() {
    log "Building adrenotools + hook libraries (c++_shared, --as-needed)..."
    local BUILD="$BUILD_DIR"

    # 修补 CMakeLists.txt: 添加 log 链接库
    local CMAKE_FILE="$WINLATOR_SRC/adrenotools/CMakeLists.txt"
    if ! grep -q 'target_link_libraries(adrenotools android log linkernsbypass)' "$CMAKE_FILE"; then
        sed -i 's/target_link_libraries(adrenotools android linkernsbypass)/target_link_libraries(adrenotools android log linkernsbypass)/' "$CMAKE_FILE"
    fi

    cmake -B "$BUILD" -S "$WINLATOR_SRC" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI="$ANDROID_ABI" \
        -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
        -DANDROID_STL="$ANDROID_STL" \
        -DBUILD_SHARED_LIBS=ON \
        -DGEN_INSTALL_TARGET=ON \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_C_FLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types" \
        -DCMAKE_CXX_FLAGS="-Wno-error=implicit-function-declaration" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--as-needed" 2>&1

    cmake --build "$BUILD" -j"$JOBS" --target adrenotools hook_impl main_hook file_redirect_hook gsl_alloc_hook 2>&1

    # Strip and collect
    local libs=(
        "$BUILD/adrenotools/libadrenotools.so"
        "$BUILD/adrenotools/src/hook/libhook_impl.so"
        "$BUILD/adrenotools/src/hook/libmain_hook.so"
        "$BUILD/adrenotools/src/hook/libfile_redirect_hook.so"
        "$BUILD/adrenotools/src/hook/libgsl_alloc_hook.so"
    )

    for lib in "${libs[@]}"; do
        if [ -f "$lib" ]; then
            "$STRIP" --strip-all "$lib" 2>/dev/null
            cp "$lib" "$OUTPUT_DIR/"
            log "  ✅ $(basename $lib) ($(ls -lh "$lib" | awk '{print $5}'))"
        fi
    done
}

# ---- 构建 winlator 原生库 (winlator + OpenXR + patchelf) ----
build_winlator_native() {
    log "Building winlator native libraries (OpenXR + patchelf)..."
    local BUILD="$BUILD_DIR"

    cmake --build "$BUILD" -j"$JOBS" --target winlator openxr_loader patchelf 2>&1

    # Strip and collect
    local libs=(
        "$BUILD/libwinlator.so"
        "$BUILD/libopenxr_loader.so"
        "$BUILD/libpatchelf.so"
    )

    for lib in "${libs[@]}"; do
        if [ -f "$lib" ]; then
            "$STRIP" --strip-all "$lib" 2>/dev/null
            cp "$lib" "$OUTPUT_DIR/"
            log "  ✅ $(basename $lib) ($(ls -lh "$lib" | awk '{print $5}'))"
        fi
    done
}

# ---- 编译 adrenoutils_extra.so ----
build_adrenoutils_extra() {
    log "Building adrenoutils_extra.so..."
    local SRC="${ADRENOUTILS_EXTRA_SRC:-/tmp/adrenotools-v819/adrenoutils_extra.c}"

    if [ ! -f "$SRC" ]; then
        warn "adrenoutils_extra.c not found at $SRC"
        warn "Extract from adrenotools-v819.tzst or set ADRENOUTILS_EXTRA_SRC"
        return 1
    fi

    $CC -shared -fPIC -O2 -Wl,-s,--as-needed -o "$OUTPUT_DIR/adrenoutils_extra.so" "$SRC" -llog -ldl 2>&1
    "$STRIP" --strip-all "$OUTPUT_DIR/adrenoutils_extra.so" 2>/dev/null
    log "  ✅ adrenoutils_extra.so ($(ls -lh "$OUTPUT_DIR/adrenoutils_extra.so" | awk '{print $5}'))"
}

# ---- 主流程 ----
log "Winlator Android Native Libraries Build (Pipetto-crypto/winlator_bionic)"
log "NDK: $NDK"
log "ABI: $ANDROID_ABI"
log "Platform: android-$ANDROID_PLATFORM"
log "STL: $ANDROID_STL"
log "Source: $WINLATOR_SRC"
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
        adrenoutils-extra)
            if build_adrenoutils_extra; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILED=$((FAILED + 1))
                err "Failed to build adrenoutils-extra"
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
