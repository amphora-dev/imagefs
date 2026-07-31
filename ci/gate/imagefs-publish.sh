#!/usr/bin/env bash
# Decide whether to refresh Release amphora / bump rootfs pin.
# Writes should_publish, sha, size to $GITHUB_OUTPUT.
#
# Env:
#   FORCE=true|false
#   EVENT_NAME — github.event_name
#   GIT_REF — github.ref
#   REPO — github.repository
#   GH_TOKEN
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

SHA="$(awk '{print $1}' artifacts/imagefs.txz.sha256sum)"
SIZE="$(stat -c%s artifacts/imagefs.txz)"
{
  echo "sha=$SHA"
  echo "size=$SIZE"
} >> "$GITHUB_OUTPUT"

if [ "${EVENT_NAME}" = "pull_request" ]; then
  echo "should_publish=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
if [[ "${GIT_REF}" == refs/tags/* ]]; then
  echo "should_publish=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

PUB=""
if gh release view amphora --repo "${REPO}" >/dev/null 2>&1; then
  gh release download amphora --repo "${REPO}" \
    --pattern 'imagefs.txz.sha256sum' --dir /tmp/amphora-rel || true
  if [ -f /tmp/amphora-rel/imagefs.txz.sha256sum ]; then
    PUB="$(awk '{print $1}' /tmp/amphora-rel/imagefs.txz.sha256sum)"
  fi
fi

if [ "${FORCE}" = "true" ] || [ -z "$PUB" ] || [ "$PUB" != "$SHA" ]; then
  echo "should_publish=true" >> "$GITHUB_OUTPUT"
  echo "Will publish (was ${PUB:-none})"
else
  echo "should_publish=false" >> "$GITHUB_OUTPUT"
  echo "SHA matches published amphora ($SHA) — skip"
fi
