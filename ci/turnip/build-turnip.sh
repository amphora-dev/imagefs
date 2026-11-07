#!/usr/bin/env bash
# Build Mesa Turnip (freedreno Vulkan, KGSL only) for Android aarch64 inside
# a BuildStream sandbox and pack the adrenotools driver package turnip-*.zip.
#
# Amphora installs the zip with AdrenotoolsManager.installFromZip into
# contents/adrenotools/turnip/; the guest wrapper ICD loads
# libvulkan_freedreno.so from there through adrenotools.
#
# Profile: a real Android build (meson host system 'android',
# -Dplatforms=android, -Dandroid-stub=true, API 30 NDK clang, libc++ linked
# statically). This is not toolchains' meson-mesa-api30.ini, which is the
# Bionic/Linux profile for imagefs userland (system 'linux', -D__AMPHORA__,
# -lc++_shared, rpath /usr/lib): adrenotools loads the driver in a linker
# namespace that only sees /system libraries and the driver dir.
#
# Every meson flag lives in this script and every source change is a file in
# vendor/turnip-patches, so sha256(this script + the patches) is the asset
# identity: turnip-<MESA_VERSION>-s<sha8>.zip (ci/gate/turnip-build.sh
# computes the same name).
#
# Output (under $OUTPUT_DIR):
#   turnip-<FULL_VERSION>.zip            libvulkan_freedreno.so, meta.json, LICENSE-mesa.rst
#   turnip-<FULL_VERSION>.zip.sha256sum
#   turnip.env                           FULL_VERSION / ZIP_NAME / SHA256 / SIZE / …
set -euo pipefail

export LC_ALL=C
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

: "${ANDROID_NDK_HOME:?BuildStream must provide ANDROID_NDK_HOME}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${MESA_VERSION:?BuildStream must provide MESA_VERSION}"
: "${MESA_TARBALL_SHA256:?BuildStream must provide MESA_TARBALL_SHA256}"

API=30
JOBS="${JOBS:-$(nproc)}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/turnip-build}"
STAGE="$BUILD_ROOT/stage"
SRC_DIR="$PWD"
SCRIPT="$(readlink -f "$0")"
PATCH_DIR="$(dirname "$SCRIPT")/../../turnip-patches"
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"

for tool in meson ninja python3 sha256sum flex bison; do
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
  "$TC/aarch64-linux-android${API}-clang" \
  "$TC/aarch64-linux-android${API}-clang++" \
  "$TC/llvm-ar" \
  "$TC/llvm-strip" \
  "$TC/llvm-readelf" \
  "$TC/ld.lld"; do
  test -x "$tool" || {
    echo "missing NDK tool: $tool" >&2
    exit 1
  }
done

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/bin" "$BUILD_ROOT/empty-pkgconfig" "$STAGE" "$OUTPUT_DIR"

# freedreno Vulkan builds BVH shaders, so meson needs glslangValidator >= 12.2.
# The glslang release may ship it only as `glslang` (same binary, new name).
if ! command -v glslangValidator >/dev/null; then
  glslang_bin="$(command -v glslang)" || {
    echo "missing glslangValidator (and glslang) on PATH" >&2
    exit 1
  }
  ln -s "$glslang_bin" "$BUILD_ROOT/bin/glslangValidator"
  export PATH="$BUILD_ROOT/bin:$PATH"
fi
glslangValidator --version | head -n 3

test -f "$SRC_DIR/VERSION" || {
  echo "no Mesa source tree in $SRC_DIR (VERSION missing)" >&2
  exit 1
}
src_version="$(tr -d '\n' < "$SRC_DIR/VERSION")"
test "$src_version" = "$MESA_VERSION" || {
  echo "Mesa source is $src_version, element says MESA_VERSION=$MESA_VERSION" >&2
  exit 1
}

