#!/usr/bin/env bash
# Smoke-test Buildroot-lite package helpers (no NDK / no compile).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# Always a scratch tree, never the ambient BUILD_DIR: the clean-rebuild case
# below runs create-rootfs.sh with REBUILD_ROOTFS=1, which deletes staging /
# host / workdir / stamps. CI exports BUILD_DIR=/tmp/imagefs-build and runs this
# before the build, so honouring it would wipe the very tree under test.
export BUILD_DIR="${PKG_SELFTEST_BUILD_DIR:-/tmp/imagefs-pkg-selftest}"
rm -rf "$BUILD_DIR"
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

# Package-local Mesa toolchain overrides are build inputs too.
mesa_default="$(pkg_content_stamp mesa-gl)"
mesa_api26="$(MESA_GL_API=26 pkg_content_stamp mesa-gl)"
[ "$mesa_default" != "$mesa_api26" ] || fail "mesa-gl stamp ignores MESA_GL_API"
zlib_api26="$(MESA_GL_API=26 pkg_content_stamp zlib)"
[ "$s1" = "$zlib_api26" ] || fail "Mesa override invalidates unrelated package stamps"

# A requested clean rebuild must not leave stamps that make build-all skip
# packages after create-rootfs removed their installed files.
mkdir -p "$STAGING_DIR/stale" "$TARGET_DIR/stale" "$HOST_DIR/stale" \
    "$WORK_DIR/stale" "$BUILT_DIR"
printf 'stale\n' > "$BUILT_DIR/zlib.done"
REBUILD_ROOTFS=1 BUILD_DIR="$BUILD_DIR" \
    bash "$SCRIPT_DIR/create-rootfs.sh" >/dev/null
for stale in \
    "$STAGING_DIR/stale" "$TARGET_DIR/stale" "$HOST_DIR/stale" \
    "$WORK_DIR/stale" "$BUILT_DIR/zlib.done"; do
    [ ! -e "$stale" ] || fail "clean rebuild left stale state: $stale"
done
for required in "$STAGING_DIR" "$TARGET_DIR" "$HOST_DIR" "$WORK_DIR" "$BUILT_DIR"; do
    [ -d "$required" ] || fail "clean rebuild did not recreate state root: $required"
done
# Recipes can write directly below WORK_DIR immediately after create-rootfs.
printf 'generated\n' > "$WORK_DIR/recipe-output.c" ||
    fail "clean rebuild left WORK_DIR unusable"

# Content stamps hash vendor/* trees named in the recipe. The imagefs workflow
# must auto-trigger on those same trees — otherwise a patch-only push skips CI
# while local incremental rebuilds correctly bust stamps.
wf="$SCRIPT_DIR/.github/workflows/build-imagefs.yml"
[ -f "$wf" ] || fail "missing $wf"
declare -A seen_vendor=()
for name in "${ALL_PACKAGES[@]}"; do
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        seen_vendor["$ref"]=1
    done < <(pkg_vendor_refs "$name")
done
for ref in "${!seen_vendor[@]}"; do
    grep -q "$ref/\*\*" "$wf" || fail "build-imagefs.yml paths miss $ref/** (referenced by recipes)"
done

# Source archives are cached independently from mutable src/staging trees. A
# corrupt archive must fail its SHA-256 sidecar check and be fetched again.
fixture="$BUILD_DIR/source-fixture"
mkdir -p "$fixture/payload" "$SRC_DIR"
printf 'known-good\n' > "$fixture/payload/data"
tar -C "$fixture" -czf "$fixture/source.tar.gz" payload
source_url="file://$fixture/source.tar.gz"
(
    cd "$SRC_DIR"
    fetch_source payload fixture.tar.gz "$source_url"
)
[ "$(cat "$SRC_DIR/payload/data")" = "known-good" ] || fail "source cache initial extract is wrong"
archive="$(source_cache_archive "$source_url")"
[ -f "$archive" ] && [ -f "$archive.sha256" ] || fail "source archive was not cached with digest"
rm -rf "$SRC_DIR/payload"
printf 'corrupt\n' > "$archive"
(
    cd "$SRC_DIR"
    fetch_source payload fixture.tar.gz "$source_url"
)
[ "$(cat "$SRC_DIR/payload/data")" = "known-good" ] ||
    fail "corrupt source cache was not replaced"

echo "OK: pkg selftest passed (${#full[@]} packages, glib deps topo ok)"
