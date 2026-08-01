#!/usr/bin/env bash
# =============================================================================
# Inject a local wrapper-*.tzst into a running Amphora install (adb).
#
# Keeps the two-stage pipeline in sync so the next launch does not re-download
# the remote pin and overwrite imagefs:
#   1) files/runtime-assets/graphics_driver/wrapper.tzst (+ .sha256)
#   2) extract into files/imagefs/  (ICD + adrenotools/hooks + ICD JSON)
#   3) mirror into files/contents/adrenotools/wrapper/
#
# Usage:
#   adb devices   # one device
#   bash ci/wrapper/push-device.sh artifacts/wrapper-7eae6442f.tzst
#   bash ci/wrapper/push-device.sh artifacts/wrapper-7eae6442f.tzst app.amphora
#
# Env:
#   PACKAGE   default app.amphora
#   ADB       default adb
# =============================================================================
set -euo pipefail

TZST="${1:?usage: $0 <wrapper-*.tzst> [package]}"
PACKAGE="${2:-${PACKAGE:-app.amphora}}"
ADB="${ADB:-adb}"

[[ -f "$TZST" ]] || {
  echo "FAIL: not a file: $TZST" >&2
  exit 1
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing $1" >&2; exit 1; }; }
need "$ADB"
need zstd
need sha256sum
need python3

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
"$ADB" get-state >/dev/null

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
echo IMG=\$(cat \"\$IMG/libvulkan_wrapper.so.wrapper.sha256\")
ls -la \"\$RA/wrapper.tzst\" \"\$IMG/libvulkan_wrapper.so\" \"\$IMG/libadrenotools.so\" \"\$ICD/wrapper_icd.aarch64.json\"
'"

"$ADB" shell "rm -rf $REMOTE_TMP" >/dev/null || true
"$ADB" shell am force-stop "$PACKAGE" >/dev/null || true

echo "OK: injected wrapper pin $SHA into $PACKAGE (runtime-assets + imagefs + adrenotools content)."
echo "Note: content_manifest still points at the remote pin — a cold provision may re-download"
echo "unless the Release + content_manifest sha match this build (run the wrapper CI on main)."
