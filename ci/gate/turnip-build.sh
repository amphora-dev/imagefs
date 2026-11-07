#!/usr/bin/env bash
# Decide whether to build/publish the Turnip runtime asset.
# Writes should_build and zip_name to $GITHUB_OUTPUT.
#
# The asset name is
#   turnip-<MESA_VERSION>-s<sha256(build script + patches)[0:8]>.zip,
# the same name ci/turnip/build-turnip.sh computes inside the sandbox.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
#   ELEMENT      (default buildstream/elements/l1/turnip.bst)
#   SCRIPT       (default ci/turnip/build-turnip.sh)
#   PATCH_DIR    (default vendor/turnip-patches)
#   RELEASE_TAG  (default turnip)
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
export LC_ALL=C

ELEMENT="${ELEMENT:-buildstream/elements/l1/turnip.bst}"
SCRIPT="${SCRIPT:-ci/turnip/build-turnip.sh}"
PATCH_DIR="${PATCH_DIR:-vendor/turnip-patches}"
RELEASE_TAG="${RELEASE_TAG:-turnip}"

env_value() {
  awk -v key="$1:" '$1 == key { gsub(/"/, "", $2); print $2; exit }' "$ELEMENT"
}
VERSION="$(env_value MESA_VERSION)"
TARBALL_SHA="$(env_value MESA_TARBALL_SHA256)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid MESA_VERSION in $ELEMENT: $VERSION" >&2
  exit 1
}
[[ "$TARBALL_SHA" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Invalid MESA_TARBALL_SHA256 in $ELEMENT: $TARBALL_SHA" >&2
  exit 1
}

# The tar source must be the tarball the environment names; BuildStream
# checks the ref, the build script only sees the extracted tree.
SOURCE_REF="$(awk -v url="mesa:mesa-${VERSION}.tar.xz" '
  $1 == "url:" && $2 == url { tar=1; next }
  tar && $1 == "ref:" { print $2; exit }
' "$ELEMENT")"
test "$SOURCE_REF" = "$TARBALL_SHA" || {
  echo "$ELEMENT: tar source mesa:mesa-${VERSION}.tar.xz ref '$SOURCE_REF' != MESA_TARBALL_SHA256 $TARBALL_SHA" >&2
  exit 1
}

patches=("$PATCH_DIR"/*.patch)
test -f "${patches[0]}" || {
  echo "no patches in $PATCH_DIR" >&2
  exit 1
}
IDENTITY_SHA8="$(cat "$SCRIPT" "${patches[@]}" | sha256sum | cut -c1-8)"
ZIP_NAME="turnip-${VERSION}-s${IDENTITY_SHA8}.zip"
echo "zip_name=$ZIP_NAME" >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view "${RELEASE_TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view "${RELEASE_TAG}" --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -qxF -- "$ZIP_NAME"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published: $ZIP_NAME"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
