#!/usr/bin/env bash
# Point BuildStream at the shared remote cache: CAS, element artifacts,
# source cache and the action cache behind remote-apis-socket (recc).
# Without a token this is a no-op and builds use the local cache only.
#
# The default host is the origin A record, not the Cloudflare-proxied name.
# Orange-cloud stalls buildbox's long gRPC streams (ByteStream and Remote
# Asset): the client sits in "Pushing artifact" while the origin receives
# no bytes. Short requests through Cloudflare can still look fast.
set -euo pipefail

url="${BST_REMOTE_CACHE_URL:-https://cas.arm.512.pub}"
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

# Per-RPC ceiling. A stalled stream fails here instead of holding the job
# until the workflow timeout. keepalive lets casd notice a dead connection.
cat > "$conf" << EOF
cache:
  storage-service:
    url: $url
    auth:
      access-token: $token_file
    connection-config:
      request-timeout: 900
      keepalive-time: 30
artifacts:
  servers:
  - url: $url
    push: true
    auth:
      access-token: $token_file
    connection-config:
      request-timeout: 900
      keepalive-time: 30
source-caches:
  servers:
  - url: $url
    push: true
    auth:
      access-token: $token_file
    connection-config:
      request-timeout: 900
      keepalive-time: 30
remote-execution:
  action-cache-service:
    url: $url
    push: true
    auth:
      access-token: $token_file
    connection-config:
      request-timeout: 900
      keepalive-time: 30
EOF

echo "BuildStream remote cache: $url -> $conf"
