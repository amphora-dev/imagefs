#!/usr/bin/env bash
# =============================================================================
# ci/upstream.sh — L1 leaf 的上游来源（唯一真源）
# =============================================================================
# gate 脚本负责算出上游 commit 并判断"这个 sha 是不是已经发布过", 构建脚本负责
# 真去 clone 并编译。两边必须看同一个仓库和同一个默认 ref —— 各写一份 URL 的话,
# 换仓库时 gate 会拿旧仓的 sha 去比对新仓的产物, 得出的 should_build 是错的。
#
# 每一项都可以被环境变量覆盖 (workflow_dispatch 输入走这条路)。
# =============================================================================

MESA_REPO="${MESA_REPO:-https://github.com/Pipetto-crypto/mesa.git}"
MESA_DEFAULT_REF="${MESA_DEFAULT_REF:-wrapper-25}"

BOX64_REPO="${BOX64_REPO:-https://github.com/ptitSeb/box64.git}"
