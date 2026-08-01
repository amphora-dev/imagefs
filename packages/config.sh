#!/usr/bin/env bash
# Shim for packages/<category>/*.sh which do:
#   source "$(dirname "$0")/../config.sh"
# That resolves to this file (not the repo-root config.sh). Forward there.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.sh"
