#!/usr/bin/env bash
# Pack ~/.cache/buildstream into zstd parts small enough for GitHub Releases (<2GiB).
#
# Env:
#   CAS_ROOT     default: $HOME/.cache/buildstream
#   OUT_DIR      default: artifacts/bst-cache
#   NAME         default: buildstream-cas-proton-wine
#   PART_BYTES   default: 1900M (split size; must stay under 2147483648)
#   ZSTD_LEVEL   default: 10
set -euo pipefail

OUT_DIR="${OUT_DIR:-artifacts/bst-cache}"
CAS_ROOT="${CAS_ROOT:-$HOME/.cache/buildstream}"
NAME="${NAME:-buildstream-cas-proton-wine}"
PART_BYTES="${PART_BYTES:-1900M}"
ZSTD_LEVEL="${ZSTD_LEVEL:-10}"

mkdir -p "$OUT_DIR"
test -d "$CAS_ROOT"
cas_bytes="$(du -sb "$CAS_ROOT" | awk '{print $1}')"
if [ "$cas_bytes" -lt 100000000 ]; then
  echo "CAS at $CAS_ROOT is too small (${cas_bytes} bytes); need a warm Actions cache" >&2
  exit 1
fi
du -sh "$CAS_ROOT"

# Drop prior outputs for this NAME so re-runs do not mix part sets.
rm -f \
  "$OUT_DIR/${NAME}.tar.zst" \
  "$OUT_DIR/${NAME}.tar.zst.sha256sum" \
  "$OUT_DIR/${NAME}.parts" \
  "$OUT_DIR/${NAME}.tar.zst.part"*

# Stream tar|zstd into split parts; sha256 covers the reassembled .tar.zst stream.
tar --sort=name --mtime='@0' --clamp-mtime --owner=0 --group=0 --numeric-owner \
  -C "$CAS_ROOT" -cf - . \
  | zstd -T0 -"${ZSTD_LEVEL}" -c \
  | tee >(sha256sum | awk -v n="${NAME}.tar.zst" '{print $1"  "n}' >"$OUT_DIR/${NAME}.tar.zst.sha256sum") \
  | split -b "$PART_BYTES" -d -a 2 - "$OUT_DIR/${NAME}.tar.zst.part"

shopt -s nullglob
parts=( "$OUT_DIR/${NAME}.tar.zst.part"* )
shopt -u nullglob
if [ "${#parts[@]}" -eq 0 ]; then
  echo "split produced no parts" >&2
  exit 1
fi

: >"$OUT_DIR/${NAME}.parts"
for p in "${parts[@]}"; do
  basename "$p" >>"$OUT_DIR/${NAME}.parts"
done

echo "parts:"
cat "$OUT_DIR/${NAME}.parts"
echo "sha256sum:"
cat "$OUT_DIR/${NAME}.tar.zst.sha256sum"
ls -lh "$OUT_DIR/${NAME}".*
