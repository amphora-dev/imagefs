#!/usr/bin/env bash
# Smoke-test Buildroot-lite package helpers (no NDK / no compile).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Minimal stubs so config.sh path migration does not touch real build dirs.
export BUILD_DIR="${BUILD_DIR:-/tmp/imagefs-pkg-selftest}"
mkdir -p "$BUILD_DIR"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/config.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/pkg.sh"

ALL_PACKAGES=(
    zlib zstd libffi libexpat libpng brotli pcre2 freetype libiconv
    fontconfig glib android-sysvshm libandroid-shmem libcxx-shared
    xorgproto libxcb xtrans libx11 libxext libxfixes libxrender libxcursor
    libxi libxshmfence libdrm vulkan-headers vulkan-loader
    openssl gmp nettle gnutls alsa-lib alsa-android-aserver sdl2
    gstreamer gst-plugins-base android-spawn android-sysv-semaphore
)

pkg_load_depends

fail() { echo "FAIL: $*" >&2; exit 1; }

# glib must pull zlib + libffi + pcre2 + libiconv
mapfile -t expanded < <(pkg_expand_with_deps glib)
printf '%s\n' "${expanded[@]}" | grep -qx zlib || fail "glib expand missing zlib"
printf '%s\n' "${expanded[@]}" | grep -qx libffi || fail "glib expand missing libffi"

mapfile -t ordered < <(pkg_topo_sort "${expanded[@]}")
# zlib before glib
zi=-1 gi=-1 i=0
for p in "${ordered[@]}"; do
    [ "$p" = zlib ] && zi=$i
    [ "$p" = glib ] && gi=$i
    i=$((i + 1))
done
[ "$zi" -ge 0 ] && [ "$gi" -ge 0 ] && [ "$zi" -lt "$gi" ] || fail "topo: zlib ($zi) must precede glib ($gi)"

# Full graph sorts to same cardinality as ALL_PACKAGES
mapfile -t full < <(pkg_topo_sort "${ALL_PACKAGES[@]}")
[ "${#full[@]}" -eq "${#ALL_PACKAGES[@]}" ] || fail "full topo size ${#full[@]} != ${#ALL_PACKAGES[@]}"

# Every package in depends.conf must exist as packages/*/<name>.sh
while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    name="${line%%:*}"
    name="$(echo "$name" | sed 's/[[:space:]]*$//')"
    pkg_recipe_path "$name" >/dev/null || fail "depends.conf lists missing package script: $name"
done < "$SCRIPT_DIR/packages/depends.conf"

# Stamp is stable for identical inputs
mkdir -p "$BUILT_DIR"
s1="$(pkg_content_stamp zlib)"
s2="$(pkg_content_stamp zlib)"
[ "$s1" = "$s2" ] || fail "stamp not stable"

echo "OK: pkg selftest passed (${#full[@]} packages, glib deps topo ok)"
