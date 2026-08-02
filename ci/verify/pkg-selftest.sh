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

# The real package set, not a copy of it (the copy had drifted: no mesa-gl).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/packages/packages.conf"

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

# Every selected package must have a recipe. build-all.sh only finds this out at
# build time, after the packages before it have already been compiled.
for name in "${ALL_PACKAGES[@]}"; do
    pkg_recipe_path "$name" >/dev/null || fail "ALL_PACKAGES lists missing package script: $name"
done

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
