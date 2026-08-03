#!/usr/bin/env bash
# =============================================================================
# lib/util.sh — 构建脚本共用的小工具
# =============================================================================
# 不依赖 config.sh（不用 log/error），因为 ci/ 下的 leaf 脚本不 source 它。
# =============================================================================

# need <命令> — 缺少就直接失败，把缺什么说清楚。
need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "FAIL: missing $1" >&2
        exit 1
    }
}

# apply_patch <patch 文件> [strip 层数]
#
# 返回码而不是自己决定生死，因为三个调用方的策略本来就不同:
#   0  已应用
#   1  补丁内容已经在源码里（幂等重跑）
#   2  应用不上
#
# mesa-gl 的源码目录被 fetch_source 缓存复用, 所以必须能识别"已应用";
# ci/wrapper 与 ci/box64 每次 git reset --hard + clean, 走不到那条分支,
# 但共用同一套判定总比各写一份好。
apply_patch() {
    local patch_file="$1" strip="${2:-1}"
    [ -f "$patch_file" ] || return 2

    # git apply 先来: 它认识 rename/mode 这些 patch(1) 处理不好的东西。
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        git apply --check "-p$strip" "$patch_file" 2>/dev/null; then
        git apply "-p$strip" "$patch_file" && return 0
    fi

    if patch "-p$strip" --forward --batch --dry-run <"$patch_file" >/dev/null 2>&1; then
        patch "-p$strip" --forward --batch <"$patch_file" >/dev/null && return 0
    fi

    # 反向能干净应用 == 内容已经在源码里了。优先用 git apply：mailbox
    # series 的后续 patch 会依赖前一段新增的上下文，patch(1) 按正序反向试跑
    # 会误判这种“已完整应用”的 series。
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        git apply --reverse --check "-p$strip" "$patch_file" 2>/dev/null; then
        return 1
    fi
    if patch "-p$strip" --reverse --batch --dry-run <"$patch_file" >/dev/null 2>&1; then
        return 1
    fi

    return 2
}
