#!/usr/bin/env bash
# =============================================================================
# Inject a local wrapper-*.tzst into a running Amphora install (adb).
#
# Keeps the two-stage pipeline in sync so the next launch does not re-download
# the remote pin and overwrite imagefs:
#   1) files/runtime-assets/graphics_driver/wrapper.tzst (+ .sha256)
#   2) extract into files/imagefs/  (ICD + adrenotools/hooks + ICD JSON)
#   3) mirror into files/contents/adrenotools/wrapper/
#   4) arm .local-override so Amphora skips content_manifest re-fetch
#      (requires Amphora build with RuntimeAssetLocalOverride support)
#
# Usage:
#   adb devices   # one device
#   bash ci/wrapper/push-device.sh artifacts/wrapper-7eae6442f.tzst
#   bash ci/wrapper/push-device.sh artifacts/wrapper-7eae6442f.tzst app.amphora
#   bash ci/wrapper/push-device.sh --clear              # drop local-override only
#   bash ci/wrapper/push-device.sh --clear app.amphora
#
# Env:
#   PACKAGE   default app.amphora
#   ADB       default adb
# =============================================================================
set -euo pipefail

ADB="${ADB:-adb}"
CLEAR=0
TZST=""
PACKAGE="${PACKAGE:-app.amphora}"

usage() {
  echo "usage: $0 <wrapper-*.tzst> [package]" >&2
  echo "       $0 --clear [package]" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --clear) CLEAR=1; shift ;;
    -h|--help) usage ;;
    -*)
      echo "unknown flag: $1" >&2
      usage
      ;;
    *)
      if [ -z "$TZST" ] && [ "$CLEAR" = 0 ]; then
        TZST="$1"
      else
        PACKAGE="$1"
      fi
      shift
      ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing $1" >&2; exit 1; }; }
need "$ADB"
"$ADB" get-state >/dev/null

if [ "$CLEAR" = 1 ]; then
  echo "Clearing wrapper local-override on $PACKAGE"
  "$ADB" shell "run-as $PACKAGE sh -c '
    rm -f files/runtime-assets/graphics_driver/wrapper.tzst.local-override
    echo cleared
    ls files/runtime-assets/graphics_driver/wrapper.tzst* 2>/dev/null || true
  '"
  "$ADB" shell am force-stop "$PACKAGE" >/dev/null || true
  echo "OK: remote content_manifest pin applies again on next launch."
  exit 0
fi

[[ -n "$TZST" ]] || usage
[[ -f "$TZST" ]] || {
  echo "FAIL: not a file: $TZST" >&2
  exit 1
}

need zstd
need sha256sum

SHA="$(sha256sum "$TZST" | awk '{print $1}')"
SIZE="$(stat -c%s "$TZST")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "Extracting $TZST ($SIZE bytes, sha256=$SHA)"
tar -I zstd -xf "$TZST" -C "$STAGE"
[[ -f "$STAGE/usr/lib/libvulkan_wrapper.so" ]] || {
  echo "FAIL: tzst missing usr/lib/libvulkan_wrapper.so" >&2
  exit 1
}
[[ -f "$STAGE/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json" ]] || {
  echo "FAIL: tzst missing wrapper_icd.aarch64.json" >&2
  exit 1
}

echo "Device package: $PACKAGE"

# Host → /data/local/tmp (run-as cannot always read arbitrary host paths)
REMOTE_TMP="/data/local/tmp/amphora-wrapper-inject"
"$ADB" shell "rm -rf $REMOTE_TMP && mkdir -p $REMOTE_TMP/usr/lib $REMOTE_TMP/usr/share/vulkan/icd.d"

push_file() {
  local src="$1" dest="$2"
  "$ADB" push "$src" "$dest" >/dev/null
}

push_file "$TZST" "$REMOTE_TMP/wrapper.tzst"
echo "$SHA" >"$STAGE/pin.sha256"
push_file "$STAGE/pin.sha256" "$REMOTE_TMP/pin.sha256"

# Push extracted leaf libs (device often lacks zstd inside run-as)
for f in libvulkan_wrapper.so libadrenotools.so libmain_hook.so \
         libhook_impl.so libfile_redirect_hook.so libgsl_alloc_hook.so; do
  [[ -f "$STAGE/usr/lib/$f" ]] || {
    echo "FAIL: tzst missing usr/lib/$f" >&2
    exit 1
  }
  push_file "$STAGE/usr/lib/$f" "$REMOTE_TMP/usr/lib/$f"
done
push_file "$STAGE/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json" \
  "$REMOTE_TMP/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json"

"$ADB" shell "run-as $PACKAGE sh -c '
set -e
RA=files/runtime-assets/graphics_driver
IMG=files/imagefs/usr/lib
ICD=files/imagefs/usr/share/vulkan/icd.d
ADR=files/contents/adrenotools/wrapper
SRC=$REMOTE_TMP
mkdir -p \"\$RA\" \"\$IMG\" \"\$ICD\" \"\$ADR\"
cp \"\$SRC/wrapper.tzst\" \"\$RA/wrapper.tzst\"
cp \"\$SRC/pin.sha256\" \"\$RA/wrapper.tzst.sha256\"
# Arm Amphora local-override (skips remote content_manifest re-download).
cp \"\$SRC/pin.sha256\" \"\$RA/wrapper.tzst.local-override\"
for f in libvulkan_wrapper.so libadrenotools.so libmain_hook.so \
         libhook_impl.so libfile_redirect_hook.so libgsl_alloc_hook.so; do
  cp \"\$SRC/usr/lib/\$f\" \"\$IMG/\$f\"
  cp \"\$SRC/usr/lib/\$f\" \"\$ADR/\$f\"
  chmod 755 \"\$IMG/\$f\" \"\$ADR/\$f\"
done
cp \"\$SRC/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json\" \"\$ICD/wrapper_icd.aarch64.json\"
cp \"\$SRC/pin.sha256\" \"\$IMG/libvulkan_wrapper.so.wrapper.sha256\"
cp \"\$SRC/pin.sha256\" \"\$ADR/libvulkan_wrapper.so.wrapper.sha256\"
# Never leave android-stub shadows in imagefs.
rm -f \"\$IMG/libcutils.so\" \"\$IMG/libsync.so\" \"\$IMG/libhardware.so\"
echo RA=\$(cat \"\$RA/wrapper.tzst.sha256\")
echo OVERRIDE=\$(cat \"\$RA/wrapper.tzst.local-override\")
echo IMG=\$(cat \"\$IMG/libvulkan_wrapper.so.wrapper.sha256\")
ls -la \"\$RA/wrapper.tzst\" \"\$RA/wrapper.tzst.local-override\" \"\$IMG/libvulkan_wrapper.so\" \"\$IMG/libadrenotools.so\" \"\$ICD/wrapper_icd.aarch64.json\"
'"

"$ADB" shell "rm -rf $REMOTE_TMP" >/dev/null || true
"$ADB" shell am force-stop "$PACKAGE" >/dev/null || true

echo "OK: injected wrapper pin $SHA into $PACKAGE (runtime-assets + imagefs + adrenotools + local-override)."
echo "Amphora builds with RuntimeAssetLocalOverride will skip remote re-fetch for this asset."
echo "Clear with: $0 --clear $PACKAGE"
