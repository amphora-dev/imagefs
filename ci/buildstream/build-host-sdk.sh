#!/usr/bin/env bash
# Generate the complete, host-only BuildStream SDK from a pinned Ubuntu Base.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGES_FILE="${HOST_SDK_PACKAGES_FILE:-$REPO_ROOT/ci/buildstream/host-sdk-packages.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/artifacts}"
CACHE_DIR="${HOST_SDK_DOWNLOAD_DIR:-$HOME/.cache/imagefs-host-sdk}"
BASE_NAME="ubuntu-base-24.04.4-base-amd64.tar.gz"
BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/$BASE_NAME"
BASE_SHA256="c1e67ef7b17a6300e136118bd1dc04725009cb376c1aad10abcf8cd453628d58"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1770683160}"
SDK_NAME="imagefs-host-sdk-noble-amd64.tar.xz"

for tool in bwrap curl sha256sum tar xz; do
    command -v "$tool" >/dev/null || {
        echo "missing host SDK generator dependency: $tool" >&2
        exit 1
    }
done

mapfile -t packages < <(
    sed 's/#.*//; /^[[:space:]]*$/d' "$PACKAGES_FILE"
)
[ "${#packages[@]}" -gt 0 ] || {
    echo "empty host SDK package list: $PACKAGES_FILE" >&2
    exit 1
}

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"
base_archive="$CACHE_DIR/$BASE_NAME"
if ! printf '%s  %s\n' "$BASE_SHA256" "$base_archive" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$base_archive"
    curl -fsSL --retry 3 "$BASE_URL" -o "$base_archive"
    printf '%s  %s\n' "$BASE_SHA256" "$base_archive" | sha256sum -c -
fi

work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
rootfs="$work/rootfs"
mkdir -p "$rootfs"
tar --no-same-owner -xzf "$base_archive" -C "$rootfs"

# Apt runs only while producing the SDK. BuildStream package sandboxes remain
# offline and consume the resulting content-addressed tar artifact.
bwrap \
    --unshare-all \
    --share-net \
    --uid 0 \
    --gid 0 \
    --bind "$rootfs" / \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --setenv HOME /root \
    --setenv LC_ALL C.UTF-8 \
    --setenv DEBIAN_FRONTEND noninteractive \
    /bin/bash -euxo pipefail -c '
        cat > /usr/sbin/policy-rc.d <<EOF
#!/bin/sh
exit 101
EOF
        chmod 0755 /usr/sbin/policy-rc.d
        apt-get -o APT::Sandbox::User=root update
        apt-get -o APT::Sandbox::User=root \
            install -y --no-install-recommends "$@"
        rm -f /usr/sbin/policy-rc.d
        apt-get clean
        rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
        mkdir -p /usr/share/imagefs-host-sdk
        dpkg-query -W -f="${Package}\t${Version}\t${Architecture}\n" |
            LC_ALL=C sort > /usr/share/imagefs-host-sdk/dpkg-manifest.txt
    ' imagefs-host-sdk "${packages[@]}"

rm -f "$rootfs/etc/machine-id"
rm -rf "$rootfs/var/log/"* "$rootfs/var/tmp/"*
find "$rootfs/dev" -mindepth 1 -delete 2>/dev/null || true

archive="$OUTPUT_DIR/$SDK_NAME"
rm -f "$archive" "$archive.sha256"
tar \
    --sort=name \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --clamp-mtime \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=posix \
    --pax-option=delete=atime,delete=ctime \
    -C "$rootfs" -cf - . |
    xz -T0 -6 > "$archive"

sha256sum "$archive" | tee "$archive.sha256"
cp "$rootfs/usr/share/imagefs-host-sdk/dpkg-manifest.txt" \
    "$OUTPUT_DIR/imagefs-host-sdk-packages.txt"
du -h "$archive"
