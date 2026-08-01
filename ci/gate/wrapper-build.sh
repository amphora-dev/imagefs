#!/usr/bin/env bash
# Decide whether to build/publish wrapper.tzst.
# Writes should_build, mesa_ref, upstream_short, upstream_full to $GITHUB_OUTPUT.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
#   MESA_REF_INPUT — optional git ref from workflow_dispatch (empty = default)
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")/.." && pwd)/upstream.sh"

REF="${MESA_REF_INPUT:-$MESA_DEFAULT_REF}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone --filter=blob:none "$MESA_REPO" "$TMP/mesa"
cd "$TMP/mesa"
git fetch --depth 1 origin "$REF" 2>/dev/null || git fetch --depth 1 origin "+refs/heads/${REF}:refs/remotes/origin/${REF}" || true
if git rev-parse --verify "origin/$REF" >/dev/null 2>&1; then
  git checkout --force "origin/$REF"
elif git rev-parse --verify "$REF" >/dev/null 2>&1; then
  git checkout --force "$REF"
else
  git fetch --depth 1 origin "$REF"
  git checkout --force FETCH_HEAD
fi

SHORT="$(git rev-parse --short=9 HEAD)"
FULL="$(git rev-parse HEAD)"
{
  echo "upstream_short=$SHORT"
  echo "upstream_full=$FULL"
  echo "mesa_ref=$REF"
} >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view wrapper --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view wrapper --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -q -- "wrapper-${SHORT}\\.tzst\$"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published for $SHORT"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
