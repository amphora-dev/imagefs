#!/usr/bin/env bash
# Build Mesa WGL (opengl32.dll + libgallium_wgl.dll with zink + softpipe) for
# x86_64 and i686 PE inside a BuildStream sandbox and pack mesa-wgl-*.tzst.
#
# Amphora links these DLLs into every prefix's system32/syswow64 and runs
# Wine with opengl32=n,b. Mesa's WGL screen tries zink first and falls back
# to softpipe when zink_create_screen fails (GALLIUM_DRIVER is left unset).
#
# Every meson flag lives in this script, so its sha256 is part of the asset
# identity: mesa-wgl-<MESA_VERSION>-s<sha256(this script)[0:8]>.tzst.
#
# Output (under $OUTPUT_DIR):
#   mesa-wgl-<FULL_VERSION>.tzst
#   mesa-wgl-<FULL_VERSION>.tzst.sha256sum
#   mesa-wgl.env   # FULL_VERSION / TZST_NAME / SHA256 / SIZE / …
set -euo pipefail

: "${LLVM_MINGW_ROOT:?BuildStream must provide LLVM_MINGW_ROOT}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${MESA_VERSION:?BuildStream must provide MESA_VERSION}"
: "${MESA_TARBALL_SHA256:?BuildStream must provide MESA_TARBALL_SHA256}"

JOBS="${JOBS:-$(nproc)}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/mesa-wgl-build}"
PACKAGE_ROOT="${PACKAGE_ROOT:-/tmp/mesa-wgl-stage}"
SRC_DIR="$PWD"

for tool in meson ninja python3 tar zstd sha256sum flex bison; do
  command -v "$tool" >/dev/null || {
    echo "missing build tool: $tool" >&2
    exit 1
  }
done
python3 -c 'import mako, yaml' || {
  echo "python3 needs mako and yaml (PyYAML) for Mesa's generators" >&2
  exit 1
}

for tool in \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang" \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang++" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang++" \
  "$LLVM_MINGW_ROOT/bin/llvm-ar" \
  "$LLVM_MINGW_ROOT/bin/llvm-strip" \
  "$LLVM_MINGW_ROOT/bin/llvm-readobj" \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-windres" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-windres"; do
  test -x "$tool" || {
    echo "missing compiler tool: $tool" >&2
    exit 1
  }
done

test -f "$SRC_DIR/VERSION" || {
  echo "no Mesa source tree in $SRC_DIR (VERSION missing)" >&2
  exit 1
}
src_version="$(tr -d '\n' < "$SRC_DIR/VERSION")"
test "$src_version" = "$MESA_VERSION" || {
  echo "Mesa source is $src_version, element says MESA_VERSION=$MESA_VERSION" >&2
  exit 1
}

SCRIPT_SHA8="$(sha256sum "$0" | cut -c1-8)"
FULL_VERSION="${MESA_VERSION}-s${SCRIPT_SHA8}"
TZST_NAME="mesa-wgl-${FULL_VERSION}.tzst"

export PATH="$LLVM_MINGW_ROOT/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# No host .pc file may satisfy a Windows dependency.
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/empty-pkgconfig"
export PKG_CONFIG_LIBDIR="$BUILD_ROOT/empty-pkgconfig"
unset PKG_CONFIG_PATH

# zink has C++ files: link libc++/libunwind/winpthread statically so the DLLs
# import only Windows system DLLs that Wine provides.
write_cross_file() {
  local triple="$1" cpu_family="$2" cpu="$3"
  cat > "$BUILD_ROOT/cross-${cpu}.txt" <<EOF
[binaries]
c = '$LLVM_MINGW_ROOT/bin/${triple}-clang'
cpp = '$LLVM_MINGW_ROOT/bin/${triple}-clang++'
ar = '$LLVM_MINGW_ROOT/bin/llvm-ar'
strip = '$LLVM_MINGW_ROOT/bin/llvm-strip'
windres = '$LLVM_MINGW_ROOT/bin/${triple}-windres'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_link_args = ['-static', '-static-libgcc', '-static-libstdc++']
cpp_link_args = ['-static', '-static-libgcc', '-static-libstdc++']

[host_machine]
system = 'windows'
cpu_family = '${cpu_family}'
cpu = '${cpu}'
endian = 'little'
EOF
}

write_cross_file x86_64-w64-mingw32 x86_64 x86_64
write_cross_file i686-w64-mingw32 x86 i686

# shellcheck disable=SC2054 # zink,softpipe is one meson array value
MESON_FLAGS=(
  --buildtype=release
  --wrap-mode=nodownload
  -Db_ndebug=true
  -Dplatforms=windows
  -Dgallium-drivers=zink,softpipe
  -Dvulkan-drivers=
  -Dllvm=disabled
  -Dshared-llvm=disabled
  -Dopengl=true
  -Degl=disabled
  -Dgles1=disabled
  -Dgles2=disabled
  -Dglx=disabled
  -Dgbm=disabled
  -Dglvnd=disabled
  -Dxmlconfig=disabled
  -Dexpat=disabled
  -Dzlib=disabled
  -Dzstd=disabled
  -Dshader-cache=disabled
  -Dvideo-codecs=
  -Dgallium-va=disabled
  -Dgallium-mediafoundation=disabled
  -Dmicrosoft-clc=disabled
  -Dspirv-tools=disabled
  -Dvalgrind=disabled
  -Dlibunwind=disabled
  -Dlmsensors=disabled
  -Dbuild-tests=false
  -Dmin-windows-version=8
)

