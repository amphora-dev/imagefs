#!/usr/bin/env bash
# Verify imagefs.txz before publish: exists, no box64, no headers, wine sonames.
#
# Env:
#   OUTPUT_DIR   default /tmp/imagefs-output
#   BUILD_DIR    default /tmp/imagefs-build (for target/ soname check)
#   ARTIFACTS    default ./artifacts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/imagefs-output}"
BUILD_DIR="${BUILD_DIR:-/tmp/imagefs-build}"
ARTIFACTS="${ARTIFACTS:-$PWD/artifacts}"

mkdir -p "$ARTIFACTS"
test -f "$OUTPUT_DIR/imagefs.txz"
test -f "$OUTPUT_DIR/imagefs.txz.sha256sum"

if tar -tJf "$OUTPUT_DIR/imagefs.txz" | grep -Eq '^(\./)?usr/bin/box64$'; then
  echo "FAIL: box64 in imagefs.txz" >&2
  exit 1
fi
if tar -tJf "$OUTPUT_DIR/imagefs.txz" | grep -Eq '^(\./)?usr/include/'; then
  echo "FAIL: usr/include in imagefs.txz" >&2
  exit 1
fi

export IMAGEFS_RUNTIME_STAGE="${IMAGEFS_RUNTIME_STAGE:-$BUILD_DIR/target}"
bash "$SCRIPT_DIR/verify-wine-deps.sh"

cp "$OUTPUT_DIR/imagefs.txz" "$OUTPUT_DIR/imagefs.txz.sha256sum" "$ARTIFACTS/"
ls -lh "$ARTIFACTS"
