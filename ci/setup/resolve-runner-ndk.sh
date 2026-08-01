#!/usr/bin/env bash
# Resolve a usable Android NDK on the runner / local machine and export
# ANDROID_NDK_HOME + ANDROID_NDK_ROOT. When $GITHUB_ENV is set (Actions), also
# persist those into the job environment.
#
# Discovery itself lives in lib/ndk.sh (shared with setup-env.sh and the L1 leaf
# builders); this script only adds the GITHUB_ENV plumbing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/config.sh"   # NDK_VERSION — pins the preferred NDK major
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/ndk.sh"

ndk_require

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
    echo "ANDROID_NDK_ROOT=$ANDROID_NDK_ROOT"
  } >> "$GITHUB_ENV"
fi
