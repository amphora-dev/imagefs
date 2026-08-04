#!/usr/bin/env bash
# Bump one pin in amphora-dev/content_manifest and push to main.
#
# A pin lives in exactly one of two places, and the caller says which:
#   COMPONENT=<name>          components.<name>   — resolved by ContentSource
#   RUNTIME_ASSET=<assetPath> runtimeAssets[]     — provisioned by
#                                                   RuntimeAssetProvisioner into
#                                                   filesDir/runtime-assets/
#
# Required env:
#   GH_TOKEN              — PAT with write access to content_manifest
#   COMPONENT | RUNTIME_ASSET  (exactly one)
#   SHA256                — artifact sha256
#   SIZE                  — artifact size in bytes
#
# Optional env:
#   ASSET_PATH            — components.<name>.assetPath (e.g. Box64-0.4.3-abc.wcp)
#   VER_NAME              — e.g. 0.4.3-abc; also used in the commit subject
#   REMOTE_URL            — full download URL
#   KIND / CONTENT_TYPE   — defaults: ROOTFS for rootfs, WCP/Box64 for box64
#   COMMIT_SUBJECT        — override commit title body first line
#   BOT_NAME / BOT_EMAIL
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
  echo "FAIL: GH_TOKEN not set; refusing to publish without updating content_manifest" >&2
  exit 1
fi

: "${SHA256:?SHA256 required}"
: "${SIZE:?SIZE required}"

if [ -n "${COMPONENT:-}" ] && [ -n "${RUNTIME_ASSET:-}" ]; then
  echo "FAIL: set COMPONENT or RUNTIME_ASSET, not both" >&2
  exit 1
fi
if [ -z "${COMPONENT:-}" ] && [ -z "${RUNTIME_ASSET:-}" ]; then
  echo "FAIL: one of COMPONENT / RUNTIME_ASSET is required" >&2
  exit 1
fi

BOT_NAME="${BOT_NAME:-imagefs-bot}"
BOT_EMAIL="${BOT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PIN_SKIP="$WORK/pin-skip"
export PIN_SKIP

git clone --depth 1 \
  "https://x-access-token:${GH_TOKEN}@github.com/amphora-dev/content_manifest.git" \
  "$WORK/content_manifest"
MANIFEST="$WORK/content_manifest/content_manifest.json"
test -f "$MANIFEST"

python3 - "$MANIFEST" <<'PY'
import json, os, sys

path = sys.argv[1]
component = os.environ.get("COMPONENT") or None
runtime_asset = os.environ.get("RUNTIME_ASSET") or None
sha = os.environ["SHA256"]
size = int(os.environ["SIZE"])
asset = os.environ.get("ASSET_PATH") or None
ver_name = os.environ.get("VER_NAME") or None
remote = os.environ.get("REMOTE_URL") or None
kind = os.environ.get("KIND") or None
content_type = os.environ.get("CONTENT_TYPE") or None

with open(path, encoding="utf-8") as f:
    data = json.load(f)


def skip(message):
    print(message)
    open(os.environ["PIN_SKIP"], "w").write("1")
    raise SystemExit(0)


if runtime_asset is not None:
    entries = data.get("runtimeAssets")
    if not isinstance(entries, list):
        raise SystemExit("manifest has no runtimeAssets[]")
    entry = next((e for e in entries if e.get("assetPath") == runtime_asset), None)
    if entry is None:
        raise SystemExit(f"runtimeAssets[] has no entry for {runtime_asset}")

    unchanged = entry.get("sha256") == sha and int(entry.get("size") or 0) == size
    if remote is not None:
        unchanged = unchanged and entry.get("remoteUrl") == remote
    if unchanged:
        skip(f"{runtime_asset} pin already up to date; nothing to commit")

    entry["sha256"] = sha
    entry["size"] = size
    if remote is not None:
        entry["remoteUrl"] = remote
    print(f"bumped runtimeAssets[{runtime_asset}] sha={sha} size={size}")
else:
    entry = data["components"][component]

    unchanged = entry.get("sha256") == sha and int(entry.get("size") or 0) == size
    if asset is not None:
        unchanged = unchanged and entry.get("assetPath") == asset
    if remote is not None:
        unchanged = unchanged and entry.get("remoteUrl") == remote
    if unchanged:
        skip(f"{component} pin already up to date; nothing to commit")

    entry["sha256"] = sha
    entry["size"] = size
    if asset is not None:
        entry["assetPath"] = asset
    if remote is not None:
        entry["remoteUrl"] = remote
    if kind is not None:
        entry["kind"] = kind
    if content_type is not None:
        entry["contentType"] = content_type

    if component == "rootfs":
        old_ver = int(str(entry.get("version", "0")))
        entry["version"] = str(old_ver + 1)
        print(f"bumped rootfs pin v{old_ver} -> v{old_ver + 1} sha={sha} size={size}")
    elif component in ("box64", "wine", "dxvk", "vkd3d"):
        # WCP pins: install path is contents/<contentType>/<verName>-<verCode>/.
        # verName/verCode must mirror the package's profile.json so Amphora's
        # isInstalled + reconcileToPin stay idempotent across rebuilds.
        if ver_name is None:
            raise SystemExit(f"VER_NAME required for {component}")
        ctype = content_type or entry.get("contentType")
        if not ctype:
            defaults = {
                "box64": "Box64",
                "wine": "Proton",
                "dxvk": "DXVK",
                "vkd3d": "VKD3D",
            }
            ctype = defaults.get(component)
        if not ctype:
            raise SystemExit(f"CONTENT_TYPE required for {component}")
        entry["verName"] = ver_name
        entry["verCode"] = int(os.environ.get("VER_CODE") or 0)
        entry["contentType"] = ctype
        entry["kind"] = kind or "WCP"
        entry["version"] = f"{ctype}-{ver_name}-{entry['verCode']}"
        print(
            f"bumped {component} pin -> {entry.get('assetPath')} "
            f"version={entry['version']} sha={sha} size={size}"
        )
    else:
        if ver_name is not None:
            entry["verName"] = ver_name
            entry["version"] = ver_name
        print(f"bumped {component} pin sha={sha} size={size}")

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

if [ -f "$PIN_SKIP" ]; then
  exit 0
fi

cd "$WORK/content_manifest"
python3 validate_manifest.py content_manifest.json
git config user.name "$BOT_NAME"
git config user.email "$BOT_EMAIL"
git add content_manifest.json

if [ -n "${COMMIT_SUBJECT:-}" ]; then
  SUBJECT="$COMMIT_SUBJECT"
elif [ -n "${RUNTIME_ASSET:-}" ]; then
  SUBJECT="chore: pin ${RUNTIME_ASSET##*/} ${VER_NAME:-$SHA256}"
elif [ "$COMPONENT" = "rootfs" ]; then
  NEW_VER="$(python3 -c 'import json;print(json.load(open("content_manifest.json"))["components"]["rootfs"]["version"])')"
  SUBJECT="chore: pin imagefs rootfs v${NEW_VER}"
elif [ "$COMPONENT" = "box64" ]; then
  SUBJECT="chore: pin Box64 ${VER_NAME}"
else
  SUBJECT="chore: pin ${COMPONENT}"
fi

git commit -m "$(cat <<EOF
${SUBJECT}

Published by amphora-dev/imagefs CI.
EOF
)"
git push origin HEAD:main
