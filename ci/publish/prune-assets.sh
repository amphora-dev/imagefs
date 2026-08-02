#!/usr/bin/env bash
# On a fixed-tag Release, delete assets that are not in the keep list.
#
# Usage:
#   ci/publish/prune-assets.sh --tag TAG --keep NAME [--keep NAME ...]
#   ci/publish/prune-assets.sh --tag TAG --keep NAME1 NAME2 ...
#   Optional: --match GLOB   only consider assets matching GLOB (default: *)
#
# Env: GH_TOKEN, REPO
set -euo pipefail

TAG=""
KEEP=()
MATCH="*"
REPO="${REPO:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:?}"; shift 2 ;;
    --match) MATCH="${2:?}"; shift 2 ;;
    --keep)
      shift
      while [ $# -gt 0 ] && [[ "$1" != -* ]]; do
        KEEP+=("$1")
        shift
      done
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

: "${TAG:?--tag required}"
: "${GH_TOKEN:?GH_TOKEN required}"
[ "${#KEEP[@]}" -gt 0 ] || { echo "need at least one --keep" >&2; exit 2; }

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

is_kept() {
  local n="$1" k
  for k in "${KEEP[@]}"; do
    [ "$n" = "$k" ] && return 0
  done
  return 1
}

mapfile -t ASSETS < <(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')
for name in "${ASSETS[@]}"; do
  # $MATCH is unquoted on purpose: --match is a glob (e.g. 'wrapper-*').
  # shellcheck disable=SC2254
  case "$name" in
    $MATCH) ;;
    *) continue ;;
  esac
  if is_kept "$name"; then
    continue
  fi
  echo "Deleting old asset: $name"
  gh release delete-asset "$TAG" "$name" --repo "$REPO" --yes || true
done
