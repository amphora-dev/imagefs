#!/usr/bin/env bash
# Decide whether to build/publish the pinned Proton Wine WCP.
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

ELEMENT="buildstream/elements/l1/proton-wine-wcp.bst"
FULL="$(awk '
  /url: amphora:proton-wine.git/ { proton=1; next }
  proton && $1 == "ref:" { print $2; exit }
' "$ELEMENT")"
[[ "$FULL" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned Proton Wine commit in $ELEMENT: $FULL" >&2
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

if gh release view wine --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view wine --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -Eq -- "-${SHORT}-x86_64-[0-9]+\\.wcp\$"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published for $SHORT"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
