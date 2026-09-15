#!/usr/bin/env bash
# One-time (or resume) bootstrap of BuildStream-aligned Proton Wine deps for
# ci/wine/dev-fast-build.sh. Fetches pulse deb + prefixPack immediately,
# builds host-freetype locally if needed, and starts/resumes
# wine/sysroot-x86_64.bst (often multi-hour). Writes bst-artifacts/dev-env.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGEFS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS="${ARTIFACTS:-/home/box/src/bst-artifacts}"
LOG="${BST_SYSROOT_LOG:-/workspace/bst-sysroot-build.log}"
BST_WRAPPER="$IMAGEFS_ROOT/buildstream/bst"
INSTALL_BST="$IMAGEFS_ROOT/ci/setup/install-buildstream.sh"

ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/home/box/src/toolchains/android-ndk-r29}"
LLVM_MINGW_ROOT="${LLVM_MINGW_ROOT:-/home/box/src/toolchains/llvm-mingw-20250920-ucrt-ubuntu-22.04-x86_64}"

PULSE_URL="https://ftp.fau.de/termux/apt/termux-main-21/pool/main/p/pulseaudio/pulseaudio_13.0-1_x86_64.deb"
PULSE_SHA="e7931675771c92bfec0e1b2f7acbf94b5a468facf087c52f3980dc5616e30c60"
PULSE_NAME="pulseaudio_13.0-1_x86_64.deb"

PREFIX_URL="https://github.com/amphora-dev/imagefs/releases/download/proton-prefix/prefixPack-11.0-d12a5634a-x86_64-1.txz"
PREFIX_SHA="21492b41aad110331449cb410bda62d8004466beff684b7903367657b972f775"
PREFIX_NAME="prefixPack-11.0-d12a5634a-x86_64-1.txz"

SYSROOT_CHECKOUT="$ARTIFACTS/android-x86_64-sysroot"
HOST_FT_PREFIX="$ARTIFACTS/host-freetype"
BG="${BG:-1}"   # 1 = background long bst build when sysroot missing

mkdir -p "$ARTIFACTS" "$(dirname "$LOG")"

echo "==> ensure BuildStream tools"
bash "$INSTALL_BST"
# shellcheck disable=SC1091
eval "$(bash "$INSTALL_BST" | awk '/^export PATH=/{print}')"
TOOLS_ROOT="${BST_TOOLS_ROOT:-$HOME/.cache/imagefs-buildstream/tools}"
export PATH="$TOOLS_ROOT/venv/bin:$TOOLS_ROOT/bin:$PATH"
command -v bst >/dev/null
command -v buildbox-casd >/dev/null || command -v buildbox-run >/dev/null
"$BST_WRAPPER" --version || bst --version

fetch_sha() {
  local url="$1" dest="$2" sha="$3"
  if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
    echo "  ok $dest"
    return 0
  fi
  echo "  download $url"
  curl -fL --retry 5 --retry-delay 2 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
  echo "$sha  $dest" | sha256sum -c -
}

echo "==> fetch pulse deb + prefixPack (CI-pinned)"
fetch_sha "$PULSE_URL" "$ARTIFACTS/$PULSE_NAME" "$PULSE_SHA"
fetch_sha "$PREFIX_URL" "$ARTIFACTS/$PREFIX_NAME" "$PREFIX_SHA"

# Prefer CI-packed sysroot (Actions CAS → release). Falls back to local bst.
PREFER_CI_SYSROOT="${PREFER_CI_SYSROOT:-1}"
CI_SYSROOT_URL="${CI_SYSROOT_URL:-https://github.com/amphora-dev/imagefs/releases/download/wine-dev-sysroot/android-x86_64-sysroot.tar.zst}"
CI_SYSROOT_SHA_URL="${CI_SYSROOT_SHA_URL:-${CI_SYSROOT_URL}.sha256sum}"
CI_HOST_FT_URL="${CI_HOST_FT_URL:-https://github.com/amphora-dev/imagefs/releases/download/wine-dev-sysroot/host-freetype.tar.zst}"

