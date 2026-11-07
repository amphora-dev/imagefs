#!/usr/bin/env bash
# Validate the Turnip adrenotools package (fail-closed, before upload/publish):
# zip layout, meta.json, and the ELF properties adrenotools needs to load
# libvulkan_freedreno.so in a namespace that only sees /system libraries.
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
ENV_FILE="${ENV_FILE:-$ARTIFACT_DIR/turnip.env}"
test -f "$ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

zip="$ARTIFACT_DIR/$ZIP_NAME"
test -f "$zip"
test -f "$zip.sha256sum"
(
  cd "$ARTIFACT_DIR"
  sha256sum -c "$ZIP_NAME.sha256sum"
)
test "$(sha256sum "$zip" | awk '{print $1}')" = "$SHA256"
test "$(stat -c%s "$zip")" = "$SIZE"
test "$SIZE" -gt 1000000

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Entries exactly libvulkan_freedreno.so, meta.json, LICENSE-mesa.rst (in
# that order) and meta.json exactly what build-turnip.sh writes.
MESA_VERSION="$MESA_VERSION" FULL_VERSION="$FULL_VERSION" \
  python3 - "$zip" "$work" <<'PY'
import json
import os
import sys
import zipfile

path, out = sys.argv[1], sys.argv[2]
want = ["libvulkan_freedreno.so", "meta.json", "LICENSE-mesa.rst"]
with zipfile.ZipFile(path) as z:
    names = z.namelist()
    if names != want:
        sys.exit(f"zip entries {names} != {want}")
    z.extractall(out)
    meta = json.loads(z.read("meta.json"))

v = os.environ["MESA_VERSION"]
want_meta = {
    "schemaVersion": 1,
    "name": f"Turnip (Mesa {v})",
    "description": f"Mesa {v} Turnip (KGSL) built by amphora-dev/imagefs: "
    "MR 44838 KGSL backport + Qualcomm gralloc UBWC detection",
    "author": "Amphora",
    "packageVersion": "1",
    "vendor": "Mesa",
    "driverVersion": os.environ["FULL_VERSION"],
    "minApi": 30,
    "libraryName": "libvulkan_freedreno.so",
}
if meta != want_meta:
    sys.exit(f"meta.json {meta} != {want_meta}")
print("zip layout and meta.json OK")
PY

so="$work/libvulkan_freedreno.so"
fail() {
  echo "$so: $*" >&2
  exit 1
}

header="$(readelf -hW "$so")"
grep -Eq '^ *Class: +ELF64$' <<< "$header" || fail "not ELF64"
grep -Eq '^ *Machine: +AArch64$' <<< "$header" || fail "not AArch64"
grep -Eq '^ *Type: +DYN ' <<< "$header" || fail "not a shared object (DYN)"

dynamic="$(readelf -dW "$so")"
grep -Fq '(SONAME)' <<< "$dynamic" || fail "no SONAME"
soname="$(awk -F'[][]' '/\(SONAME\)/ { print $2 }' <<< "$dynamic")"
test "$soname" = libvulkan_freedreno.so || fail "SONAME is $soname"
if grep -q 'TEXTREL' <<< "$dynamic"; then
  fail "has TEXTREL"
fi
# A leftover build-tree RUNPATH ($ORIGIN/../../android_stub) would point the
# loader at stub libraries; the package must resolve only /system libs.
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic"; then
  fail "has RPATH/RUNPATH"
fi

# Real libraries on /system (android-stub only links against stubs of
# hardware/log/nativewindow/sync). libc++_shared.so, libdrm.so and imagefs
# libraries are not visible to the adrenotools namespace.
needed="$(awk -F'[][]' '/\(NEEDED\)/ { print $2 }' <<< "$dynamic")"
echo "NEEDED:"
sed 's/^/  /' <<< "$needed"
grep -qx libc.so <<< "$needed" || fail "libc.so not in NEEDED"
while read -r lib; do
  case "$lib" in
    libc.so | libm.so | libdl.so | liblog.so | libz.so | libsync.so | libnativewindow.so | libhardware.so) ;;
    *) fail "NEEDED $lib is not on the allow-list" ;;
  esac
done <<< "$needed"

# -Dplatforms=android exports only the hwvulkan module HMI (same as
# WN-Turnip); adrenotools/the wrapper reach the driver through it.
syms="$(readelf --dyn-syms -W "$so")"
awk '
  $7 != "UND" { name = $8; sub(/@.*/, "", name); if (name == "HMI") found = 1 }
  END { exit !found }
' <<< "$syms" || fail "does not define HMI"
if grep -q '__emutls_' <<< "$syms"; then
  fail "uses emulated TLS (__emutls_*)"
fi

# 16 KB page devices need every LOAD segment aligned to at least 0x4000.
aligns="$(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }')"
test -n "$aligns" || fail "no LOAD segments"
while read -r align; do
  test "$((align))" -ge $((0x4000)) || fail "LOAD segment align $align < 0x4000"
done <<< "$aligns"

echo "turnip OK: $ZIP_NAME ($SIZE bytes)"
