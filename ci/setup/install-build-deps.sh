#!/usr/bin/env bash
# Install apt/pip packages needed by imagefs CI.
#
# Modes (aliases accepted):
#   leaf | box64  — single-product / few-tool builds (Box64 WCP, …)
#   graph | full  — multi-package imagefs graph (meson/autotools/…)
set -euo pipefail

MODE="${1:-graph}"
case "$MODE" in
  box64) MODE=leaf ;;
  full) MODE=graph ;;
  wrapper) MODE=wrapper ;;
esac

sudo apt-get update

case "$MODE" in
  leaf)
    sudo apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build python3 \
      curl wget git xz-utils tar ca-certificates \
      binutils ccache
    ;;
  graph|wrapper)
    # wrapper = graph toolchain + mesa host tools (mako/zstd/clang for native).
    sudo apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build \
      autoconf automake libtool libtool-bin autotools-dev pkg-config \
      perl python3 python3-pip python3-setuptools python3-wheel \
      python3-mako \
      curl wget git unzip xz-utils tar bzip2 gzip ca-certificates \
      patch file rsync binutils gperf flex bison gettext texinfo \
      patchelf ccache zstd \
      clang llvm \
      libglib2.0-dev-bin \
      libzstd-dev zlib1g-dev libdrm-dev
    sudo pip3 install --no-cache-dir "meson>=1.3"
    ;;
  *)
    echo "usage: $0 [leaf|graph|wrapper]  (aliases: box64→leaf, full→graph)" >&2
    exit 2
    ;;
esac
