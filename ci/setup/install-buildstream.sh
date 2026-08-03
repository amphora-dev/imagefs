#!/usr/bin/env bash
# Install pinned BuildStream/BuildBox tooling for the opt-in PoC workflow.
set -euo pipefail

BST_VERSION="${BST_VERSION:-2.7.0}"
BST_CORE_PLUGINS_VERSION="${BST_CORE_PLUGINS_VERSION:-2.7.0}"
BST_PLUGINS_VERSION="${BST_PLUGINS_VERSION:-2.3.1}"
BUILDBOX_VERSION="${BUILDBOX_VERSION:-1.4.15}"
BUILDBOX_SHA256="${BUILDBOX_SHA256:-07ce72be4a7a33534a1f31a7ebf28fb1d830686c6deff068ee6353e2fc811c0d}"
TOOLS_ROOT="${BST_TOOLS_ROOT:-$HOME/.cache/imagefs-buildstream/tools}"
VENV="$TOOLS_ROOT/venv"
BIN="$TOOLS_ROOT/bin"

mkdir -p "$TOOLS_ROOT" "$BIN"

plugin_versions="$("$VENV/bin/python" -c \
    'from importlib.metadata import version; print(version("buildstream-plugins"), version("buildstream-plugins-community"))' \
    2>/dev/null || true)"
if [ ! -x "$VENV/bin/bst" ] ||
   [ "$("$VENV/bin/bst" --version 2>/dev/null || true)" != "$BST_VERSION" ] ||
   [ "$plugin_versions" != "$BST_CORE_PLUGINS_VERSION $BST_PLUGINS_VERSION" ]; then
    rm -rf "$VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --disable-pip-version-check --quiet --upgrade pip
    "$VENV/bin/pip" install --disable-pip-version-check --quiet \
        "BuildStream==$BST_VERSION" \
        "buildstream-plugins==$BST_CORE_PLUGINS_VERSION" \
        "buildstream-plugins-community==$BST_PLUGINS_VERSION"
fi

if [ ! -x "$BIN/buildbox-casd" ] ||
   [ "$("$BIN/buildbox-casd" --version 2>/dev/null | awk 'NR == 1 {print $2}')" != "$BUILDBOX_VERSION" ]; then
    archive="$(mktemp)"
    trap 'rm -f "$archive"' EXIT
    curl -fsSL --retry 3 \
        "https://gitlab.com/BuildGrid/buildbox/buildbox-integration/-/releases/$BUILDBOX_VERSION/downloads/buildbox-x86_64-linux-gnu.tgz" \
        -o "$archive"
    printf '%s  %s\n' "$BUILDBOX_SHA256" "$archive" | sha256sum -c -
    rm -rf "$BIN"
    mkdir -p "$BIN"
    tar -xzf "$archive" -C "$BIN"
fi
ln -sfn "$BIN/buildbox-run-bubblewrap" "$BIN/buildbox-run"

if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n%s\n' "$VENV/bin" "$BIN" >> "$GITHUB_PATH"
fi

printf 'BuildStream %s installed in %s\n' "$BST_VERSION" "$TOOLS_ROOT"
printf 'export PATH=%q:%q:$PATH\n' "$VENV/bin" "$BIN"
