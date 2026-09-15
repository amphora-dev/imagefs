#!/usr/bin/env bash
set -euo pipefail
OUT_DIR="${OUT_DIR:-artifacts/bst-cache}"
CAS_ROOT="${CAS_ROOT:-$HOME/.cache/buildstream}"
NAME="${NAME:-buildstream-cas-proton-wine}"
mkdir -p "$OUT_DIR"
test -d "$CAS_ROOT"
du -sh "$CAS_ROOT"
tar --sort=name --mtime='@0' --clamp-mtime --owner=0 --group=0 --numeric-owner \
  -C "$CAS_ROOT" -cf - . | zstd -T0 -10 -o "$OUT_DIR/${NAME}.tar.zst"
( cd "$OUT_DIR" || exit 1; sha256sum "${NAME}.tar.zst" > "${NAME}.tar.zst.sha256sum"; ls -lh )
