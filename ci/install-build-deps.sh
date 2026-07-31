#!/usr/bin/env bash
# Install apt/pip packages needed by imagefs CI.
# Usage: ci/install-build-deps.sh [full|box64]
#   full  — full imagefs rootfs build (default)
#   box64 — Box64 WCP only
set -euo pipefail

MODE="${1:-full}"

sudo apt-get update

case "$MODE" in
  box64)
    sudo apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build python3 \
      curl wget git xz-utils tar ca-certificates \
      binutils ccache
    ;;
  full)
    sudo apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build \
      autoconf automake libtool libtool-bin autotools-dev pkg-config \
      perl python3 python3-pip python3-setuptools python3-wheel \
      curl wget git unzip xz-utils tar bzip2 gzip ca-certificates \
      patch file rsync binutils gperf flex bison gettext texinfo \
      patchelf ccache \
      libglib2.0-dev-bin
    sudo pip3 install --no-cache-dir "meson>=1.3"
    ;;
  *)
    echo "usage: $0 [full|box64]" >&2
    exit 2
    ;;
esac