fetch_ci_sysroot() {
  if [ "${PREFER_CI_SYSROOT}" != 1 ]; then
    return 1
  fi
  if [ -d "$SYSROOT_CHECKOUT/usr/lib" ] && [ -d "$SYSROOT_CHECKOUT/usr/include" ]; then
    echo "  sysroot already at $SYSROOT_CHECKOUT"
    return 0
  fi
  echo "==> try CI wine-dev-sysroot release"
  local tmp sha_file
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  if ! curl -fL --retry 5 --retry-delay 2 -o "$tmp/sysroot.tar.zst" "$CI_SYSROOT_URL"; then
    echo "  CI sysroot not published yet (ok — will bst locally)"
    return 1
  fi
  if curl -fL --retry 3 -o "$tmp/sysroot.sha256sum" "$CI_SYSROOT_SHA_URL" 2>/dev/null; then
    # sha file may list relative name — normalize
    awk -v f="$tmp/sysroot.tar.zst" '{print $1"  "f}' "$tmp/sysroot.sha256sum" | sha256sum -c -
  else
    echo "  WARN: no sha256sum beside release asset; skipping verify"
  fi
  rm -rf "$SYSROOT_CHECKOUT"
  mkdir -p "$SYSROOT_CHECKOUT"
  zstd -d -c "$tmp/sysroot.tar.zst" | tar -x -C "$SYSROOT_CHECKOUT"
  test -d "$SYSROOT_CHECKOUT/usr/lib"
  echo "  unpacked CI sysroot → $SYSROOT_CHECKOUT"
  # host-freetype from same release if missing
  if [ ! -f "$HOST_FT_PREFIX/lib/libfreetype.so" ] && [ ! -f "$HOST_FT_PREFIX/lib/libfreetype.a" ]; then
    if curl -fL --retry 3 -o "$tmp/host-freetype.tar.zst" "$CI_HOST_FT_URL"; then
      mkdir -p "$HOST_FT_PREFIX"
      zstd -d -c "$tmp/host-freetype.tar.zst" | tar -x -C "$HOST_FT_PREFIX"
      echo "  unpacked CI host-freetype → $HOST_FT_PREFIX"
    fi
  fi
  return 0
}


build_host_freetype() {
  if [ -f "$HOST_FT_PREFIX/lib/libfreetype.so" ] || \
     [ -f "$HOST_FT_PREFIX/lib/libfreetype.a" ]; then
    echo "  host-freetype already at $HOST_FT_PREFIX"
    return 0
  fi
  echo "==> build host-freetype → $HOST_FT_PREFIX (mirrors wine/host-freetype.bst)"
  local srcdir work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  curl -fL --retry 3 -o "$work/ft.tar.xz" \
    "https://downloads.sourceforge.net/freetype/freetype-2.13.3.tar.xz"
  echo "0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289  $work/ft.tar.xz" \
    | sha256sum -c -
  tar -xJf "$work/ft.tar.xz" -C "$work"
  srcdir="$work/freetype-2.13.3"
  (
    cd "$srcdir"
    export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export CC=/usr/bin/gcc CXX=/usr/bin/g++ AR=/usr/bin/ar RANLIB=/usr/bin/ranlib STRIP=/usr/bin/strip
    unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS || true
    ./configure \
      --prefix="$HOST_FT_PREFIX" \
      --without-zlib \
      --without-bzip2 \
      --without-png \
      --without-harfbuzz \
      --without-brotli
    make -j"$(nproc)"
    make install
  )
}

fetch_ci_sysroot || true
build_host_freetype

write_dev_env() {
  local sysroot_ready=0
  if [ -d "$SYSROOT_CHECKOUT/usr/lib" ] && [ -d "$SYSROOT_CHECKOUT/usr/include" ]; then
    sysroot_ready=1
  fi
  cat > "$ARTIFACTS/dev-env.sh" <<ENV
# Generated by ci/wine/dev-bootstrap-sysroot.sh — source before dev-fast-build.sh
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME@Q}
export LLVM_MINGW_ROOT=${LLVM_MINGW_ROOT@Q}
export ANDROID_X86_64_SYSROOT=${SYSROOT_CHECKOUT@Q}
export HOST_FREETYPE=${HOST_FT_PREFIX@Q}
export PULSE_DEV_DEB=${ARTIFACTS@Q}/$PULSE_NAME
export PREFIX_PACK=${ARTIFACTS@Q}/$PREFIX_NAME
export PATH=${LLVM_MINGW_ROOT@Q}/bin:${ANDROID_NDK_HOME@Q}/toolchains/llvm/prebuilt/linux-x86_64/bin:\$PATH
# BuildStream tools
export PATH=${TOOLS_ROOT@Q}/venv/bin:${TOOLS_ROOT@Q}/bin:\$PATH
# sysroot_ready=$sysroot_ready  (1=usr/lib present)
ENV
  if [ "$sysroot_ready" = 0 ]; then
    cat >> "$ARTIFACTS/dev-env.sh" <<'ENV'

# WARNING: ANDROID_X86_64_SYSROOT not populated yet.
# Wait for /workspace/bst-sysroot-build.log to finish, then re-run:
#   bash ci/wine/dev-bootstrap-sysroot.sh
# or manually: buildstream/bst artifact checkout wine/sysroot-x86_64.bst /home/box/src/bst-artifacts/android-x86_64-sysroot
ENV
  fi
  echo "wrote $ARTIFACTS/dev-env.sh (sysroot_ready=$sysroot_ready)"
}

