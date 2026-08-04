#!/usr/bin/env bash
# =============================================================================
# Build Pipetto Mesa vulkan wrapper and pack wrapper-*.tzst (L1 leaf).
#
# Independent of imagefs.txz packaging — Amphora pins it via
# content_manifest.runtimeAssets[] (assetPath graphics_driver/wrapper.tzst).
#
# Sysroot: BuildStream stages the exact imagefs X11/drm/sysvshm artifacts at
# $STAGING_ROOT so compile-time headers and runtime SONAMEs stay identical.
# Do NOT mix Termux headers with foreign libs — that produced runtime
# VK_ERROR_INCOMPATIBLE_DRIVER (-9) in earlier experiments.
#
# Link / pack profile (must match a working Termux-style ICD):
#   - -D__TERMUX__ + patch 0003 → DETECT_OS_ANDROID off (no stub DT_NEEDED)
#   - never pack android-stub libcutils/liblog/libsync into usr/lib
#   - self-build libadrenotools + hooks from Mesa subproject (pinned revision;
#     keep C++ exceptions enabled in the cross file — -fno-exceptions produced
#     a broken hook vintage and guest adrenotools_open_libvulkan failures)
#
# Output (under $OUTPUT_DIR):
#   wrapper-<mesa_shortsha>.tzst
#   wrapper-<mesa_shortsha>.tzst.sha256sum
#   wrapper-tzst.env   # FULL_VERSION / TZST_NAME / SHA256 / SIZE / …
#
# Env:
#   WRAPPER_MESA_SRC / WRAPPER_MESA_COMMIT required (provided by BuildStream)
#   ADRENOTOOLS_REF  exact prestaged libadrenotools commit
#   ANDROID_NDK_HOME   required
#   WRAPPER_API        NDK API for mesa compile (default 30 — memfd_create)
#   STAGING_ROOT       target sysroot staged by BuildStream
#   OUTPUT_DIR         default $PWD/artifacts
#   JOBS
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

: "${WRAPPER_MESA_SRC:?BuildStream must provide WRAPPER_MESA_SRC}"
: "${WRAPPER_MESA_COMMIT:?BuildStream must provide WRAPPER_MESA_COMMIT}"
: "${ANDROID_NDK_HOME:?BuildStream must provide ANDROID_NDK_HOME}"
MESA_SRC="$WRAPPER_MESA_SRC"
WRAPPER_API="${WRAPPER_API:-30}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/artifacts}"
STAGING_ROOT="${STAGING_ROOT:-/opt/android-sysroot}"
JOBS="${JOBS:-$(nproc)}"
WORKDIR="${WORKDIR:-/tmp/wrapper-mesa}"
ADRENOTOOLS_REF="${ADRENOTOOLS_REF:-8483dfdaa2abf97ee89ad0e5f337e7b508550c6b}"

# Runtime RPATH matches imagefs packaging style; Amphora also sets LD_LIBRARY_PATH.
RPATH_USR="/usr/lib"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FAIL: missing $1" >&2
    exit 1
  }
}

check_deps() {
  local tools=(meson ninja cmake python3 pkg-config zstd patchelf flex bison)
  for b in "${tools[@]}"; do
    need "$b"
  done
  python3 -c 'import mako' 2>/dev/null || {
    echo "FAIL: python3-mako required" >&2
    exit 1
  }
}

