#!/usr/bin/env bash
# Restore BuildStream CAS from wine-dev-bst-cache release (split parts) or a single URL.
#
# Usage:
#   ci/cache/restore-buildstream-cas.sh [--help] [--dry-run] [--force]
#       [--dest DIR] [--base-url URL] [--url SINGLE_TAR_ZST]
#
# Env (overridden by flags):
#   CAS_ROOT / DEST          extract target (default: ~/.cache/buildstream)
#   CI_BST_CACHE_BASE_URL    release asset directory
#   CI_BST_CACHE_URL         single .tar.zst URL (skips parts manifest)
#   CI_BST_CACHE_SHA_URL     sha256sum URL for single-file mode
#   CI_BST_CACHE_NAME        asset basename prefix (default: buildstream-cas-proton-wine)
#   FORCE=1                  replace non-empty DEST
set -euo pipefail

NAME="${CI_BST_CACHE_NAME:-buildstream-cas-proton-wine}"
BASE_URL="${CI_BST_CACHE_BASE_URL:-https://github.com/amphora-dev/imagefs/releases/download/wine-dev-bst-cache}"
SINGLE_URL="${CI_BST_CACHE_URL:-}"
SHA_URL="${CI_BST_CACHE_SHA_URL:-}"
DEST="${CAS_ROOT:-${DEST:-$HOME/.cache/buildstream}}"
FORCE="${FORCE:-0}"
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Download the Actions-exported BuildStream CAS and extract into DEST
(default: ~/.cache/buildstream). Prefer the wine-dev-bst-cache release
(split parts under 2GiB). Single-file --url still works for local copies.

Options:
  -h, --help          Show this help
  -n, --dry-run       Print plan only; do not download or write DEST
  -f, --force         Replace non-empty DEST (or FORCE=1)
      --dest DIR      Extract directory (default: \$HOME/.cache/buildstream)
      --base-url URL  Release asset directory (parts + .parts + .sha256sum)
      --url URL       Single .tar.zst URL (bypass parts)

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --force
  $(basename "$0") --url file:///tmp/${NAME}.tar.zst --dest /tmp/bst-cas
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -f|--force) FORCE=1; shift ;;
    --dest) DEST="${2:?}"; shift 2 ;;
    --base-url) BASE_URL="${2:?}"; shift 2 ;;
    --url) SINGLE_URL="${2:?}"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) echo "unexpected arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

BASE_URL="${BASE_URL%/}"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ] && [ "$FORCE" != 1 ]; then
  echo "CAS present at $DEST (pass --force or FORCE=1 to replace)"
  du -sh "$DEST" || true
  exit 0
fi

need_cmds=(curl zstd tar)
for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null || { echo "missing command: $c" >&2; exit 1; }
done

if [ "$DRY_RUN" = 1 ]; then
  echo "dry-run: DEST=$DEST FORCE=$FORCE"
  if [ -n "$SINGLE_URL" ]; then
    echo "dry-run: single URL=$SINGLE_URL"
    echo "dry-run: sha URL=${SHA_URL:-${SINGLE_URL}.sha256sum}"
  else
    echo "dry-run: base URL=$BASE_URL"
    echo "dry-run: would fetch ${BASE_URL}/${NAME}.parts and listed parts"
    echo "dry-run: sha URL=${BASE_URL}/${NAME}.tar.zst.sha256sum"
  fi
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="$tmp/${NAME}.tar.zst"
sha_file="$tmp/${NAME}.tar.zst.sha256sum"

if [ -n "$SINGLE_URL" ]; then
  echo "Downloading single archive..."
  curl -fL --retry 5 --retry-delay 2 -o "$archive" "$SINGLE_URL"
  sha_fetch="${SHA_URL:-${SINGLE_URL}.sha256sum}"
  if curl -fL --retry 3 -o "$sha_file" "$sha_fetch"; then
    awk -v f="$archive" '{print $1"  "f}' "$sha_file" | sha256sum -c -
  else
    echo "warning: no sha256sum at $sha_fetch; skipping verify" >&2
  fi
else
  parts_url="${BASE_URL}/${NAME}.parts"
  sha_fetch="${BASE_URL}/${NAME}.tar.zst.sha256sum"
  echo "Fetching parts list: $parts_url"
  curl -fL --retry 5 --retry-delay 2 -o "$tmp/parts" "$parts_url"
  curl -fL --retry 3 -o "$sha_file" "$sha_fetch"

  : >"$archive"
  while IFS= read -r part || [ -n "${part:-}" ]; do
    [ -n "$part" ] || continue
    case "$part" in \#*) continue ;; esac
    echo "Downloading $part ..."
    curl -fL --retry 5 --retry-delay 2 -o "$tmp/$part" "${BASE_URL}/${part}"
    cat "$tmp/$part" >>"$archive"
    rm -f "$tmp/$part"
  done <"$tmp/parts"

  awk -v f="$archive" '{print $1"  "f}' "$sha_file" | sha256sum -c -
fi

rm -rf "$DEST"
mkdir -p "$DEST"
zstd -d -c "$archive" | tar -x -C "$DEST"
du -sh "$DEST"
echo "Restored BuildStream CAS → $DEST"
