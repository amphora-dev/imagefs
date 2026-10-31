#!/usr/bin/env bash
# Decide whether to build/publish the Mesa WGL runtime asset.
# Writes should_build and tzst_name to $GITHUB_OUTPUT.
#
# The asset name is mesa-wgl-<MESA_VERSION>-s<sha256(build script)[0:8]>.tzst,
# the same name ci/mesa-wgl/build-mesa-wgl.sh computes inside the sandbox.
#
# Env:
#   FORCE, EVENT_NAME, REPO, GH_TOKEN
#   ELEMENT      (default buildstream/elements/l1/mesa-wgl.bst)
#   SCRIPT       (default ci/mesa-wgl/build-mesa-wgl.sh)
#   RELEASE_TAG  (default mesa-wgl)
set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"

ELEMENT="${ELEMENT:-buildstream/elements/l1/mesa-wgl.bst}"
SCRIPT="${SCRIPT:-ci/mesa-wgl/build-mesa-wgl.sh}"
RELEASE_TAG="${RELEASE_TAG:-mesa-wgl}"

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

SCRIPT_SHA8="$(sha256sum "$SCRIPT" | cut -c1-8)"
TZST_NAME="mesa-wgl-${VERSION}-s${SCRIPT_SHA8}.tzst"
echo "tzst_name=$TZST_NAME" >> "$GITHUB_OUTPUT"

if [ "${FORCE}" = "true" ] || [ "${EVENT_NAME}" = "push" ]; then
  echo "should_build=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

if gh release view "${RELEASE_TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  if gh release view "${RELEASE_TAG}" --repo "${REPO}" --json assets \
    --jq '.assets[].name' | grep -qxF -- "$TZST_NAME"; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "Already published: $TZST_NAME"
    exit 0
  fi
fi
echo "should_build=true" >> "$GITHUB_OUTPUT"
