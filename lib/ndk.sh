#!/usr/bin/env bash
# =============================================================================
# lib/ndk.sh — Android NDK 发现逻辑（唯一实现）
# =============================================================================
# 图构建 (setup-env.sh)、L1 leaf 构建 (ci/box64, ci/wrapper) 和 CI 的 runner 探测
# (ci/setup/resolve-runner-ndk.sh) 都要找 NDK。四份各自拷贝过一遍, 结果彼此漂移:
#   - 只有 box64 那份会扫 /opt/android-sdk/ndk，于是同一台机器上 box64 能构建、
#     wrapper 报找不到 NDK；
#   - 只有 runner 那份会优先挑 config.sh 钉住的 r29，其余三份挑版本号最大的。
# 这里收敛成一份。
#
# 查找顺序: 显式环境变量 -> 调用方补充的候选 -> SDK 风格的 <sdk>/ndk/<version>。
# SDK 目录里优先取 $NDK_PREFER_MAJOR (默认从 config.sh 的 NDK_VERSION="r29" 推出),
# 没有匹配的再退回版本号最大的那个。
# 判定标准统一为 toolchains/llvm/prebuilt/linux-x86_64/bin/clang 可执行。
# =============================================================================

_ndk_has_clang() {
    [ -n "$1" ] && [ -x "$1/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]
}

# 在一个 SDK 的 ndk/ 目录里挑一个版本: 先按偏好的大版本, 再按版本号最大。
_ndk_pick_from_sdk() {
    local ndk_root="$1" major="$2" pick=""
    if [ -n "$major" ]; then
        pick="$(find "$ndk_root" -mindepth 1 -maxdepth 1 -type d -name "$major.*" | sort -V | tail -1)"
        _ndk_has_clang "$pick" && { printf '%s\n' "$pick"; return 0; }
    fi
    pick="$(find "$ndk_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
    _ndk_has_clang "$pick" && { printf '%s\n' "$pick"; return 0; }
    return 1
}

# ndk_resolve_dir [额外候选目录 ...] -> stdout 打印 NDK 根目录, 找不到返回 1
ndk_resolve_dir() {
    local cand sdk pick major
    # NDK_VERSION 形如 r29 -> 偏好 29.*; 其他写法（含未设置）就不作偏好。
    major="${NDK_PREFER_MAJOR:-}"
    if [ -z "$major" ] && [[ "${NDK_VERSION:-}" =~ ^r([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
    fi

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

    # SDK 风格布局 (GitHub runner / 本机 sdkmanager)。
    for sdk in "${ANDROID_SDK_ROOT:-}" /usr/local/lib/android/sdk /opt/android-sdk; do
        [ -n "$sdk" ] && [ -d "$sdk/ndk" ] || continue
        if pick="$(_ndk_pick_from_sdk "$sdk/ndk" "$major")"; then
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
        ls -la "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}/ndk" 2>/dev/null || true
        return 1
    fi
    export ANDROID_NDK_HOME="$dir"
    export ANDROID_NDK_ROOT="$dir"
    echo "Using NDK: $ANDROID_NDK_HOME"
}
