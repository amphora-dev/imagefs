#!/usr/bin/env bash
# Pack ~/.cache/buildstream for download outside Actions (cache API is runner-only).
# Used by export-buildstream-cache.yml — does not build or publish Proton WCP.
set -euo pipefail
OUT_DIR="${OUT_DIR:-artifacts/bst-cache}"
CAS_ROOT="${CAS_ROOT:-$HOME/.cache/buildstream}"
NAME="${NAME:-buildstream-cas-proton-wine}"

mkdir -p "$OUT_DIR"
if [ ! -d "$CAS_ROOT" ]; then
  echo "missing CAS at $CAS_ROOT" >&2
  exit 1
fi
du -sh "$CAS_ROOT"
# Fast-ish zstd: remote cache seed, not archival -19
tar \
  --sort=name \
  --mtime='@0' \
  --clamp-mtime \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$CAS_ROOT" \
  -cf - . |
  zstd -T0 -10 -o "$OUT_DIR/${NAME}.tar.zst"
(
  cd "$OUT_DIR" || exit 1
  sha256sum "${NAME}.tar.zst" > "${NAME}.tar.zst.sha256sum"
  ls -lh
)
echo "Packed $OUT_DIR/${NAME}.tar.zst"
