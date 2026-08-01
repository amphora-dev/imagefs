#!/usr/bin/env bash
# =============================================================================
# Build Bionic Box64 and pack a Winlator Component Package (.wcp).
#
# Independent of imagefs.txz — Box64 updates more often than the rootfs, so
# Amphora pins it via content_manifest.components.box64 only.
#
# Output (under $OUTPUT_DIR):
#   Box64-<major.minor.rev>-<shortsha>.wcp
#   Box64-<major.minor.rev>-<shortsha>.wcp.sha256sum
#   box64-wcp.env   # FULL_VERSION / WCP_NAME / SHA256 / SIZE for CI
#
# Env:
#   BOX64_REF              git ref to build (default: origin/main tip)
#   BOX64_REPO             default https://github.com/ptitSeb/box64.git
#   ANDROID_NDK_HOME       required (or ANDROID_NDK_ROOT / runner NDK)
#   ANDROID_API            NDK API level (default 31 — WinNative Bionic; needs
#                          pthread_attr_*inheritsched / mutexattr_*protocol which
#                          Bionic exposes at higher APIs. TERMUX=0. imagefs stays
#                          on API 26; box64 only needs libc/libm/libdl at runtime.)
#   APPLY_PIPETTO_PATCH    1=apply vendor/box64-patches/pipetto-controller-fix.patch
#   OUTPUT_DIR             default $PWD/artifacts
#   BUILD_DIR              default /tmp/box64-wcp-build
#   JOBS                   parallel make jobs (default nproc)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BOX64_REPO="${BOX64_REPO:-https://github.com/ptitSeb/box64.git}"
BOX64_REF="${BOX64_REF:-}"
ANDROID_API="${ANDROID_API:-31}"
APPLY_PIPETTO_PATCH="${APPLY_PIPETTO_PATCH:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/artifacts}"
BUILD_DIR="${BUILD_DIR:-/tmp/box64-wcp-build}"
JOBS="${JOBS:-$(nproc)}"
SRC_DIR="$BUILD_DIR/src"
CMAKE_BUILD="$BUILD_DIR/cmake-build"

source "$REPO_ROOT/lib/ndk.sh"
ndk_require

TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
CC_BIN="$TC/bin/aarch64-linux-android${ANDROID_API}-clang"
STRIP_BIN="$TC/bin/llvm-strip"
if [ ! -x "$CC_BIN" ]; then
    echo "FAIL: missing compiler $CC_BIN" >&2
    exit 1
fi

mkdir -p "$SRC_DIR" "$CMAKE_BUILD" "$OUTPUT_DIR"

# ---- fetch upstream ----
if [ ! -d "$SRC_DIR/box64/.git" ]; then
    rm -rf "$SRC_DIR/box64"
    git clone --filter=blob:none "$BOX64_REPO" "$SRC_DIR/box64"
fi
cd "$SRC_DIR/box64"
git fetch --tags --force origin
if [ -n "$BOX64_REF" ]; then
    git checkout --force "$BOX64_REF"
    git pull --ff-only 2>/dev/null || true
else
    git checkout --force main
    git pull --ff-only origin main
fi
# Drop local patch residue from prior runs
git reset --hard HEAD
git clean -fdx

COMMIT_FULL="$(git rev-parse HEAD)"
COMMIT_SHORT="$(git rev-parse --short=9 HEAD)"
MAJOR="$(awk '/#define BOX64_MAJOR/{print $3}' src/box64version.h)"
MINOR="$(awk '/#define BOX64_MINOR/{print $3}' src/box64version.h)"
REVISION="$(awk '/#define BOX64_REVISION/{print $3}' src/box64version.h)"
FULL_VERSION="${MAJOR}.${MINOR}.${REVISION}-${COMMIT_SHORT}"
WCP_NAME="Box64-${FULL_VERSION}.wcp"

echo "Building Box64 ${FULL_VERSION} (commit ${COMMIT_FULL})"