build_arch() {
  local cpu="$1"
  local dir="$BUILD_ROOT/build-$cpu"
  meson setup "$dir" "$SRC_DIR" \
    --cross-file "$BUILD_ROOT/cross-${cpu}.txt" \
    "${MESON_FLAGS[@]}" || {
    tail -150 "$dir/meson-logs/meson-log.txt" >&2 || true
    exit 1
  }
  ninja -C "$dir" -j "$JOBS"
}

build_arch x86_64
build_arch i686

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/system32" "$PACKAGE_ROOT/syswow64" \
  "$PACKAGE_ROOT/licenses" "$OUTPUT_DIR"

stage_dlls() {
  local cpu="$1" dest="$2" name found
  for name in opengl32.dll libgallium_wgl.dll; do
    found="$(find "$BUILD_ROOT/build-$cpu" -name "$name" -type f | head -n1)"
    test -n "$found" || {
      echo "missing $name under $BUILD_ROOT/build-$cpu" >&2
      exit 1
    }
    llvm-strip --strip-unneeded -o "$dest/$name" "$found"
    chmod 0644 "$dest/$name"
  done
}

stage_dlls x86_64 "$PACKAGE_ROOT/system32"
stage_dlls i686 "$PACKAGE_ROOT/syswow64"

# Imports Wine provides as builtins. vulkan-1 is dlopened by zink at runtime,
# so it must not appear here; neither may libc++/libunwind/libwinpthread or
# zlib/zstd DLLs (none of them exist in a Wine prefix).
import_allowed() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    kernel32.dll | user32.dll | gdi32.dll | advapi32.dll | ntdll.dll | ws2_32.dll) return 0 ;;
    api-ms-win-*.dll) return 0 ;;
    libgallium_wgl.dll) test "$2" = opengl32.dll ;;
    *) return 1 ;;
  esac
}

check_dll() {
  local path="$1" machine="$2" name imports bad=0 imp
  name="$(basename "$path")"
  llvm-readobj --file-headers "$path" | grep -q "Machine: ${machine} " || {
    echo "$path is not $machine:" >&2
    llvm-readobj --file-headers "$path" | grep Machine >&2
    exit 1
  }
  imports="$(llvm-readobj --coff-imports "$path" | awk '$1 == "Name:" && !seen[$2]++ { print $2 }')"
  echo "imports of $path:"
  printf '%s\n' "$imports" | sed 's/^/  /'
  while read -r imp; do
    import_allowed "$imp" "$name" || {
      echo "$path imports $imp, which is not on the allow-list" >&2
      bad=1
    }
  done <<< "$imports"
  test "$bad" = 0 || exit 1
}

check_opengl32_exports() {
  local path="$1" arch="$2" exports sym
  exports="$(llvm-readobj --coff-exports "$path" | awk '$1 == "Name:" { print $2 }')"
  for sym in wglCreateContext wglGetProcAddress wglSwapBuffers glBegin; do
    printf '%s\n' "$exports" | grep -qx "$sym" || {
      echo "$path does not export $sym" >&2
      exit 1
    }
  done
  if [ "$arch" = i686 ] && printf '%s\n' "$exports" | grep -q '@'; then
    echo "$path exports stdcall-decorated names:" >&2
    printf '%s\n' "$exports" | grep '@' | head >&2
    exit 1
  fi
}

for dir_machine in system32:IMAGE_FILE_MACHINE_AMD64:x86_64 \
  syswow64:IMAGE_FILE_MACHINE_I386:i686; do
  IFS=: read -r dir machine arch <<< "$dir_machine"
  check_dll "$PACKAGE_ROOT/$dir/opengl32.dll" "$machine"
  check_dll "$PACKAGE_ROOT/$dir/libgallium_wgl.dll" "$machine"
  check_opengl32_exports "$PACKAGE_ROOT/$dir/opengl32.dll" "$arch"
  for driver in zink softpipe; do
    grep -a -q "$driver" "$PACKAGE_ROOT/$dir/libgallium_wgl.dll" || {
      echo "$dir/libgallium_wgl.dll has no $driver driver" >&2
      exit 1
    }
  done
done

test -d "$SRC_DIR/licenses" || {
  echo "Mesa source has no licenses/ directory" >&2
  exit 1
}
cp -R "$SRC_DIR/licenses/." "$PACKAGE_ROOT/licenses/"
cp "$SRC_DIR/docs/license.rst" "$PACKAGE_ROOT/licenses/license.rst"

# Deterministic tar: fixed order, owner, modes and mtimes; single-threaded
# zstd so the bytes do not depend on the runner's core count.
tar --sort=name --owner=0 --group=0 --numeric-owner \
  --mode='a+rX,go-w' \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime \
  -C "$PACKAGE_ROOT" -cf - licenses syswow64 system32 |
  zstd -19 -T1 -q -o "$OUTPUT_DIR/$TZST_NAME"

(
  cd "$OUTPUT_DIR"
  sha256sum "$TZST_NAME" > "$TZST_NAME.sha256sum"
)
size="$(stat -c%s "$OUTPUT_DIR/$TZST_NAME")"
sha="$(awk '{print $1}' "$OUTPUT_DIR/$TZST_NAME.sha256sum")"

cat > "$OUTPUT_DIR/mesa-wgl.env" <<EOF
FULL_VERSION=$FULL_VERSION
MESA_VERSION=$MESA_VERSION
MESA_TARBALL_SHA256=$MESA_TARBALL_SHA256
SCRIPT_SHA8=$SCRIPT_SHA8
TZST_NAME=$TZST_NAME
SHA256=$sha
SIZE=$size
EOF

tar -I zstd -tvf "$OUTPUT_DIR/$TZST_NAME"
cat "$OUTPUT_DIR/mesa-wgl.env"