patches=("$PATCH_DIR"/*.patch)
test -f "${patches[0]}" || {
  echo "no patches in $PATCH_DIR" >&2
  exit 1
}

IDENTITY_SHA8="$(cat "$SCRIPT" "${patches[@]}" | sha256sum | cut -c1-8)"
FULL_VERSION="${MESA_VERSION}-s${IDENTITY_SHA8}"
ZIP_NAME="turnip-${FULL_VERSION}.zip"
echo "Turnip $FULL_VERSION -> $ZIP_NAME"

for p in "${patches[@]}"; do
  patch -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch < "$p" || {
    echo "patch did not apply: $(basename "$p")" >&2
    exit 1
  }
  echo "applied $(basename "$p")"
done

KGSL="$SRC_DIR/src/freedreno/vulkan/tu_knl_kgsl.cc"
GRALLOC="$SRC_DIR/src/util/u_gralloc/u_gralloc_fallback.c"
grep -qF 'kgsl_poll_timestamp' "$KGSL" || {
  echo "0003-tu-kgsl-Prevent-indefinite-wait-times-for-0-timeout: kgsl_poll_timestamp missing in $KGSL" >&2
  exit 1
}
grep -qF 'ret.state == KGSL_SYNCOBJ_STATE_TS && sync->state == KGSL_SYNCOBJ_STATE_TS' "$KGSL" || {
  echo "0010-tu-kgsl-Correctly-merge-timestamps-and-sync-files: TS+TS merge check missing in $KGSL" >&2
  exit 1
}
if grep -qF 'data[hnd->handle->numFds] == gmsm' "$GRALLOC"; then
  echo "0012-u_gralloc-fallback-detect-qcom-ubwc-without-gmsm: gmsm check still in $GRALLOC" >&2
  exit 1
fi
grep -qF 'numInts >= 2' "$GRALLOC" || {
  echo "0012-u_gralloc-fallback-detect-qcom-ubwc-without-gmsm: numInts >= 2 missing in $GRALLOC" >&2
  exit 1
}

# No host or imagefs .pc file may satisfy an Android dependency.
export PKG_CONFIG_LIBDIR="$BUILD_ROOT/empty-pkgconfig"
unset PKG_CONFIG_PATH

cat > "$BUILD_ROOT/cross-android-aarch64.txt" <<EOF
[binaries]
c = '$TC/aarch64-linux-android${API}-clang'
cpp = '$TC/aarch64-linux-android${API}-clang++'
ar = '$TC/llvm-ar'
strip = '$TC/llvm-strip'
c_ld = '$TC/ld.lld'
cpp_ld = '$TC/ld.lld'
pkg-config = 'pkg-config'

[built-in options]
# The driver dir has no libc++_shared.so and adrenotools' namespace cannot
# reach the app's copy.
cpp_link_args = ['-static-libstdc++']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat > "$BUILD_ROOT/native.txt" <<EOF
[binaries]
c = '/usr/bin/gcc'
cpp = '/usr/bin/g++'
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# kgsl only + freedreno only: meson drops libdrm (system_has_kms_drm=false).
# zlib stays at its default: the NDK libz.so is a public /system library.
MESON_FLAGS=(
  --buildtype=release
  --wrap-mode=nodownload
  -Db_ndebug=true
  -Dstrip=true
  -Dplatforms=android
  -Dandroid-stub=true
  -Dplatform-sdk-version=30
  # android-strict (default on) hides every VK_KHR_* extension Android CTS
  # allow-lists only above platform-sdk-version (vk_extensions.py
  # ALLOWED_ANDROID_VERSION): at 30 that drops load_store_op_none (DXVK 3.0.2
  # needs it), maintenance5/6, robustness2, dynamic_rendering, ... This driver
  # is loaded by adrenotools, not the system Vulkan HAL, so CTS rules do not
  # apply: expose what Turnip supports.
  -Dandroid-strict=false
  -Dandroid-libbacktrace=disabled
  -Dvulkan-drivers=freedreno
  -Dfreedreno-kmds=kgsl
  -Dgallium-drivers=
  -Dopengl=false
  -Degl=disabled
  -Dgles1=disabled
  -Dgles2=disabled
  -Dglx=disabled
  -Dgbm=disabled
  -Dllvm=disabled
  -Dshared-llvm=disabled
  -Dxmlconfig=disabled
  -Dzstd=disabled
  -Dvalgrind=disabled
  -Dlibunwind=disabled
  -Dlmsensors=disabled
  -Dperfetto=false
  -Dvideo-codecs=
  -Dbuild-tests=false
)

BUILD_DIR="$BUILD_ROOT/build"
DESTDIR_ROOT="$BUILD_ROOT/install"
meson setup "$BUILD_DIR" "$SRC_DIR" \
  --cross-file "$BUILD_ROOT/cross-android-aarch64.txt" \
  --native-file "$BUILD_ROOT/native.txt" \
  --prefix=/usr \
  --libdir=lib \
  "${MESON_FLAGS[@]}" || {
  tail -150 "$BUILD_DIR/meson-logs/meson-log.txt" >&2 || true
  exit 1
}
ninja -C "$BUILD_DIR" -j "$JOBS"
# Install, not the build-tree file: meson drops the build RUNPATH
# ($ORIGIN/../../android_stub) on install.
meson install -C "$BUILD_DIR" --destdir "$DESTDIR_ROOT" --no-rebuild

so="$DESTDIR_ROOT/usr/lib/libvulkan_freedreno.so"
test -f "$so" || {
  echo "libvulkan_freedreno.so not installed at $so" >&2
  exit 1
}

"$TC/llvm-strip" --strip-unneeded -o "$STAGE/libvulkan_freedreno.so" "$so"
cp "$SRC_DIR/docs/license.rst" "$STAGE/LICENSE-mesa.rst"
chmod 0644 "$STAGE/libvulkan_freedreno.so" "$STAGE/LICENSE-mesa.rst"

MESA_VERSION="$MESA_VERSION" FULL_VERSION="$FULL_VERSION" python3 - "$STAGE/meta.json" <<'PY'
import json
import os
import sys

v = os.environ["MESA_VERSION"]
meta = {
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
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PY

# Deterministic zip (the host SDK has no `zip`): fixed entry order, date,
# mode and compression.
python3 - "$STAGE" "$OUTPUT_DIR/$ZIP_NAME" <<'PY'
import sys
import zipfile

stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w") as z:
    for name in ("libvulkan_freedreno.so", "meta.json", "LICENSE-mesa.rst"):
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        with open(f"{stage}/{name}", "rb") as f:
            z.writestr(info, f.read(), compresslevel=9)
PY

(
  cd "$OUTPUT_DIR"
  sha256sum "$ZIP_NAME" > "$ZIP_NAME.sha256sum"
)
size="$(stat -c%s "$OUTPUT_DIR/$ZIP_NAME")"
sha="$(awk '{print $1}' "$OUTPUT_DIR/$ZIP_NAME.sha256sum")"

cat > "$OUTPUT_DIR/turnip.env" <<EOF
FULL_VERSION=$FULL_VERSION
MESA_VERSION=$MESA_VERSION
MESA_TARBALL_SHA256=$MESA_TARBALL_SHA256
IDENTITY_SHA8=$IDENTITY_SHA8
ZIP_NAME=$ZIP_NAME
SHA256=$sha
SIZE=$size
EOF

"$TC/llvm-readelf" -d "$STAGE/libvulkan_freedreno.so"
# Android platform build: the only export is the hwvulkan module HMI.
"$TC/llvm-readelf" --dyn-syms -W "$STAGE/libvulkan_freedreno.so" |
  grep -E ' HMI$' || echo "HMI not exported (ci/verify/turnip.sh fails on this)"
ls -l "$STAGE"
cat "$OUTPUT_DIR/turnip.env"
