#!/usr/bin/env bash
# Validate VKD3D WCP structure and PE architectures.
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
ENV_FILE="${ENV_FILE:-$ARTIFACT_DIR/vkd3d-wcp.env}"
test -f "$ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

wcp="$ARTIFACT_DIR/$WCP_NAME"
test -f "$wcp"
test -f "$wcp.sha256sum"
(
  cd "$ARTIFACT_DIR"
  sha256sum -c "$WCP_NAME.sha256sum"
)
test "$(sha256sum "$wcp" | awk '{print $1}')" = "$SHA256"
test "$(stat -c%s "$wcp")" = "$SIZE"
test "$SIZE" -gt 500000

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xJf "$wcp" -C "$work"

for dll in d3d12 d3d12core; do
  test -f "$work/system32/${dll}.dll"
  test -f "$work/syswow64/${dll}.dll"
done

python3 - "$work/profile.json" "$FULL_VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    profile = json.load(stream)
assert profile["type"] == "VKD3D"
assert profile["versionName"] == sys.argv[2]
assert profile["versionCode"] == 0
assert len(profile["files"]) == 4
PY

file "$work/system32/d3d12.dll" | grep -q 'PE32+.*x86-64'
file "$work/syswow64/d3d12.dll" | grep -q 'PE32.*Intel 80386'
echo "vkd3d-wcp OK: $WCP_NAME ($SIZE bytes)"
