#!/usr/bin/env bash
# Restore remote BuildStream CAS published by export-buildstream-cache.yml
# into ~/.cache/buildstream for local bst / CI-aligned builds.
set -euo pipefail
URL="${CI_BST_CACHE_URL:-https://github.com/amphora-dev/imagefs/releases/download/wine-dev-bst-cache/buildstream-cas-proton-wine.tar.zst}"
SHA_URL="${CI_BST_CACHE_SHA_URL:-${URL}.sha256sum}"
DEST="${CAS_ROOT:-$HOME/.cache/buildstream}"
FORCE="${FORCE:-0}"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ] && [ "$FORCE" != 1 ]; then
  echo "CAS already present at $DEST (FORCE=1 to replace)"
  du -sh "$DEST"
  exit 0
fi

tmp="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$tmp"' EXIT
echo "==> download $URL"
curl -fL --retry 5 --retry-delay 2 -o "$tmp/cas.tar.zst" "$URL"
if curl -fL --retry 3 -o "$tmp/cas.sha256sum" "$SHA_URL"; then
  awk -v f="$tmp/cas.tar.zst" '{print $1"  "f}' "$tmp/cas.sha256sum" | sha256sum -c -
fi
rm -rf "$DEST"
mkdir -p "$DEST"
zstd -d -c "$tmp/cas.tar.zst" | tar -x -C "$DEST"
du -sh "$DEST"
echo "Restored BuildStream CAS → $DEST"
