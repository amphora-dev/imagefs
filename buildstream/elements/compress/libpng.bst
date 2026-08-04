kind: autotools

description: |
  libpng 1.6.44 for Android/Bionic with PNG16_0 symbol versioning.

  The post-install phase mirrors the production fail-closed checks and relinks
  from libtool objects when Android libtool drops the version script or SONAME.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- filename: compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: libpng:libpng-1.6.44.tar.xz
  ref: 60c4da1d5b7f0aa8d158da48e8f8afa9773c1c8baa5d21974df61f1886b8ce8e

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-shared
    --disable-static
    --enable-arm-neon=no

config:
  strip-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    real=
    for candidate in "$libdir"/libpng16.so*; do
      if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
        real="$candidate"
      fi
    done
    test -n "$real"

    soname="$(readelf -dW "$real" | awk -F'[][]' '/SONAME/{print $2}')"
    if ! readelf -V "$real" | grep -q PNG16_0 ||
       [ "$soname" != libpng16.so.16 ]; then
      test -f libpng.vers
      grep -q PNG16_0 libpng.vers
      objects="$(find \
        .libs mips/.libs powerpc/.libs intel/.libs arm/.libs \
        -type f -name '*.o' 2>/dev/null | LC_ALL=C sort)"
      test -n "$objects"
      "$CC" -shared -fPIC -O2 \
        -o "$real" \
        $objects \
        -L/opt/android-sysroot/usr/lib -lz -lm \
        -Wl,--version-script="$PWD/libpng.vers" \
        -Wl,--no-undefined-version \
        -Wl,-soname,libpng16.so.16 \
        -Wl,-rpath,/usr/lib
    fi

    final="$libdir/libpng16.so.16.44.0"
    if [ "$real" != "$final" ]; then
      install -m 0755 "$real" "$final"
      rm -f "$real"
    fi
    ln -sfn libpng16.so.16.44.0 "$libdir/libpng16.so.16"
    ln -sfn libpng16.so.16 "$libdir/libpng16.so"
    ln -sfn libpng16.so "$libdir/libpng.so"
    find "%{install-root}" -type f -name '*.la' -delete
    "$STRIP" "$final"

    test "$(readelf -dW "$final" |
      awk -F'[][]' '/SONAME/{print $2}')" = libpng16.so.16
    readelf -V "$final" | grep -q PNG16_0
    if "$NM" -D "$final" | grep -Eq ' U png_.*_neon$'; then
      echo "libpng has unresolved NEON symbols" >&2
      exit 1
    fi
    python3 - "$final" <<'PY'
    import re
    import subprocess
    import sys

    output = subprocess.check_output(["readelf", "-lW", sys.argv[1]], text=True)
    for line in output.splitlines():
        match = re.match(r"\s*LOAD\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)", line)
        if match:
            offset, vaddr = (int(value, 16) for value in match.groups())
            if (vaddr - offset) % 4096:
                raise SystemExit(f"non-congruent LOAD: {line}")
    PY
