#!/usr/bin/env bash
# =============================================================================
# lib/ndk.sh — Android NDK 发现逻辑（唯一实现）
# =============================================================================
# 图构建 (setup-env.sh) 与 L1 leaf 构建 (ci/box64, ci/wrapper) 都要找 NDK。
# 三份各自拷贝过一遍, 结果彼此漂移: 只有 box64 那份会扫 /opt/android-sdk/ndk，
# 于是同一台机器上 box64 能构建、wrapper 报找不到 NDK。这里收敛成一份。
#
# 查找顺序: 显式环境变量 -> 调用方补充的候选 -> SDK 风格的 <sdk>/ndk/<version>。
# 判定标准统一为 toolchains/llvm/prebuilt/linux-x86_64/bin/clang 可执行。
# =============================================================================

_ndk_has_clang() {
    [ -n "$1" ] && [ -x "$1/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]
}

# ndk_resolve_dir [额外候选目录 ...] -> stdout 打印 NDK 根目录, 找不到返回 1
ndk_resolve_dir() {
    local cand sdk pick

    for cand in \
        "${ANDROID_NDK_HOME:-}" \
        "${ANDROID_NDK_ROOT:-}" \
        "${ANDROID_NDK_LATEST_HOME:-}" \
        "${ANDROID_NDK:-}" \
        "$@"; do
        if _ndk_has_clang "$cand"; then
            printf '%s\n' "$cand"
            return 0
        fi
    done

    # SDK 风格布局 (GitHub runner / 本机 sdkmanager): 取版本号最大的那个。
    for sdk in "${ANDROID_SDK_ROOT:-}" /usr/local/lib/android/sdk /opt/android-sdk; do
        [ -n "$sdk" ] && [ -d "$sdk/ndk" ] || continue
        pick="$(find "$sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
        if _ndk_has_clang "$pick"; then
            printf '%s\n' "$pick"
            return 0
        fi
    done

    return 1
}

# ndk_require [额外候选目录 ...] — 解析并 export ANDROID_NDK_HOME / ANDROID_NDK_ROOT
ndk_require() {
    local dir
    if ! dir="$(ndk_resolve_dir "$@")"; then
        echo "FAIL: no usable Android NDK (set ANDROID_NDK_HOME)" >&2
        return 1
    fi
    export ANDROID_NDK_HOME="$dir"
    export ANDROID_NDK_ROOT="$dir"
    echo "Using NDK: $ANDROID_NDK_HOME"
}
