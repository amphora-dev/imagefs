#!/usr/bin/env bash
# Package the Box64 binary built by box64-wcp.bst into a WCP.
# Runs inside the BuildStream sandbox from the element's install-commands.
set -euo pipefail

: "${BOX64_BINARY:?BuildStream must provide BOX64_BINARY}"
: "${BOX64_COMMIT:?BuildStream must provide BOX64_COMMIT}"
: "${BOX64_PATCH:?BuildStream must provide BOX64_PATCH}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${STRIP:?NDK toolchain must provide STRIP}"

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
WORK=/tmp/box64-wcp

[[ "$BOX64_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "BOX64_COMMIT is not a full sha: $BOX64_COMMIT" >&2
  exit 1
}

"$STRIP" "$BOX64_BINARY"
interpreter="$(readelf -l "$BOX64_BINARY" |
  awk -F: '/interpreter/{gsub(/[\[\] ]/,"",$2); print $2}')"
[ "$interpreter" = /system/bin/linker64 ] || {
  echo "unexpected ELF interpreter: ${interpreter:-<none>}" >&2
  exit 1
}

version_field() {
  awk -v key="$1" '$1 == "#define" && $2 == key { print $3; exit }' src/box64version.h
}
major="$(version_field BOX64_MAJOR)"
minor="$(version_field BOX64_MINOR)"
revision="$(version_field BOX64_REVISION)"
[ -n "$major" ] && [ -n "$minor" ] && [ -n "$revision" ] || {
  echo "cannot read version from src/box64version.h" >&2
  exit 1
}

# The patch fingerprint is part of the WCP identity: amphora's
# WinlatorContentAssetInstaller.sameProfile keys on type + verName + verCode,
# so a patch-only change must yield a different versionName.
# ci/gate/box64-build.sh derives the same value for its dedupe check.
commit_short="${BOX64_COMMIT:0:9}"
patch_full="$(sha256sum "$BOX64_PATCH" | awk '{print $1}')"
patch_short="${patch_full:0:8}"
full_version="$major.$minor.$revision-$commit_short-p$patch_short"
wcp_name="Box64-$full_version.wcp"

rm -rf "$WORK"
mkdir -p "$WORK" "$OUTPUT_DIR"
install -m 0755 "$BOX64_BINARY" "$WORK/box64"

python3 - "$WORK/profile.json" "$full_version" <<'PY'
import json
import sys

path, version = sys.argv[1], sys.argv[2]
profile = {
    "type": "Box64",
    "versionName": version,
    "versionCode": 0,
    "description": f"Box64-{version}",
    "files": [{"source": "box64", "target": "${bindir}/box64"}],
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(profile, f, indent=2)
    f.write("\n")
PY

tar --owner=0 --group=0 --numeric-owner \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
  -I 'xz -T1' -cf "$OUTPUT_DIR/$wcp_name" -C "$WORK" box64 profile.json
(
  cd "$OUTPUT_DIR"
  sha256sum "$wcp_name" > "$wcp_name.sha256sum"
)
size="$(stat -c%s "$OUTPUT_DIR/$wcp_name")"
sha="$(awk '{print $1}' "$OUTPUT_DIR/$wcp_name.sha256sum")"

cat > "$OUTPUT_DIR/box64-wcp.env" <<EOF
FULL_VERSION=$full_version
COMMIT_FULL=$BOX64_COMMIT
COMMIT_SHORT=$commit_short
PATCH_FULL=$patch_full
PATCH_SHORT=$patch_short
WCP_NAME=$wcp_name
SHA256=$sha
SIZE=$size
EOF

echo "packaged $wcp_name ($size bytes, sha256 $sha)"