# ---- optional WinNative controller / android-spawn wrap patch ----
if [ "$APPLY_PIPETTO_PATCH" = "1" ]; then
    PATCH="$REPO_ROOT/vendor/box64-patches/pipetto-controller-fix.patch"
    if [ -f "$PATCH" ]; then
        echo "Applying $PATCH"
        # Mailbox series from WinNative; upstream moves fast — fall back cleanly.
        if git apply --check "$PATCH" 2>/dev/null; then
            git apply "$PATCH"
        elif patch -p1 --forward --batch --dry-run < "$PATCH" >/dev/null 2>&1; then
            patch -p1 --forward --batch < "$PATCH"
        else
            echo "WARN: pipetto patch did not apply cleanly; continuing without it" >&2
            git checkout -- .
            git clean -fd
        fi
    else
        echo "WARN: patch missing at $PATCH; skipping" >&2
    fi
fi

# ---- configure / build (WinNative Bionic flags) ----
rm -rf "$CMAKE_BUILD"
mkdir -p "$CMAKE_BUILD"
cd "$CMAKE_BUILD"

# Silence Bionic header gaps that still show up as errors under -Werror-ish defaults
# on some NDK/clang combos even at API 31.
export CFLAGS="${CFLAGS:-} -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-function-declaration"

cmake "$SRC_DIR/box64" \
    -DCMAKE_C_COMPILER="$CC_BIN" \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DANDROID=1 \
    -DBIONIC=1 \
    -DARM_DYNAREC=1 \
    -DBAD_SIGNAL=1 \
    -DTERMUX=0 \
    -DHAVE_TRACE=0 \
    -DNOGIT=ON

# Upstream dynarec has had parallel-build races; prefer JOBS but allow override.
make -j"$JOBS"
"$STRIP_BIN" box64

# ---- ELF sanity (must be Bionic, not glibc) ----
if command -v readelf >/dev/null 2>&1; then
    INTERP="$(readelf -l box64 | awk -F: '/interpreter/{gsub(/[\[\] ]/,"",$2); print $2}')"
    echo "interpreter: $INTERP"
    case "$INTERP" in
        /system/bin/linker64) ;;
        *)
            echo "FAIL: expected /system/bin/linker64, got '$INTERP'" >&2
            exit 1
            ;;
    esac
    echo "NEEDED: $(readelf -d box64 | awk -F'[][]' '/NEEDED/{printf "%s ", $2}')"
fi

# ---- pack WCP (xz tar + profile.json) ----
cat > profile.json <<EOF
{
  "type": "Box64",
  "versionName": "${FULL_VERSION}",
  "versionCode": 0,
  "description": "Box64-${FULL_VERSION}",
  "files": [
    {
      "source": "box64",
      "target": "\${bindir}/box64"
    }
  ]
}
EOF

tar --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH:-0}" --clamp-mtime --sort=name \
  -I 'xz -T1' -cf "$OUTPUT_DIR/$WCP_NAME" box64 profile.json
(
    cd "$OUTPUT_DIR"
    sha256sum "$WCP_NAME" | tee "${WCP_NAME}.sha256sum"
)
SHA256="$(awk '{print $1}' "$OUTPUT_DIR/${WCP_NAME}.sha256sum")"
SIZE="$(stat -c%s "$OUTPUT_DIR/$WCP_NAME")"

cat > "$OUTPUT_DIR/box64-wcp.env" <<EOF
FULL_VERSION=${FULL_VERSION}
COMMIT_FULL=${COMMIT_FULL}
COMMIT_SHORT=${COMMIT_SHORT}
WCP_NAME=${WCP_NAME}
SHA256=${SHA256}
SIZE=${SIZE}
EOF

echo "Wrote $OUTPUT_DIR/$WCP_NAME ($SIZE bytes, sha256=$SHA256)"
ls -lh "$OUTPUT_DIR/$WCP_NAME"
