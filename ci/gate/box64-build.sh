#!/usr/bin/env bash
# Decide whether to build/publish Box64 WCP.
# Writes should_build, upstream_short and upstream_full to $GITHUB_OUTPUT.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

ELEMENT="buildstream/elements/l1/box64-wcp.bst"
FULL="$(awk '
  /url: box64:box64.git/ { box64=1; next }
  box64 && $1 == "ref:" { print $2; exit }
' "$ELEMENT")"
[[ "$FULL" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned Box64 commit in $ELEMENT: $FULL" >&2
  exit 1
}
SHORT="${FULL:0:9}"

# WCP identity includes the patch fingerprint (see box64-wcp.bst
# install-commands): `<maj>.<min>.<rev>-<commit9>-p<p8>`.
PATCH_FILE="vendor/box64-patches/pipetto-controller-fix.patch"
PATCH_SHORT="$(sha256sum "$PATCH_FILE" | awk '{print $1}')"
PATCH_SHORT="${PATCH_SHORT:0:8}"
{
  echo "upstream_short=$SHORT"
  echo "upstream_full=$FULL"
} >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view box64 --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view box64 --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -q -- "^Box64-.*-${SHORT}-p${PATCH_SHORT}\\.wcp\$"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published for $SHORT"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
