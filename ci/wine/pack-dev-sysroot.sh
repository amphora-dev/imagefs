#!/usr/bin/env bash
# Checkout BuildStream wine sysroot (+ host-freetype) and pack downloadable
# tarballs for local ci/wine/dev-bootstrap-sysroot.sh. Runs on Actions so the
# restored ~/.cache/buildstream CAS becomes usable outside the runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_DIR="${OUT_DIR:-artifacts/dev}"
SYSROOT_DIR="${SYSROOT_DIR:-/tmp/wine-sysroot}"
HOST_FT_DIR="${HOST_FT_DIR:-/tmp/host-freetype-bst}"
BST="${BST:-buildstream/bst}"

mkdir -p "$OUT_DIR"

echo "==> ensure wine/sysroot-x86_64.bst is built (CAS hit when cache warm)"
"$BST" build wine/sysroot-x86_64.bst

if [ ! -d "$SYSROOT_DIR/usr/lib" ]; then
  rm -rf "$SYSROOT_DIR"
  "$BST" artifact checkout wine/sysroot-x86_64.bst \
    --deps none \
    --directory "$SYSROOT_DIR"
fi
test -d "$SYSROOT_DIR/usr/lib"
test -d "$SYSROOT_DIR/usr/include"

echo "==> pack android-x86_64-sysroot.tar.zst"
tar \
  --sort=name \
  --mtime='@0' \
  --clamp-mtime \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$SYSROOT_DIR" \
  -cf - . |
  zstd -T0 -19 -o "$OUT_DIR/android-x86_64-sysroot.tar.zst"

echo "==> host-freetype (best-effort)"
if "$BST" build wine/host-freetype.bst; then
  rm -rf "$HOST_FT_DIR"
  "$BST" artifact checkout wine/host-freetype.bst \
    --deps none \
    --directory "$HOST_FT_DIR"
  # Element install-root layout may be /opt/host-freetype or usr — normalize.
  if [ -d "$HOST_FT_DIR/opt/host-freetype" ]; then
    pack_root="$HOST_FT_DIR/opt/host-freetype"
  elif [ -d "$HOST_FT_DIR/usr" ]; then
    pack_root="$HOST_FT_DIR"
  else
    pack_root="$HOST_FT_DIR"
  fi
  tar \
    --sort=name \
    --mtime='@0' \
    --clamp-mtime \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -C "$pack_root" \
    -cf - . |
    zstd -T0 -19 -o "$OUT_DIR/host-freetype.tar.zst"
else
  echo "WARN: host-freetype bst build skipped/failed" >&2
fi

(
  cd "$OUT_DIR" || exit 1
  sha256sum android-x86_64-sysroot.tar.zst > android-x86_64-sysroot.tar.zst.sha256sum
  if [ -f host-freetype.tar.zst ]; then
    sha256sum host-freetype.tar.zst > host-freetype.tar.zst.sha256sum
  fi
  ls -lh
)

echo "Packed sysroot for local fast path under $OUT_DIR"
