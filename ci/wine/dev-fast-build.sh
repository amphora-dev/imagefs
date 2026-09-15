#!/usr/bin/env bash
# BuildStream-aligned fast Proton Wine development loop.
#
# Same configure/env/packaging as CI (ci/wine/proton-wcp-env.sh +
# build-proton-wcp.sh). Persistent out-of-tree build; incremental make;
# emits a drop-in Proton-*.wcp (Amphora-installable) when a full package
# tree is available (local full install or BASE_WCP merge).
#
# Official release pins still go through CI `build-proton-wine` /
# l1/proton-wine-wcp.bst. This script is for day-to-day speed only.
#
# Usage:
#   source /home/box/src/bst-artifacts/dev-env.sh   # after bootstrap
#   bash ci/wine/dev-fast-build.sh                 # incremental + repack WCP
#   MODE=full bash ci/wine/dev-fast-build.sh       # first full make+install+WCP
#   MODE=configure bash ci/wine/dev-fast-build.sh  # (re)configure only
#   TARGETS='dlls/ntdll/all' bash ci/wine/dev-fast-build.sh
#   BASE_WCP=/path/to/Proton-....wcp bash ci/wine/dev-fast-build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGEFS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROTON_SRC="${PROTON_SRC:-/home/box/src/amphora-dev/proton-wine}"
BUILD_DIR="${BUILD_DIR:-/home/box/src/wine-bst-dev-build}"
WINE_TOOLS_DIR="${WINE_TOOLS_DIR:-/home/box/src/wine-bst-dev-wine-tools}"
OUT_DIR="${OUT_DIR:-/workspace/fast-wineandroid-bst}"
PACKAGE_ROOT="${PACKAGE_ROOT:-$BUILD_DIR/.wcp-package}"
DESTDIR_ROOT="${DESTDIR_ROOT:-$BUILD_DIR/.destdir}"
MODE="${MODE:-incremental}"   # incremental | full | configure | pack
TARGETS="${TARGETS:-dlls/wineandroid.drv/all}"
JOBS="${JOBS:-$(nproc)}"

ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/home/box/src/toolchains/android-ndk-r29}"
LLVM_MINGW_ROOT="${LLVM_MINGW_ROOT:-/home/box/src/toolchains/llvm-mingw-20250920-ucrt-ubuntu-22.04-x86_64}"
HOST_FREETYPE="${HOST_FREETYPE:-/home/box/src/bst-artifacts/host-freetype}"
# Prefer bootstrap-written paths; fall back to common bst checkout.
ANDROID_X86_64_SYSROOT="${ANDROID_X86_64_SYSROOT:-/home/box/src/bst-artifacts/android-x86_64-sysroot}"
PULSE_DEV_DEB="${PULSE_DEV_DEB:-/home/box/src/bst-artifacts/pulseaudio_13.0-1_x86_64.deb}"
PREFIX_PACK="${PREFIX_PACK:-/home/box/src/bst-artifacts/prefixPack-11.0-d12a5634a-x86_64-1.txz}"

