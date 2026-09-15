#!/usr/bin/env bash
# Build the pinned Proton Wine source inside a BuildStream sandbox and emit WCP.
# Configure/env/packaging shared with ci/wine/proton-wcp-env.sh (also used by
# ci/wine/dev-fast-build.sh). Behavior must stay identical to the previous
# inlined script so artifact keys remain stable for unchanged inputs.
set -euo pipefail

: "${ANDROID_NDK_HOME:?BuildStream must provide ANDROID_NDK_HOME}"
: "${LLVM_MINGW_ROOT:?BuildStream must provide LLVM_MINGW_ROOT}"
: "${ANDROID_X86_64_SYSROOT:?BuildStream must provide ANDROID_X86_64_SYSROOT}"
: "${PREFIX_PACK:?BuildStream must provide PREFIX_PACK}"
: "${PULSE_DEV_DEB:?BuildStream must provide PULSE_DEV_DEB}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${PROTON_COMMIT:?BuildStream must provide PROTON_COMMIT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=proton-wcp-env.sh
source "$SCRIPT_DIR/proton-wcp-env.sh"

JOBS="$PROTON_WCP_JOBS"
DESTDIR=/tmp/proton-wine-dest
PACKAGE_ROOT=/tmp/proton-wine-package

proton_wcp_require_tools 1
test -f VERSION

proton_wcp_prepare_pulse
proton_wcp_export_cross_env

./autogen.sh

rm -rf wine-tools
mkdir wine-tools
(
  cd wine-tools
  proton_wcp_export_wine_tools_env
  # shellcheck disable=SC2046
  ../configure $(proton_wcp_wine_tools_configure_args)
  make -j"$JOBS" __tooldeps__ nls/all
)

proton_wcp_export_cross_env
# shellcheck disable=SC2046
./configure $(proton_wcp_cross_configure_args ./wine-tools)

make -j"$JOBS"
rm -rf "$DESTDIR" "$PACKAGE_ROOT"
make -j"$JOBS" DESTDIR="$DESTDIR" install

proton_wcp_assemble_from_destdir "$DESTDIR" "$PACKAGE_ROOT" "$PREFIX_PACK"
proton_wcp_strip_package "$PACKAGE_ROOT"
proton_wcp_write_profile_and_pack "$PACKAGE_ROOT" "$OUTPUT_DIR" "$PROTON_COMMIT" VERSION
