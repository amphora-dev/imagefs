#!/usr/bin/env bash
# Build pinned DXVK (x86_64 + i686 PE) inside a BuildStream sandbox and emit WCP.
set -euo pipefail

: "${LLVM_MINGW_ROOT:?BuildStream must provide LLVM_MINGW_ROOT}"
: "${GLSLANG_ROOT:?BuildStream must provide GLSLANG_ROOT}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${DXVK_COMMIT:?BuildStream must provide DXVK_COMMIT}"
: "${DXVK_VERSION:?BuildStream must provide DXVK_VERSION}"

JOBS="${JOBS:-$(nproc)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
PACKAGE_ROOT=/tmp/dxvk-wcp
BUILD_ROOT=/tmp/dxvk-build

for tool in meson ninja patch python3 tar xz file; do
  command -v "$tool" >/dev/null || {
    echo "missing build tool: $tool" >&2
    exit 1
  }
done

test -x "$GLSLANG_ROOT/bin/glslangValidator" ||
  test -x "$GLSLANG_ROOT/bin/glslang" || {
  echo "missing glslang at $GLSLANG_ROOT/bin" >&2
  exit 1
}

for tool in \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang" \
  "$LLVM_MINGW_ROOT/bin/llvm-ar" \
  "$LLVM_MINGW_ROOT/bin/llvm-strip" \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-windres" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-windres"; do
  test -x "$tool" || {
    echo "missing compiler: $tool" >&2
    exit 1
  }
done

export PATH="$GLSLANG_ROOT/bin:$LLVM_MINGW_ROOT/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ -f .bst/patches/dxvk-gplasync-master.patch ]; then
  patch -p1 < .bst/patches/dxvk-gplasync-master.patch
fi

mkdir -p "$BUILD_ROOT"
cat > "$BUILD_ROOT/cross-x86_64.txt" <<EOF
[binaries]
c = '$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang'
cpp = '$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang++'
ar = '$LLVM_MINGW_ROOT/bin/llvm-ar'
strip = '$LLVM_MINGW_ROOT/bin/llvm-strip'
windres = '$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-windres'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = false

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

cat > "$BUILD_ROOT/cross-i686.txt" <<EOF
[binaries]
c = '$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang'
cpp = '$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang++'
ar = '$LLVM_MINGW_ROOT/bin/llvm-ar'
strip = '$LLVM_MINGW_ROOT/bin/llvm-strip'
windres = '$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-windres'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = false

[host_machine]
system = 'windows'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
EOF

meson setup "$BUILD_ROOT/build64" \
  --cross-file "$BUILD_ROOT/cross-x86_64.txt" \
  --buildtype release \
  --strip \
  -Db_ndebug=if-release

meson setup "$BUILD_ROOT/build32" \
  --cross-file "$BUILD_ROOT/cross-i686.txt" \
  --buildtype release \
  --strip \
  -Db_ndebug=if-release

ninja -C "$BUILD_ROOT/build64" -j "$JOBS"
ninja -C "$BUILD_ROOT/build32" -j "$JOBS"

commit_short="${DXVK_COMMIT:0:9}"
full_version="${DXVK_VERSION}-gplasync-${commit_short}"
wcp_name="Dxvk-${full_version}.wcp"

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/system32" "$PACKAGE_ROOT/syswow64" "$OUTPUT_DIR"

copy_dlls() {
  local src_build="$1"
  local dest="$2"
  local name
  for name in d3d8 d3d9 d3d10core d3d11 dxgi; do
    local found
    found="$(find "$src_build" -name "${name}.dll" -type f | head -n1)"
    test -n "$found" || {
      echo "missing ${name}.dll under $src_build" >&2
      exit 1
    }
    install -m 0644 "$found" "$dest/${name}.dll"
  done
}

copy_dlls "$BUILD_ROOT/build64" "$PACKAGE_ROOT/system32"
copy_dlls "$BUILD_ROOT/build32" "$PACKAGE_ROOT/syswow64"

cat > "$PACKAGE_ROOT/profile.json" <<EOF
{
  "type": "DXVK",
  "versionName": "$full_version",
  "versionCode": 0,
  "description": "Dxvk ${full_version}",
  "files": [
    {"source": "system32/d3d8.dll", "target": "\${system32}/d3d8.dll"},
    {"source": "system32/d3d9.dll", "target": "\${system32}/d3d9.dll"},
    {"source": "system32/d3d10core.dll", "target": "\${system32}/d3d10core.dll"},
    {"source": "system32/d3d11.dll", "target": "\${system32}/d3d11.dll"},
    {"source": "system32/dxgi.dll", "target": "\${system32}/dxgi.dll"},
    {"source": "syswow64/d3d8.dll", "target": "\${syswow64}/d3d8.dll"},
    {"source": "syswow64/d3d9.dll", "target": "\${syswow64}/d3d9.dll"},
    {"source": "syswow64/d3d10core.dll", "target": "\${syswow64}/d3d10core.dll"},
    {"source": "syswow64/d3d11.dll", "target": "\${syswow64}/d3d11.dll"},
    {"source": "syswow64/dxgi.dll", "target": "\${syswow64}/dxgi.dll"}
  ]
}
EOF

tar --owner=0 --group=0 --numeric-owner \
  --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
  -I 'xz -T1' -cf "$OUTPUT_DIR/$wcp_name" -C "$PACKAGE_ROOT" \
  profile.json system32 syswow64

(
  cd "$OUTPUT_DIR"
  sha256sum "$wcp_name" > "$wcp_name.sha256sum"
)
size="$(stat -c%s "$OUTPUT_DIR/$wcp_name")"
sha="$(awk '{print $1}' "$OUTPUT_DIR/$wcp_name.sha256sum")"

cat > "$OUTPUT_DIR/dxvk-wcp.env" <<EOF
FULL_VERSION=$full_version
COMMIT_FULL=$DXVK_COMMIT
COMMIT_SHORT=$commit_short
WCP_NAME=$wcp_name
SHA256=$sha
SIZE=$size
EOF