usage() {
  cat <<'USAGE'
BuildStream-aligned Proton Wine fast path (drop-in WCP capable)

Bootstrap (once):
  bash ci/wine/dev-bootstrap-sysroot.sh
  source /home/box/src/bst-artifacts/dev-env.sh

First full local WCP (slow; matches CI layout):
  MODE=full bash ci/wine/dev-fast-build.sh

Daily incremental (default TARGETS=dlls/wineandroid.drv/all):
  bash ci/wine/dev-fast-build.sh
  TARGETS='dlls/wineandroid.drv/all dlls/win32u/all' bash ci/wine/dev-fast-build.sh

If you have a CI Proton-*.wcp but no local full install yet:
  BASE_WCP=/path/to/Proton-....wcp bash ci/wine/dev-fast-build.sh
  # rebuilds TARGETS, overlays into unpacked WCP at identical paths, repacks

Pack only (repack existing package tree):
  MODE=pack bash ci/wine/dev-fast-build.sh

Official release pins: CI build-proton-wine / l1/proton-wine-wcp.bst
Do NOT use proton-wine/scripts/fast-wineandroid-build.sh (NDK-only, diverges).
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

export ANDROID_NDK_HOME LLVM_MINGW_ROOT ANDROID_X86_64_SYSROOT PULSE_DEV_DEB
export HOST_FREETYPE PREFIX_PACK JOBS
export WINE_PREFIX="${WINE_PREFIX:-/opt/wine}"

if [ ! -d "$ANDROID_X86_64_SYSROOT/usr/lib" ]; then
  cat >&2 <<ERR
ERROR: ANDROID_X86_64_SYSROOT is not ready: $ANDROID_X86_64_SYSROOT

Run bootstrap first (may take many hours for sysroot):
  bash $SCRIPT_DIR/dev-bootstrap-sysroot.sh
  # then: source /home/box/src/bst-artifacts/dev-env.sh

Do not fall back to /home/box/src/wine-android-build — that tree was
configured WITHOUT pulse/vulkan/fontconfig/gstreamer/sysroot and diverges from CI.
ERR
  exit 1
fi

# shellcheck source=proton-wcp-env.sh
source "$SCRIPT_DIR/proton-wcp-env.sh"

test -d "$PROTON_SRC" || { echo "missing PROTON_SRC=$PROTON_SRC" >&2; exit 1; }
test -f "$PROTON_SRC/VERSION" || { echo "missing $PROTON_SRC/VERSION" >&2; exit 1; }

PROTON_COMMIT="${PROTON_COMMIT:-$(git -C "$PROTON_SRC" rev-parse HEAD)}"
export PROTON_COMMIT

proton_wcp_require_tools 0
proton_wcp_prepare_pulse

mkdir -p "$BUILD_DIR" "$OUT_DIR" "$(dirname "$WINE_TOOLS_DIR")"

STAMP_FILE="$BUILD_DIR/.proton-wcp-configure.stamp"
EXPECTED_STAMP="$(proton_wcp_configure_stamp "$WINE_TOOLS_DIR")"
NEED_CONFIGURE=0
if [ ! -f "$BUILD_DIR/Makefile" ] || [ ! -f "$STAMP_FILE" ]; then
  NEED_CONFIGURE=1
elif [ "$(cat "$STAMP_FILE")" != "$EXPECTED_STAMP" ]; then
  echo "configure stamp mismatch — will reconfigure"
  NEED_CONFIGURE=1
fi
if [ "$MODE" = "configure" ] || [ "$MODE" = "full" ]; then
  NEED_CONFIGURE=1
fi

run_configure() {
  echo "==> configure (CI-identical flags) PROTON_COMMIT=$PROTON_COMMIT"
  if [ ! -f "$PROTON_SRC/configure" ]; then
    (cd "$PROTON_SRC" && ./autogen.sh)
  fi

  if [ ! -f "$WINE_TOOLS_DIR/Makefile" ] || [ "$NEED_CONFIGURE" = 1 ]; then
    echo "==> wine-tools host build at $WINE_TOOLS_DIR"
    rm -rf "$WINE_TOOLS_DIR"
    mkdir -p "$WINE_TOOLS_DIR"
    (
      cd "$WINE_TOOLS_DIR"
      proton_wcp_export_wine_tools_env
      # shellcheck disable=SC2046
      "$PROTON_SRC/configure" $(proton_wcp_wine_tools_configure_args)
      make -j"$JOBS" __tooldeps__ nls/all
    )
  fi

  # Out-of-tree: wipe build dir contents carefully but keep sibling state.
  # Re-run configure in BUILD_DIR.
  find "$BUILD_DIR" -mindepth 1 -maxdepth 1 ! -name '.wcp-package' ! -name '.destdir' \
    ! -name '.proton-wcp-configure.stamp' -exec rm -rf {} +
  mkdir -p "$BUILD_DIR"
  (
    cd "$BUILD_DIR"
    proton_wcp_export_cross_env
    # shellcheck disable=SC2046
    "$PROTON_SRC/configure" $(proton_wcp_cross_configure_args "$WINE_TOOLS_DIR")
  )
  echo "$EXPECTED_STAMP" > "$STAMP_FILE"
  echo "==> configure done; stamp=$EXPECTED_STAMP"
}

ensure_package_base() {
  # Prefer existing local package tree from a prior MODE=full.
  if [ -f "$PACKAGE_ROOT/lib/wine/x86_64-unix/wine" ] && \
     [ -f "$PACKAGE_ROOT/prefixPack.txz" ]; then
    return 0
  fi
  # Else merge from BASE_WCP / BASE_WCP_TREE.
  if [ -n "${BASE_WCP_TREE:-}" ]; then
    echo "==> seeding package tree from BASE_WCP_TREE=$BASE_WCP_TREE"
    rm -rf "$PACKAGE_ROOT"
    mkdir -p "$PACKAGE_ROOT"
    cp -a "$BASE_WCP_TREE"/. "$PACKAGE_ROOT/"
    return 0
  fi
  if [ -n "${BASE_WCP:-}" ]; then
    echo "==> seeding package tree from BASE_WCP=$BASE_WCP"
    rm -rf "$PACKAGE_ROOT"
    mkdir -p "$PACKAGE_ROOT"
    tar -I zstd -xf "$BASE_WCP" -C "$PACKAGE_ROOT"
    return 0
  fi
  return 1
}

overlay_build_artifacts_into_package() {
  # Map well-known build outputs → CI WCP paths (identical layout).
  # Never runs full `make install` here — that is MODE=full only.
  local so drv64 drv32
  so="$BUILD_DIR/dlls/wineandroid.drv/wineandroid.so"
  drv64="$BUILD_DIR/dlls/wineandroid.drv/x86_64-windows/wineandroid.drv"
  drv32="$BUILD_DIR/dlls/wineandroid.drv/i386-windows/wineandroid.drv"
  if [ -f "$so" ]; then
    install -D -m 0755 "$so" "$PACKAGE_ROOT/lib/wine/x86_64-unix/wineandroid.so"
    echo "  overlay lib/wine/x86_64-unix/wineandroid.so"
  fi
  if [ -f "$drv64" ]; then
    install -D -m 0644 "$drv64" "$PACKAGE_ROOT/lib/wine/x86_64-windows/wineandroid.drv"
    echo "  overlay lib/wine/x86_64-windows/wineandroid.drv"
  fi
  if [ -f "$drv32" ]; then
    install -D -m 0644 "$drv32" "$PACKAGE_ROOT/lib/wine/i386-windows/wineandroid.drv"
    echo "  overlay lib/wine/i386-windows/wineandroid.drv"
  fi

  # Best-effort overlays for other common dll TARGETS (unix .so + PE).
  # Example TARGETS='dlls/win32u/all' → dlls/win32u/win32u.so etc.
  local t base name
  for t in $TARGETS; do
    case "$t" in
      dlls/*/all|dlls/*)
        base="${t%/all}"
        name="$(basename "$base")"
        [ "$name" = "wineandroid.drv" ] && continue
        if [ -f "$BUILD_DIR/$base/${name}.so" ]; then
          install -D -m 0755 "$BUILD_DIR/$base/${name}.so" \
            "$PACKAGE_ROOT/lib/wine/x86_64-unix/${name}.so"
          echo "  overlay lib/wine/x86_64-unix/${name}.so"
        fi
        if [ -f "$BUILD_DIR/$base/x86_64-windows/${name}.dll" ]; then
          install -D -m 0644 "$BUILD_DIR/$base/x86_64-windows/${name}.dll" \
            "$PACKAGE_ROOT/lib/wine/x86_64-windows/${name}.dll"
          echo "  overlay lib/wine/x86_64-windows/${name}.dll"
        fi
        if [ -f "$BUILD_DIR/$base/x86_64-windows/${name}.drv" ]; then
          install -D -m 0644 "$BUILD_DIR/$base/x86_64-windows/${name}.drv" \
            "$PACKAGE_ROOT/lib/wine/x86_64-windows/${name}.drv"
          echo "  overlay lib/wine/x86_64-windows/${name}.drv"
        fi
        if [ -f "$BUILD_DIR/$base/i386-windows/${name}.dll" ]; then
          install -D -m 0644 "$BUILD_DIR/$base/i386-windows/${name}.dll" \
            "$PACKAGE_ROOT/lib/wine/i386-windows/${name}.dll"
          echo "  overlay lib/wine/i386-windows/${name}.dll"
        fi
        if [ -f "$BUILD_DIR/$base/i386-windows/${name}.drv" ]; then
          install -D -m 0644 "$BUILD_DIR/$base/i386-windows/${name}.drv" \
            "$PACKAGE_ROOT/lib/wine/i386-windows/${name}.drv"
          echo "  overlay lib/wine/i386-windows/${name}.drv"
        fi
        ;;
    esac
  done
}

pack_dropin_wcp() {
  : "${PREFIX_PACK:?PREFIX_PACK required to pack WCP}"
  test -f "$PREFIX_PACK"
  if [ ! -f "$PACKAGE_ROOT/prefixPack.txz" ]; then
    cp "$PREFIX_PACK" "$PACKAGE_ROOT/prefixPack.txz"
  fi
  # Ensure wine symlinks match CI verify.
  ln -sfn ../lib/wine/x86_64-unix/wine "$PACKAGE_ROOT/bin/wine"
  ln -sfn ../lib/wine/x86_64-unix/wine-preloader "$PACKAGE_ROOT/bin/wine-preloader"

  proton_wcp_export_cross_env
  # Strip only overlaid binaries would be ideal; CI strips everything — do same.
  proton_wcp_strip_package "$PACKAGE_ROOT"
  proton_wcp_write_profile_and_pack "$PACKAGE_ROOT" "$OUT_DIR" "$PROTON_COMMIT" "$PROTON_SRC/VERSION"

  # Also stage individual SHA notes for quick smoke / adb push experiments.
  {
    echo "bst-aligned incremental / drop-in WCP path"
    echo "NOT a substitute for CI release pins (build-proton-wine)."
    echo "PROTON_SRC=$PROTON_SRC"
    echo "PROTON_COMMIT=$PROTON_COMMIT"
    echo "BUILD_DIR=$BUILD_DIR"
    echo "MODE=$MODE"
    echo "TARGETS=$TARGETS"
    echo "ANDROID_X86_64_SYSROOT=$ANDROID_X86_64_SYSROOT"
    date -u +%Y-%m-%dT%H:%M:%SZ
  } > "$OUT_DIR/NOTE.txt"
  echo "$PROTON_COMMIT" > "$OUT_DIR/PROTON_SHA.txt"
  if [ -f "$PACKAGE_ROOT/lib/wine/x86_64-unix/wineandroid.so" ]; then
    sha256sum \
      "$PACKAGE_ROOT/lib/wine/x86_64-unix/wineandroid.so" \
      "$PACKAGE_ROOT/lib/wine/x86_64-windows/wineandroid.drv" \
      2>/dev/null | tee "$OUT_DIR/SHA256-wineandroid.txt" || true
  fi
  # shellcheck disable=SC1090
  source "$OUT_DIR/proton-wine-wcp.env"
  echo "DROP-IN WCP: $OUT_DIR/$WCP_NAME"
  echo "Install like any CI Proton WCP (Amphora consumes profile.json + layout)."
}

run_full() {
  run_configure
  echo "==> full make -j$JOBS (CI-equivalent; slow once)"
  (
    cd "$BUILD_DIR"
    proton_wcp_export_cross_env
    make -j"$JOBS"
  )
  echo "==> DESTDIR install + assemble WCP package"
  : "${PREFIX_PACK:?PREFIX_PACK required for MODE=full}"
  test -f "$PREFIX_PACK"
  rm -rf "$DESTDIR_ROOT"
  mkdir -p "$DESTDIR_ROOT"
  (
    cd "$BUILD_DIR"
    proton_wcp_export_cross_env
    make -j"$JOBS" DESTDIR="$DESTDIR_ROOT" install
  )
  proton_wcp_assemble_from_destdir "$DESTDIR_ROOT" "$PACKAGE_ROOT" "$PREFIX_PACK"
  pack_dropin_wcp
}

run_incremental() {
  if [ "$NEED_CONFIGURE" = 1 ]; then
    run_configure
  fi
  echo "==> incremental make -j$JOBS $TARGETS"
  (
    cd "$BUILD_DIR"
    proton_wcp_export_cross_env
    # shellcheck disable=SC2086
    make -j"$JOBS" $TARGETS
  )

  if ensure_package_base; then
    echo "==> overlay into package tree (CI-identical paths) → drop-in WCP"
    overlay_build_artifacts_into_package
    if [ -f "$PREFIX_PACK" ] || [ -f "$PACKAGE_ROOT/prefixPack.txz" ]; then
      pack_dropin_wcp
    else
      echo "WARN: PREFIX_PACK missing; staged overlay tree at $PACKAGE_ROOT" >&2
      echo "      set PREFIX_PACK or BASE_WCP to emit Amphora-installable .wcp" >&2
    fi
  else
    cat <<MSG
Built TARGETS in $BUILD_DIR but no package base yet.

Next options for a drop-in Amphora WCP:
  1) MODE=full bash $SCRIPT_DIR/dev-fast-build.sh
     (one-time full make+install; then daily incremental repacks WCP)
  2) BASE_WCP=/path/to/CI-Proton-....wcp bash $SCRIPT_DIR/dev-fast-build.sh
     (overlay rebuilt DLLs into CI WCP at identical paths, repack)

Artifacts still under: $BUILD_DIR
MSG
    mkdir -p "$OUT_DIR"
    echo "$PROTON_COMMIT" > "$OUT_DIR/PROTON_SHA.txt"
    if [ -f "$BUILD_DIR/dlls/wineandroid.drv/wineandroid.so" ]; then
      cp -f "$BUILD_DIR/dlls/wineandroid.drv/wineandroid.so" "$OUT_DIR/"
      cp -f "$BUILD_DIR/dlls/wineandroid.drv/x86_64-windows/wineandroid.drv" "$OUT_DIR/wineandroid.drv"
      sha256sum "$OUT_DIR/wineandroid.so" "$OUT_DIR/wineandroid.drv" | tee "$OUT_DIR/SHA256.txt"
    fi
    echo "bst-aligned build outputs (not yet a full WCP) — see docs/DEV-FAST-WINE.md" > "$OUT_DIR/NOTE.txt"
  fi
}

case "$MODE" in
  configure)
    run_configure
    echo "OK configure-only. Daily: MODE=incremental (default) or MODE=full."
    ;;
  full)
    run_full
    ;;
  pack)
    ensure_package_base || {
      echo "no package tree; run MODE=full or set BASE_WCP" >&2
      exit 1
    }
    pack_dropin_wcp
    ;;
  incremental)
    run_incremental
    ;;
  *)
    echo "unknown MODE=$MODE (use incremental|full|configure|pack)" >&2
    exit 1
    ;;
esac

echo
echo "=== summary ==="
echo "BUILD_DIR=$BUILD_DIR"
echo "OUT_DIR=$OUT_DIR"
echo "PROTON_COMMIT=$PROTON_COMMIT"
echo "Docs: $IMAGEFS_ROOT/docs/DEV-FAST-WINE.md"
