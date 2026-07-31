#!/usr/bin/env bash
# Decide whether to build/publish Box64 WCP.
# Writes should_build, box64_ref, upstream_short, upstream_full to $GITHUB_OUTPUT.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
#   BOX64_REF_INPUT — optional git ref from workflow_dispatch
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

REF="${BOX64_REF_INPUT:-}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone --filter=blob:none https://github.com/ptitSeb/box64.git "$TMP/box64"
cd "$TMP/box64"
if [ -n "$REF" ]; then
  git fetch --depth 1 origin "$REF"
  git checkout --force FETCH_HEAD
else
  git checkout --force main
  git pull --ff-only origin main
fi

SHORT="$(git rev-parse --short=9 HEAD)"
FULL="$(git rev-parse HEAD)"
{
  echo "upstream_short=$SHORT"
  echo "upstream_full=$FULL"
  echo "box64_ref=$REF"
} >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view box64 --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view box64 --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -q -- "-${SHORT}\\.wcp\$"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published for $SHORT"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
