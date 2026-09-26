#!/usr/bin/env bash
# Point BuildStream at the shared remote cache: CAS, element artifacts,
# source cache and the action cache behind remote-apis-socket (recc).
# Without a token this is a no-op and builds use the local cache only.
set -euo pipefail

url="${BST_REMOTE_CACHE_URL:-https://cas-arm.512.pub}"
token="${BST_REMOTE_CACHE_TOKEN:-}"
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
conf="$conf_dir/buildstream.conf"
token_file="$conf_dir/bst-remote-cache.token"

if [ -z "$token" ]; then
    if [ "${BST_REMOTE_CACHE_REQUIRED:-false}" = true ]; then
        echo "BST_REMOTE_CACHE_TOKEN is required but empty" >&2
        exit 1
    fi
    echo "BST_REMOTE_CACHE_TOKEN not set; using the local BuildStream cache only" >&2
    exit 0
fi

mkdir -p "$conf_dir"
(umask 077 && printf '%s\n' "$token" > "$token_file")

cat > "$conf" << EOF
cache:
  storage-service:
    url: $url
    auth:
      access-token: $token_file
artifacts:
  servers:
  - url: $url
    push: true
    auth:
      access-token: $token_file
source-caches:
  servers:
  - url: $url
    push: true
    auth:
      access-token: $token_file
remote-execution:
  action-cache-service:
    url: $url
    push: true
    auth:
      access-token: $token_file
EOF

echo "BuildStream remote cache: $url -> $conf"