validate_staging() {
  local staging="$STAGING_ROOT"
  [[ -d "$staging/usr/lib" ]] || {
    echo "FAIL: staging missing $staging/usr/lib" >&2
    exit 1
  }
  [[ -f "$staging/usr/include/xcb/present.h" ]] || {
    echo "FAIL: staging missing xcb/present.h" >&2
    exit 1
  }
  if ! grep -q 'xcb_present_pixmap_synced' "$staging/usr/include/xcb/present.h"; then
    echo "FAIL: staging xcb/present.h lacks xcb_present_pixmap_synced" >&2
    exit 1
  fi
  [[ -f "$staging/usr/lib/libandroid-sysvshm.so" ]] || {
    echo "FAIL: staging missing libandroid-sysvshm.so" >&2
    exit 1
  }
  if ! (nm -D --defined-only "$staging/usr/lib/libandroid-sysvshm.so" 2>/dev/null || true) \
    | grep -q ' libandroid_shmget$'; then
    if ! readelf -Ws "$staging/usr/lib/libandroid-sysvshm.so" 2>/dev/null \
      | awk '{print $8}' | grep -qx 'libandroid_shmget'; then
      echo "FAIL: libandroid-sysvshm.so missing libandroid_shmget (ICD would fail with -9)" >&2
      exit 1
    fi
  fi
  # Ensure unversioned linker names exist for pkg-config consumers.
  (
    cd "$staging/usr/lib"
    for f in libX11.so.* libX11-xcb.so.* libxcb.so.* libxcb-*.so.* libdrm.so.* \
             libz.so.* libzstd.so.* libxshmfence.so.* libexpat.so.*; do
      [[ -e "$f" ]] || continue
      base="${f%%.so.*}.so"
      [[ -e "$base" ]] || ln -sfn "$f" "$base"
    done
  )
  echo "Staging OK: $staging"
}

ensure_mesa() {
  [ -d "$MESA_SRC" ] || {
    echo "FAIL: prestaged Mesa missing: $MESA_SRC" >&2
    exit 1
  }
  cd "$MESA_SRC"
  COMMIT_FULL="$WRAPPER_MESA_COMMIT"
  COMMIT_SHORT="${COMMIT_FULL:0:9}"
  MESA_VERSION="$(tr -d '\n' <VERSION 2>/dev/null || echo unknown)"
  FULL_VERSION="${MESA_VERSION}-${COMMIT_SHORT}"
  TZST_NAME="wrapper-${COMMIT_SHORT}.tzst"
  echo "Prestaged Mesa $FULL_VERSION ($COMMIT_FULL)"
}

