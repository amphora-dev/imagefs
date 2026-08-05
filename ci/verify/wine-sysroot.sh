#!/usr/bin/env bash
# Verify the source-built x86_64 development sysroot consumed by Proton Wine.
set -euo pipefail

SYSROOT="${SYSROOT:-/tmp/wine-sysroot}"
test -d "$SYSROOT/usr/lib"
test -d "$SYSROOT/usr/include"

for path in \
  usr/include/GL/gl.h \
  usr/include/vulkan/vulkan.h \
  usr/include/X11/Xlib.h \
  usr/include/alsa/asoundlib.h \
  usr/include/glib-2.0/glib.h \
  usr/include/gstreamer-1.0/gst/gst.h \
  usr/lib/libGL.so.1 \
  usr/lib/libEGL.so.1 \
  usr/lib/libX11.so \
  usr/lib/libXext.so \
  usr/lib/libasound.so \
  usr/lib/libglib-2.0.so \
  usr/lib/libgstreamer-1.0.so \
  usr/lib/libgstgl-1.0.so \
  usr/lib/libgnutls.so \
  usr/lib/libfontconfig.so \
  usr/lib/libfreetype.so \
  usr/lib/libSDL2.so; do
  test -e "$SYSROOT/$path" || {
    echo "missing Wine sysroot input: $path" >&2
    exit 1
  }
done

python3 - "$SYSROOT" <<'PY'
import os
import subprocess
import sys

root = sys.argv[1]
checked = 0
for directory, _, names in os.walk(os.path.join(root, "usr", "lib")):
    for name in names:
        path = os.path.join(directory, name)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        kind = subprocess.run(
            ["file", "-b", path], check=True, text=True, stdout=subprocess.PIPE
        ).stdout
        if "ELF" not in kind:
            continue
        checked += 1
        if "ELF 64-bit" not in kind or "x86-64" not in kind:
            raise SystemExit(f"non-x86_64 ELF in Wine sysroot: {path}: {kind.strip()}")
if checked < 30:
    raise SystemExit(f"unexpectedly small Wine sysroot: only {checked} ELF files")
for directory, _, names in os.walk(os.path.join(root, "usr")):
    for name in names:
        if not name.endswith((".pc", ".la", ".cmake")):
            continue
        path = os.path.join(directory, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as stream:
            if b"/data/data/com.termux" in stream.read():
                raise SystemExit(f"Termux path leaked into Wine sysroot metadata: {path}")
print(f"validated {checked} x86_64 sysroot ELF files")
PY

echo "Self-built Wine sysroot verified"