checkout_sysroot_if_built() {
  if "$BST_WRAPPER" show --deps none wine/sysroot-x86_64.bst 2>/dev/null | grep -q cached; then
    :
  fi
  # Try checkout; succeed only if artifact exists.
  if "$BST_WRAPPER" checkout --force --hardlinks wine/sysroot-x86_64.bst "$SYSROOT_CHECKOUT" 2>"$ARTIFACTS/checkout-sysroot.err"; then
    echo "checked out sysroot → $SYSROOT_CHECKOUT"
    return 0
  fi
  echo "sysroot checkout not ready yet ($(wc -l < "$ARTIFACTS/checkout-sysroot.err" 2>/dev/null || echo 0) err lines)"
  return 1
}

start_or_resume_sysroot_build() {
  if [ -d "$SYSROOT_CHECKOUT/usr/lib" ]; then
    echo "sysroot already present at $SYSROOT_CHECKOUT"
    return 0
  fi
  if fetch_ci_sysroot; then
    return 0
  fi

  # Also try building host-freetype via bst for CAS completeness (optional).
  echo "==> BuildStream: wine/sysroot-x86_64.bst (long; log=$LOG)"
  local cmd=( "$BST_WRAPPER" build wine/sysroot-x86_64.bst )
  if [ "$BG" = 1 ]; then
    if pgrep -f 'bst.*wine/sysroot-x86_64' >/dev/null 2>&1; then
      echo "bst sysroot build already running — see $LOG"
      return 0
    fi
    # Detach fully so bootstrap can finish and land scripts.
    nohup bash -c '
      set -euo pipefail
      IMAGEFS_ROOT="$1"; LOG="$2"; ARTIFACTS="$3"; SYSROOT_CHECKOUT="$4"
      TOOLS_ROOT="${BST_TOOLS_ROOT:-$HOME/.cache/imagefs-buildstream/tools}"
      export PATH="$TOOLS_ROOT/venv/bin:$TOOLS_ROOT/bin:$PATH"
      cd "$IMAGEFS_ROOT"
      echo "=== bst build wine/sysroot-x86_64.bst start $(date -u) ==="
      if buildstream/bst build wine/sysroot-x86_64.bst; then
        echo "=== build OK $(date -u) — checking out ==="
        rm -rf "$SYSROOT_CHECKOUT"
        buildstream/bst artifact checkout --force --hardlinks wine/sysroot-x86_64.bst "$SYSROOT_CHECKOUT"
        # also pull host-freetype artifact if present
        buildstream/bst build wine/host-freetype.bst || true
        echo "=== checkout done $(date -u) ==="
        # refresh dev-env
        bash ci/wine/dev-bootstrap-sysroot.sh >/tmp/dev-bootstrap-refresh.log 2>&1 || true
      else
        echo "=== build FAILED $(date -u) — re-run: bash ci/wine/dev-bootstrap-sysroot.sh ==="
        exit 1
      fi
    ' _ "$IMAGEFS_ROOT" "$LOG" "$ARTIFACTS" "$SYSROOT_CHECKOUT" \
      >>"$LOG" 2>&1 &
    echo $! > "$ARTIFACTS/bst-sysroot-build.pid"
    echo "started background bst pid=$(cat "$ARTIFACTS/bst-sysroot-build.pid")"
    echo "  tail -f $LOG"
    echo "  resume: bash $SCRIPT_DIR/dev-bootstrap-sysroot.sh"
    return 0
  fi

  # Foreground path
  (cd "$IMAGEFS_ROOT" && "${cmd[@]}") | tee -a "$LOG"
  rm -rf "$SYSROOT_CHECKOUT"
  (cd "$IMAGEFS_ROOT" && "$BST_WRAPPER" checkout --force --hardlinks wine/sysroot-x86_64.bst "$SYSROOT_CHECKOUT")
}

# Attempt checkout first in case a previous run finished.
checkout_sysroot_if_built || true
start_or_resume_sysroot_build
write_dev_env

cat <<SUMMARY

=== bootstrap status ===
ARTIFACTS=$ARTIFACTS
PULSE=$ARTIFACTS/$PULSE_NAME
PREFIX_PACK=$ARTIFACTS/$PREFIX_NAME
HOST_FREETYPE=$HOST_FT_PREFIX
SYSROOT=$SYSROOT_CHECKOUT
LOG=$LOG
dev-env: source $ARTIFACTS/dev-env.sh

Next when sysroot ready:
  source $ARTIFACTS/dev-env.sh
  MODE=full bash $SCRIPT_DIR/dev-fast-build.sh   # first drop-in WCP
  bash $SCRIPT_DIR/dev-fast-build.sh             # daily incremental + repack

CI release path unchanged: l1/proton-wine-wcp.bst / build-proton-wine
SUMMARY
