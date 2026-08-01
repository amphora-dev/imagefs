#!/usr/bin/env bash
# Bump one component pin in amphora-dev/content_manifest and push to main.
#
# Required env:
#   GH_TOKEN              — PAT with write access to content_manifest
#   COMPONENT             — e.g. rootfs | box64
#   SHA256                — artifact sha256
#   SIZE                  — artifact size in bytes
#
# Optional env (box64 / versioned assets):
#   ASSET_PATH            — e.g. Box64-0.4.3-abc.wcp (defaults unchanged)
#   VER_NAME              — e.g. 0.4.3-abc
#   REMOTE_URL            — full download URL
#   KIND / CONTENT_TYPE   — defaults: ROOTFS for rootfs, WCP/Box64 for box64
#   COMMIT_SUBJECT        — override commit title body first line
#   BOT_NAME / BOT_EMAIL
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
  echo "WARN: GH_TOKEN not set; skip content_manifest pin update" >&2
  exit 0
fi

: "${COMPONENT:?COMPONENT required}"
: "${SHA256:?SHA256 required}"
: "${SIZE:?SIZE required}"

BOT_NAME="${BOT_NAME:-imagefs-bot}"
BOT_EMAIL="${BOT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 \
  "https://x-access-token:${GH_TOKEN}@github.com/amphora-dev/content_manifest.git" \
  "$WORK/content_manifest"
MANIFEST="$WORK/content_manifest/content_manifest.json"
test -f "$MANIFEST"

python3 - "$MANIFEST" <<'PY'
import json, os, sys

path = sys.argv[1]
component = os.environ["COMPONENT"]
sha = os.environ["SHA256"]
size = int(os.environ["SIZE"])
asset = os.environ.get("ASSET_PATH") or None
ver_name = os.environ.get("VER_NAME") or None
remote = os.environ.get("REMOTE_URL") or None
kind = os.environ.get("KIND") or None
content_type = os.environ.get("CONTENT_TYPE") or None

with open(path, encoding="utf-8") as f:
    data = json.load(f)

entry = data["components"][component]
same = entry.get("sha256") == sha and int(entry.get("size") or 0) == size
if asset is not None:
    same = same and entry.get("assetPath") == asset
if remote is not None:
    same = same and entry.get("remoteUrl") == remote

# Amphora installs ARCHIVE wrappers via RuntimeAssetProvisioner from
# runtimeAssets[] (TarCompressorUtils reads filesDir/runtime-assets/<assetPath>).
# components.turnip is the UI/pin; both must stay in sync or the device keeps
# the stale WinNative blob even after components.* is bumped.
runtime_synced = True
target_asset = asset or entry.get("assetPath")
if target_asset and isinstance(data.get("runtimeAssets"), list):
    for ra in data["runtimeAssets"]:
        if ra.get("assetPath") != target_asset:
            continue
        if (
            ra.get("sha256") != sha
            or int(ra.get("size") or 0) != size
            or (remote is not None and ra.get("remoteUrl") != remote)
        ):
            runtime_synced = False
        break

if same and runtime_synced:
    print(f"{component} pin already up to date; nothing to commit")
    open("/tmp/content-manifest-pin-skip", "w").write("1")
    raise SystemExit(0)

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
elif component == "box64":
    if ver_name is None:
        raise SystemExit("VER_NAME required for box64")
    entry["verName"] = ver_name
    entry["verCode"] = int(os.environ.get("VER_CODE") or 0)
    entry["version"] = f"Box64-{ver_name}-{entry['verCode']}"
    entry.setdefault("kind", "WCP")
    entry.setdefault("contentType", "Box64")
    print(f"bumped box64 pin -> {entry.get('assetPath')} sha={sha} size={size}")
elif component == "turnip":
    # turnip pin = Pipetto vulkan wrapper.tzst (ARCHIVE), not freedreno Turnip.
    entry.setdefault("kind", "ARCHIVE")
    entry.setdefault("compression", "zstd")
    entry.setdefault("assetPath", "graphics_driver/wrapper.tzst")
    if ver_name is not None:
        entry["version"] = ver_name
    print(f"bumped turnip(wrapper) pin -> {entry.get('assetPath')} sha={sha} size={size}")
else:
    if ver_name is not None:
        entry["verName"] = ver_name
        entry["version"] = ver_name
    print(f"bumped {component} pin sha={sha} size={size}")

# Keep runtimeAssets[] twin in sync for the same assetPath (wrapper.tzst, …).
if target_asset and isinstance(data.get("runtimeAssets"), list):
    for ra in data["runtimeAssets"]:
        if ra.get("assetPath") != target_asset:
            continue
        old = (ra.get("sha256"), ra.get("size"), ra.get("remoteUrl"))
        ra["sha256"] = sha
        ra["size"] = size
        if remote is not None:
            ra["remoteUrl"] = remote
        print(
            f"synced runtimeAssets[{target_asset}] "
            f"{old} -> {(ra.get('sha256'), ra.get('size'), ra.get('remoteUrl'))}"
        )
        break

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

if [ -f /tmp/content-manifest-pin-skip ]; then
  exit 0
fi

cd "$WORK/content_manifest"
git config user.name "$BOT_NAME"
git config user.email "$BOT_EMAIL"
git add content_manifest.json

if [ -n "${COMMIT_SUBJECT:-}" ]; then
  SUBJECT="$COMMIT_SUBJECT"
elif [ "$COMPONENT" = "rootfs" ]; then
  NEW_VER="$(python3 -c 'import json;print(json.load(open("content_manifest.json"))["components"]["rootfs"]["version"])')"
  SUBJECT="chore: pin imagefs rootfs v${NEW_VER}"
elif [ "$COMPONENT" = "box64" ]; then
  SUBJECT="chore: pin Box64 ${VER_NAME}"
elif [ "$COMPONENT" = "turnip" ]; then
  SUBJECT="chore: pin wrapper ${VER_NAME:-tzst}"
else
  SUBJECT="chore: pin ${COMPONENT}"
fi

git commit -m "$(cat <<EOF
${SUBJECT}

Published by amphora-dev/imagefs CI.
EOF
)"
git push origin HEAD:main
