#!/usr/bin/env bash
# Decide whether to build/publish DXVK WCP.
# Writes should_build, upstream_short and upstream_full to $GITHUB_OUTPUT.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
#   ELEMENT      (default buildstream/elements/l1/dxvk-wcp.bst)
#   RELEASE_TAG  (default dxvk)
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

ELEMENT="${ELEMENT:-buildstream/elements/l1/dxvk-wcp.bst}"
RELEASE_TAG="${RELEASE_TAG:-dxvk}"
FULL="$(awk '
  /url: dxvk:dxvk.git/ { dxvk=1; next }
  dxvk && $1 == "ref:" { print $2; exit }
' "$ELEMENT")"
[[ "$FULL" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned DXVK commit in $ELEMENT: $FULL" >&2
  exit 1
}
SHORT="${FULL:0:9}"
{
  echo "upstream_short=$SHORT"
  echo "upstream_full=$FULL"
} >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view "${RELEASE_TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view "${RELEASE_TAG}" --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -q -- "-${SHORT}\\.wcp\$"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published for $SHORT"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
