#!/usr/bin/env bash
# Validate Proton WCP structure, architecture and Android 16KB ELF alignment.
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
ENV_FILE="${ENV_FILE:-$ARTIFACT_DIR/proton-wine-wcp.env}"
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
test "$SIZE" -gt 50000000

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -I zstd -xf "$wcp" -C "$work"

test "$(readlink "$work/bin/wine")" = ../lib/wine/x86_64-unix/wine
test "$(readlink "$work/bin/wine-preloader")" = ../lib/wine/x86_64-unix/wine-preloader
test -f "$work/lib/wine/x86_64-unix/wine"
test -f "$work/lib/wine/x86_64-windows/ntdll.dll"
test -f "$work/lib/wine/i386-windows/ntdll.dll"
test -f "$work/prefixPack.txz"

python3 - "$work/profile.json" "$FULL_VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    profile = json.load(stream)
assert profile["type"] == "Proton"
assert profile["versionName"] == sys.argv[2]
assert profile["versionCode"] == 0
assert profile["wine"] == {
    "binPath": "bin",
    "libPath": "lib",
    "prefixPack": "prefixPack.txz",
}
PY

file "$work/lib/wine/x86_64-unix/wine" | grep -q 'ELF 64-bit.*x86-64'
file "$work/lib/wine/x86_64-windows/ntdll.dll" | grep -q 'PE32+.*x86-64'
file "$work/lib/wine/i386-windows/ntdll.dll" | grep -q 'PE32.*Intel 80386'

python3 - "$work/lib/wine/x86_64-unix" <<'PY'
import os
import subprocess
import sys

root = sys.argv[1]
checked = 0
standard_relr = 0
for directory, _, names in os.walk(root):
    for name in names:
        path = os.path.join(directory, name)
        kind = subprocess.run(
            ["file", "-b", path], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        if "ELF 64-bit" not in kind:
            continue
        checked += 1
        program_headers = subprocess.run(
            ["readelf", "-lW", path], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        loads = [line.split() for line in program_headers.splitlines() if line.lstrip().startswith("LOAD ")]
        if not loads:
            raise SystemExit(f"{path}: no PT_LOAD segments")
        for fields in loads:
            offset = int(fields[1], 16)
            vaddr = int(fields[2], 16)
            align = int(fields[-1], 16)
            if align < 0x4000:
                raise SystemExit(f"{path}: PT_LOAD alignment {align:#x} is below 16KB")
            if (vaddr - offset) % 0x4000:
                raise SystemExit(f"{path}: PT_LOAD offset/vaddr are not 16KB congruent")
        dynamic = subprocess.run(
            ["readelf", "-dW", path], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        if "/data/data/com.termux" in dynamic:
            raise SystemExit(f"{path}: contains Termux runtime path")
        if "libpulse.so" in dynamic:
            raise SystemExit(f"{path}: unexpectedly depends on PulseAudio")
        android_relr_tags = ("6fffe000", "6fffe001", "6fffe003")
        if any(tag in dynamic.lower() for tag in android_relr_tags):
            raise SystemExit(f"{path}: contains Android-private RELR dynamic tags")
        if "(RELR)" in dynamic and "(RELRSZ)" in dynamic and "(RELRENT)" in dynamic:
            standard_relr += 1
if checked == 0:
    raise SystemExit("no x86_64 Unix ELF files checked")
if standard_relr == 0:
    raise SystemExit("no x86_64 Unix ELF uses standard DT_RELR tags")
print(
    f"validated {checked} x86_64 Unix ELF files "
    f"({standard_relr} with standard DT_RELR)"
)
PY

echo "Proton WCP verified: $WCP_NAME"
