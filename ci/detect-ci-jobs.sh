#!/usr/bin/env bash
# Decide which CI jobs to run. Writes imagefs=true|false and box64=true|false
# to $GITHUB_OUTPUT.
#
# Env:
#   EVENT_NAME, EVENT_BEFORE, SHA
#   TARGET — workflow_dispatch: auto|imagefs|box64|both
#   GITHUB_BASE_REF — for pull_request diffs
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

TARGET="${TARGET:-auto}"
EVENT_NAME="${EVENT_NAME:?}"

imagefs=false
box64=false

box64_sources_changed() {
  local range=""
  if [ "$EVENT_NAME" = "pull_request" ] && [ -n "${GITHUB_BASE_REF:-}" ]; then
    git fetch --depth=1 origin "$GITHUB_BASE_REF" 2>/dev/null || true
    range="origin/${GITHUB_BASE_REF}...HEAD"
  elif [ -n "${EVENT_BEFORE:-}" ] && [ "${EVENT_BEFORE}" != "0000000000000000000000000000000000000000" ]; then
    range="${EVENT_BEFORE}...${SHA:-HEAD}"
  else
    return 1
  fi
  git diff --name-only "$range" \
    | grep -E '^(ci/build-box64-wcp\.sh|vendor/box64-patches/)' >/dev/null
}

case "$EVENT_NAME" in
  schedule)
    box64=true
    ;;
  workflow_dispatch)
    case "$TARGET" in
      imagefs) imagefs=true ;;
      box64) box64=true ;;
      both) imagefs=true; box64=true ;;
      *) imagefs=true; box64=true ;;
    esac
    ;;
  pull_request|push)
    imagefs=true
    if box64_sources_changed; then
      box64=true
    fi
    ;;
  *)
    imagefs=true
    ;;
esac

{
  echo "imagefs=$imagefs"
  echo "box64=$box64"
} >> "$GITHUB_OUTPUT"
echo "jobs: imagefs=$imagefs box64=$box64 (event=$EVENT_NAME target=$TARGET)"
