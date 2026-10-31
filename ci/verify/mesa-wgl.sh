#!/usr/bin/env bash
# Validate the Mesa WGL runtime asset layout and PE architectures.
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
ENV_FILE="${ENV_FILE:-$ARTIFACT_DIR/mesa-wgl.env}"
test -f "$ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

tzst="$ARTIFACT_DIR/$TZST_NAME"
test -f "$tzst"
test -f "$tzst.sha256sum"
(
  cd "$ARTIFACT_DIR"
  sha256sum -c "$TZST_NAME.sha256sum"
)
test "$(sha256sum "$tzst" | awk '{print $1}')" = "$SHA256"
test "$(stat -c%s "$tzst")" = "$SIZE"
test "$SIZE" -gt 2000000

listing="$(tar -I zstd -tvf "$tzst")"
if printf '%s\n' "$listing" | grep -q '^[^-d]'; then
  echo "$TZST_NAME holds entries that are neither files nor directories:" >&2
  printf '%s\n' "$listing" | grep '^[^-d]' >&2
  exit 1
fi
if tar -I zstd -tf "$tzst" | grep -Ev '^(licenses|system32|syswow64)(/|$)'; then
  echo "$TZST_NAME holds entries outside licenses/ system32/ syswow64/" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -I zstd -xf "$tzst" -C "$work"

for dll in opengl32 libgallium_wgl; do
  file "$work/system32/${dll}.dll" | grep -q 'PE32+ executable.*x86-64'
  file "$work/syswow64/${dll}.dll" | grep -q 'PE32 executable.*Intel 80386'
done
test -n "$(ls -A "$work/licenses")"
echo "mesa-wgl OK: $TZST_NAME ($SIZE bytes)"