apply_patches() {
  cd "$MESA_SRC"
  local patch
  shopt -s nullglob
  for patch in "$REPO_ROOT"/vendor/wrapper-patches/*.patch; do
    patch -p1 --forward --batch <"$patch" || {
      echo "FAIL: patch did not apply cleanly: $patch" >&2
      exit 1
    }
    echo "Applied $patch"
  done
  shopt -u nullglob
  # Drop -Werror=gnu-empty-initializer from trial flag lists without deleting
  # the _trial_msvc = [...] assignment line (that used to break meson setup).
  python3 - <<'PY'
from pathlib import Path
p = Path("meson.build")
t = p.read_text()
t2 = t.replace("'-Werror=gnu-empty-initializer', ", "").replace(", '-Werror=gnu-empty-initializer'", "")
if t2 != t:
    p.write_text(t2)
    print("stripped -Werror=gnu-empty-initializer from meson.build trial lists")
PY
  [[ -d "$MESA_SRC/subprojects/libadrenotools" ]] || {
    echo "FAIL: prestaged libadrenotools source missing" >&2
    exit 1
  }
}

write_cross_files() {
  local staging="$STAGING_ROOT"
  local prefix="$staging/usr"
  local tc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
  local clang="$tc/bin/aarch64-linux-android${WRAPPER_API}-clang"
  local clangxx="$tc/bin/aarch64-linux-android${WRAPPER_API}-clang++"
  [[ -x "$clang" ]] || {
    echo "FAIL: missing $clang (WRAPPER_API=$WRAPPER_API)" >&2
    exit 1
  }

  mkdir -p "$WORKDIR" "$prefix/lib/pkgconfig"
  # Rewrite .pc prefix to staging so meson finds the right libs/headers.
  # xorgproto installs to share/pkgconfig (xproto.pc); xcb Requires xau→xproto.
  mkdir -p "$WORKDIR/pkgconfig"
  local pc base
  for pc in "$prefix/lib/pkgconfig/"*.pc "$prefix/share/pkgconfig/"*.pc; do
    [[ -f "$pc" ]] || continue
    base="$(basename "$pc")"
    case "$base" in
      x11.pc|x11-xcb.pc|xcb*.pc|xshmfence.pc|libdrm.pc|xext.pc|xfixes.pc|zlib.pc|libzstd.pc|expat.pc|xorg-macros.pc|xau.pc|xdmcp.pc|xproto.pc|xtrans.pc|*proto.pc) ;;
      *) continue ;;
    esac
    sed -e "s|^prefix=.*|prefix=$prefix|" \
        -e "s|^includedir=.*|includedir=$prefix/include|" \
        -e "s|^libdir=.*|libdir=$prefix/lib|" \
        "$pc" >"$WORKDIR/pkgconfig/$base"
  done
  [[ -f "$WORKDIR/pkgconfig/xproto.pc" ]] || {
    echo "FAIL: staging missing xproto.pc (xorgproto share/pkgconfig)" >&2
    exit 1
  }

  cat >"$WORKDIR/android-aarch64.txt" <<EOF
[binaries]
ar = '$tc/bin/llvm-ar'
c = '$clang'
# Keep exceptions for C++ subprojects (libadrenotools); mesa C++ files are fine with them.
cpp = '$clangxx'
c_ld = '$tc/bin/ld.lld'
cpp_ld = '$tc/bin/ld.lld'
strip = '$tc/bin/llvm-strip'
pkg-config = 'pkg-config'

[built-in options]
# __TERMUX__ unlocks Pipetto AHardwareBuffer / X11 WSI fields and (with patch
# 0003) keeps DETECT_OS_ANDROID off so we do not DT_NEEDED android-stub libs.
c_args = ['-I$prefix/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__']
cpp_args = ['-I$prefix/include', '-Wno-error', '-D__USE_GNU', '-D__TERMUX__']
c_link_args = ['-L$prefix/lib', '-landroid-sysvshm', '-lc++_shared', '-Wl,-rpath,$RPATH_USR', '-Wl,--as-needed']
cpp_link_args = ['-L$prefix/lib', '-landroid-sysvshm', '-lc++_shared', '-Wl,-rpath,$RPATH_USR', '-Wl,--as-needed']

[host_machine]
# Termux-style: NDK clang triple is still aarch64-linux-android*, but meson
# host system is linux (platforms=x11, not android).
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
# Include staging share/pkgconfig for xproto.pc (do not rely on host /usr/share).
pkg_config_libdir = '$WORKDIR/pkgconfig:$prefix/lib/pkgconfig:$prefix/share/pkgconfig'
needs_exe_wrapper = true
EOF

  cat >"$WORKDIR/native.txt" <<EOF
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
}

configure_and_build() {
  local staging="$STAGING_ROOT"
  local prefix="$staging/usr"
  local builddir="$WORKDIR/build"
  rm -rf "$builddir"
  mkdir -p "$builddir"

  export PKG_CONFIG_LIBDIR="$WORKDIR/pkgconfig:$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
  unset PKG_CONFIG_PATH || true

  cd "$MESA_SRC"
  echo "meson setup..."
  meson setup "$builddir" \
    --cross-file "$WORKDIR/android-aarch64.txt" \
    --native-file "$WORKDIR/native.txt" \
    --prefix /usr \
    --libdir lib \
    -Dbuildtype=release \
    -Db_ndebug=true \
    -Dstrip=true \
    -Dplatforms=x11 \
    -Dgallium-drivers= \
    -Dvulkan-drivers=wrapper \
    -Dopengl=false \
    -Degl=disabled \
    -Dgbm=disabled \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dxmlconfig=disabled \
    -Dcpp_rtti=false \
    -Dandroid-stub=true \
    -Dandroid-libbacktrace=disabled \
    -Dvideo-codecs= \
    -Dglvnd=disabled \
    -Dzstd=enabled \
    -Dexpat=disabled \
    -Dxlib-lease=disabled \
    || {
      tail -160 "$builddir/meson-logs/meson-log.txt" || true
      exit 1
    }

  echo "ninja compile..."
  meson compile -C "$builddir" -j"$JOBS"
  local so="$builddir/src/vulkan/wrapper/libvulkan_wrapper.so"
  [[ -f "$so" ]] || {
    echo "FAIL: libvulkan_wrapper.so not produced" >&2
    exit 1
  }
  echo "built: $so ($(du -h "$so" | awk '{print $1}'))"
}

normalize_needed() {
  # Amphora imagefs ships unversioned X11/xcb SONAMEs (libxcb.so, not .so.1).
  local so="$1"
  local needed name unversioned
  mapfile -t needed < <(readelf -d "$so" 2>/dev/null | awk -F'[][]' '/NEEDED/{print $2}')
  for name in "${needed[@]}"; do
    case "$name" in
      libxcb.so.*|libX11.so.*|libX11-xcb.so.*|libxcb-*.so.*)
        unversioned="${name%%.so.*}.so"
        if [ "$name" != "$unversioned" ]; then
          echo "patchelf --replace-needed $name -> $unversioned"
          patchelf --replace-needed "$name" "$unversioned" "$so"
        fi
        ;;
    esac
  done
}

pack_tzst() {
  local tc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
  local builddir="$WORKDIR/build"
  local stage="$WORKDIR/tzst-stage"
  local so="$builddir/src/vulkan/wrapper/libvulkan_wrapper.so"
  local icd
  icd="$(find "$builddir" -name 'wrapper_icd.*.json' | head -1)"
  [[ -n "$icd" ]] || {
    echo "FAIL: wrapper ICD json missing" >&2
    exit 1
  }

  rm -rf "$stage"
  mkdir -p "$stage/usr/lib" "$stage/usr/share/vulkan/icd.d"

  "$tc/bin/llvm-strip" --strip-unneeded "$so" -o "$stage/usr/lib/libvulkan_wrapper.so"
  normalize_needed "$stage/usr/lib/libvulkan_wrapper.so"
  patchelf --set-rpath "$RPATH_USR" "$stage/usr/lib/libvulkan_wrapper.so"

  # Drop android-stub DT_NEEDED if the linker still recorded them. Official /
  # Termux ICDs never ship stub libcutils/liblog/libsync in imagefs — those
  # names must resolve from /system (or not appear at all).
  local stub
  for stub in libcutils.so liblog.so libsync.so libhardware.so; do
    if readelf -d "$stage/usr/lib/libvulkan_wrapper.so" | awk -F'[][]' '/NEEDED/{print $2}' | grep -qx "$stub"; then
      echo "patchelf --remove-needed $stub (android-stub must not ship in imagefs)"
      patchelf --remove-needed "$stub" "$stage/usr/lib/libvulkan_wrapper.so"
    fi
  done
  # libnativewindow.so is real on /system; keep NEEDED, do not pack a stub.

# Self-built adrenotools (+ hooks) from the prestaged Mesa subproject.
  # each other. Guest ADRENOTOOLS_HOOKS_PATH is imagefs usr/lib.
  local adreno="$builddir/subprojects/libadrenotools/libadrenotools.so"
  [[ -f "$adreno" ]] || {
    echo "FAIL: libadrenotools.so missing from subproject build" >&2
    exit 1
  }
  "$tc/bin/llvm-strip" --strip-unneeded "$adreno" -o "$stage/usr/lib/libadrenotools.so"
  patchelf --set-rpath "$RPATH_USR" "$stage/usr/lib/libadrenotools.so" 2>/dev/null || true
  local h f
  for h in main_hook file_redirect_hook gsl_alloc_hook hook_impl; do
    f="$(find "$builddir/subprojects/libadrenotools" -name "lib${h}.so" 2>/dev/null | head -1 || true)"
    [[ -n "$f" && -f "$f" ]] || {
      echo "FAIL: missing self-built hook lib${h}.so" >&2
      exit 1
    }
    "$tc/bin/llvm-strip" --strip-unneeded "$f" -o "$stage/usr/lib/lib${h}.so"
    patchelf --set-rpath "$RPATH_USR" "$stage/usr/lib/lib${h}.so" 2>/dev/null || true
  done

  python3 - <<PY
import json
d = json.load(open("$icd"))
d.setdefault("ICD", {})["library_path"] = "libvulkan_wrapper.so"
json.dump(d, open("$stage/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json", "w"), indent=4)
print("ICD api:", d.get("ICD", {}).get("api_version"))
PY

  local needed
  needed="$(readelf -d "$stage/usr/lib/libvulkan_wrapper.so" | awk -F'[][]' '/NEEDED/{print $2}')"
  # Sanity: unversioned xcb + expected leaf deps; no android stubs.
  echo "NEEDED: $needed"
  echo "$needed" | grep -qx 'libandroid-sysvshm.so' || {
    echo "FAIL: expected NEEDED libandroid-sysvshm.so" >&2
    exit 1
  }
  echo "$needed" | grep -qx 'libxcb.so' || {
    echo "FAIL: expected NEEDED libxcb.so (unversioned; Amphora imagefs has no libxcb.so.1)" >&2
    exit 1
  }
  echo "$needed" | grep -E -qx 'libxcb\.so\.[0-9]+' && {
    echo "FAIL: versioned libxcb still in NEEDED" >&2
    exit 1
  }
  echo "$needed" | grep -qx 'libadrenotools.so' || {
    echo "FAIL: expected NEEDED libadrenotools.so" >&2
    exit 1
  }
  for stub in libcutils.so liblog.so libsync.so libhardware.so; do
    echo "$needed" | grep -qx "$stub" && {
      echo "FAIL: android-stub $stub still in NEEDED (would shadow /system in imagefs)" >&2
      exit 1
    }
  done
  # Refuse to pack stub .so files into usr/lib.
  for stub in libcutils.so liblog.so libsync.so libhardware.so; do
    [[ -e "$stage/usr/lib/$stub" ]] && {
      echo "FAIL: refusing to pack android-stub $stub into tzst" >&2
      exit 1
    }
  done

  mkdir -p "$OUTPUT_DIR"
  local out="$OUTPUT_DIR/$TZST_NAME"
  rm -f "$out"
  # Reproducible-ish: clamp mtime.
  tar --owner=0 --group=0 --numeric-owner \
    --mtime="@${SOURCE_DATE_EPOCH:-0}" --clamp-mtime --sort=name \
    -C "$stage" -cf - usr | zstd -T0 -19 -o "$out"
  (
    cd "$OUTPUT_DIR"
    sha256sum "$TZST_NAME" | tee "${TZST_NAME}.sha256sum"
  )
  SHA256="$(awk '{print $1}' "$OUTPUT_DIR/${TZST_NAME}.sha256sum")"
  SIZE="$(stat -c%s "$OUTPUT_DIR/$TZST_NAME")"

  cat >"$OUTPUT_DIR/wrapper-tzst.env" <<EOF
FULL_VERSION=${FULL_VERSION}
COMMIT_FULL=${COMMIT_FULL}
COMMIT_SHORT=${COMMIT_SHORT}
ADRENOTOOLS_REF=${ADRENOTOOLS_REF}
TZST_NAME=${TZST_NAME}
SHA256=${SHA256}
SIZE=${SIZE}
EOF

  echo "Wrote $out ($SIZE bytes, sha256=$SHA256)"
  tar -I zstd -tf "$out"
}

main() {
  local clang="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${WRAPPER_API}-clang"
  [[ -x "$clang" ]] || {
    echo "FAIL: BuildStream NDK compiler missing: $clang" >&2
    exit 1
  }
  check_deps
  mkdir -p "$WORKDIR" "$OUTPUT_DIR"
  validate_staging
  ensure_mesa
  apply_patches
  write_cross_files
  configure_and_build
  pack_tzst
  echo "done"
}

main "$@"
