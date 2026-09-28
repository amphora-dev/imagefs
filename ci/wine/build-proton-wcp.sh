#!/usr/bin/env bash
# Build the pinned Proton Wine source inside a BuildStream sandbox and emit WCP.
set -euo pipefail

: "${ANDROID_NDK_HOME:?BuildStream must provide ANDROID_NDK_HOME}"
: "${LLVM_MINGW_ROOT:?BuildStream must provide LLVM_MINGW_ROOT}"
: "${ANDROID_X86_64_SYSROOT:?BuildStream must provide ANDROID_X86_64_SYSROOT}"
: "${PREFIX_PACK:?BuildStream must provide PREFIX_PACK}"
: "${PULSE_DEV_DEB:?BuildStream must provide PULSE_DEV_DEB}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${PROTON_COMMIT:?BuildStream must provide PROTON_COMMIT}"

JOBS="${JOBS:-$(nproc)}"

# recc's default warning level hides Action Cache hit / miss lines, and info
# on stderr would be one line per compile. Keep those lines in per-process
# files and print a single count when this script exits.
recc_log_dir=""
if command -v recc >/dev/null 2>&1 && [ -n "${RECC_SERVER:-}" ]; then
  recc_log_dir=/tmp/recc-logs
  mkdir -p "$recc_log_dir"
  export RECC_LOG_LEVEL=info
  export RECC_LOG_DIRECTORY="$recc_log_dir"
fi

report_recc_stats() {
  [ -n "$recc_log_dir" ] || return 0
  [ -d "$recc_log_dir" ] || return 0
  python3 - "$recc_log_dir" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
hit = miss = updated = not_compiler = 0
for path in root.rglob("*"):
    if not path.is_file():
        continue
    text = path.read_text(errors="replace")
    hit += text.count("Action Cache hit for [")
    miss += text.count("Action not cached and running in cache-only mode")
    updated += text.count("Action cache updated for [")
    not_compiler += text.count("Not a compiler command")
print(
    f"recc actions: hit={hit} miss={miss} updated={updated} not_compiler={not_compiler}"
)
PY
}
# A failing EXIT trap replaces the script's status under set -e; the count
# must never fail a build.
trap 'report_recc_stats || true' EXIT

recc_wrap_compilers() {
  # Cache-only recc against buildbox-casd (RECC_SERVER set by the element).
  if ! command -v recc >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "${RECC_SERVER:-}" ]; then
    return 0
  fi
  echo "recc: wrapping CC/CXX (server=${RECC_SERVER}, cache_only=${RECC_CACHE_ONLY:-0}, upload_local=${RECC_CACHE_UPLOAD_LOCAL_BUILD:-0})" >&2
  CC="recc ${CC}"
  CXX="recc ${CXX}"
  export CC CXX
}

# Wine --with-mingw=clang invokes bare `clang` from PATH for PE objects, not $CC.
# Install absolute-path shims so only llvm-mingw binaries are wrapped (not NDK *-android*-clang).
recc_wrap_mingw_clang() {
  if ! command -v recc >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "${RECC_SERVER:-}" ]; then
    return 0
  fi
  local wrap_dir="${RECC_MINGW_WRAP_DIR:-/tmp/recc-mingw-wrap}"
  mkdir -p "$wrap_dir"
  local name real
  for name in clang clang++ x86_64-w64-mingw32-clang i686-w64-mingw32-clang \
              x86_64-w64-mingw32-clang++ i686-w64-mingw32-clang++; do
    real="$LLVM_MINGW_ROOT/bin/$name"
    if [ ! -x "$real" ]; then
      continue
    fi
    cat >"$wrap_dir/$name" <<EOF
#!/usr/bin/env bash
exec recc $(printf '%q' "$real") "\$@"
EOF
    chmod +x "$wrap_dir/$name"
  done
  case ":$PATH:" in
    *":$wrap_dir:"*) ;;
    *) PATH="$wrap_dir:$PATH"; export PATH ;;
  esac
  echo "recc: mingw PATH wrap at $wrap_dir (bare clang -> recc llvm-mingw)" >&2
}

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
TARGET=x86_64-linux-android30
NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
TOOLCHAIN="$NDK_TOOLCHAIN/bin"
DEPS="$ANDROID_X86_64_SYSROOT/usr"
DESTDIR=/tmp/proton-wine-dest
PACKAGE_ROOT=/tmp/proton-wine-package
WINE_PREFIX=/opt/wine

configure_recc_toolchain_fingerprint() {
  # recc does not hash the invoked compiler binary. Toolchain elements retain
  # their installation paths across upgrades, so include the hashes of every
  # compiler entry point we wrap in a remote-platform property. This makes an
  # NDK, llvm-mingw, or host-GCC update invalidate old action-cache results.
  # Hash binary contents rather than --version: a toolchain may be rebuilt
  # without changing its reported version.
  command -v recc >/dev/null 2>&1 || return 0
  [ -n "${RECC_SERVER:-}" ] || return 0

  local -a candidates=(
    /usr/bin/gcc
    /usr/bin/g++
    "$TOOLCHAIN/clang"
    "$TOOLCHAIN/clang++"
    "$LLVM_MINGW_ROOT/bin/clang"
    "$LLVM_MINGW_ROOT/bin/clang++"
    "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang"
    "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang"
    "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang++"
    "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang++"
  )
  local -a compilers=()
  local compiler fingerprint
  for compiler in "${candidates[@]}"; do
    [ -x "$compiler" ] && compilers+=("$compiler")
  done
  if [ "${#compilers[@]}" -eq 0 ]; then
    echo "no compilers available for recc fingerprint" >&2
    return 1
  fi
  fingerprint="$(sha256sum "${compilers[@]}" | sha256sum | awk '{print $1}')"
  if [ -z "$fingerprint" ]; then
    echo "failed to calculate recc toolchain fingerprint" >&2
    return 1
  fi
  export RECC_REMOTE_PLATFORM_toolchain="$fingerprint"
  echo "recc: toolchain fingerprint=$fingerprint (${#compilers[@]} compiler paths)" >&2
}

for tool in autoconf autoreconf bison dpkg-deb file flex make meson patch pkg-config \
            python3 readelf sha256sum tar zstd; do
  command -v "$tool" >/dev/null || {
    echo "missing build tool: $tool" >&2
    exit 1
  }
done
for tool in \
  "$TOOLCHAIN/clang" \
  "$TOOLCHAIN/clang++" \
  "$TOOLCHAIN/$TARGET-clang" \
  "$TOOLCHAIN/$TARGET-clang++" \
  "$TOOLCHAIN/llvm-strip" \
  "$LLVM_MINGW_ROOT/bin/llvm-dlltool" \
  "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang" \
  "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang"; do
  test -x "$tool" || {
    echo "missing compiler: $tool" >&2
    exit 1
  }
done
test -d "$DEPS/lib"
test -d "$DEPS/include"
test -f "$PREFIX_PACK"
test -f "$PULSE_DEV_DEB"
test -f VERSION

PULSE_DEV_ROOT=/tmp/termux-pulse-dev
rm -rf "$PULSE_DEV_ROOT"
mkdir -p "$PULSE_DEV_ROOT"
dpkg-deb --fsys-tarfile "$PULSE_DEV_DEB" |
  tar --no-same-owner -xf - -C "$PULSE_DEV_ROOT"
PULSE_DEV_PREFIX="$PULSE_DEV_ROOT/data/data/com.termux/files/usr"
test -f "$PULSE_DEV_PREFIX/include/pulse/pulseaudio.h"
test -f "$PULSE_DEV_PREFIX/include/pulse/version.h"
test -f "$PULSE_DEV_PREFIX/lib/libpulse.so"
grep -Eq '^#define PA_MAJOR +13$' "$PULSE_DEV_PREFIX/include/pulse/version.h"
grep -Eq '^#define PA_PROTOCOL_VERSION +33$' "$PULSE_DEV_PREFIX/include/pulse/version.h"
readelf -dW "$PULSE_DEV_PREFIX/lib/libpulse.so" |
  grep -q 'Shared library: \[libpulsecommon-13\.0\.so\]'

export PATH="$LLVM_MINGW_ROOT/bin:$TOOLCHAIN:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH=/opt/host-freetype/lib
configure_recc_toolchain_fingerprint
# recc recognizes compilers by basename: clang, clang++ and gcc are cached,
# but a target-prefixed name such as $TARGET-clang is "Not a compiler
# command". Call the real clang with the --target the NDK wrapper adds.
# --target goes in CC/CXX, not CFLAGS: Wine links with $(CC) ... $(LDFLAGS)
# and no $(CFLAGS), so a CFLAGS-only target links against the host glibc
# (ntdll.so: undefined symbol setprogname).
export CC="$TOOLCHAIN/clang --target=$TARGET"
export CXX="$TOOLCHAIN/clang++ --target=$TARGET"
export AS="$TOOLCHAIN/$TARGET-clang"
export AR="$TOOLCHAIN/llvm-ar"
export LD="$TOOLCHAIN/ld.lld"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export STRIP="$TOOLCHAIN/llvm-strip"
export DLLTOOL="$LLVM_MINGW_ROOT/bin/llvm-dlltool"
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig"
export ACLOCAL_PATH="$DEPS/lib/aclocal:$DEPS/share/aclocal"
export CPPFLAGS="-I$DEPS/include --sysroot=$NDK_TOOLCHAIN/sysroot"
export CFLAGS="-march=x86-64 -mtune=generic -fPIC -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion"
export CXXFLAGS="$CFLAGS"
# NDK r29's Clang driver injects both --pack-dyn-relocs=relr and
# --use-android-relr-tags for Android targets. Box64 understands standard
# DT_RELR but not the Android-private aliases, so override both parts of that
# driver default. Without the explicit --no-use switch, ntdll's free_areas
# remains the raw 0xd6978 file address and Wine crashes in virtual_init.
export LDFLAGS="-L$DEPS/lib -Wl,-rpath,/usr/lib -Wl,-z,max-page-size=16384 -Wl,--pack-dyn-relocs=relr -Wl,--no-use-android-relr-tags"
export FREETYPE_CFLAGS="-I$DEPS/include/freetype2"
export PULSE_CFLAGS="-I$PULSE_DEV_PREFIX/include"
export PULSE_LIBS="-L$PULSE_DEV_PREFIX/lib -lpulse -pthread"
export SDL2_CFLAGS="-I$DEPS/include/SDL2"
export SDL2_LIBS="-L$DEPS/lib -lSDL2"
export FONTCONFIG_LIBS="-L$DEPS/lib -lfontconfig -lfreetype -lexpat"
export X_CFLAGS="-I$DEPS/include/X11"
export X_LIBS=
export GSTREAMER_CFLAGS="-I$DEPS/include/gstreamer-1.0 -I$DEPS/include/glib-2.0 -I$DEPS/lib/glib-2.0/include -I$DEPS/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$DEPS/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"

./autogen.sh

# Require PresentModes USER_DRIVER thunk (win32u advertises FIFO+MAILBOX+IMMEDIATE).
python3 .bst/ci/wine/check-present-modes-thunk.py

rm -rf wine-tools
mkdir wine-tools
(
  cd wine-tools
  export CC=/usr/bin/gcc
  export CXX=/usr/bin/g++
  export AS=/usr/bin/as
  export AR=/usr/bin/ar
  export LD=/usr/bin/ld
  export RANLIB=/usr/bin/ranlib
  export STRIP=/usr/bin/strip
  recc_wrap_compilers
  unset DLLTOOL PKG_CONFIG_PATH ACLOCAL_PATH
  export PKG_CONFIG_LIBDIR=/opt/host-freetype/lib/pkgconfig
  export CPPFLAGS=-I/opt/host-freetype/include/freetype2
  export LDFLAGS=-L/opt/host-freetype/lib
  export FREETYPE_CFLAGS=-I/opt/host-freetype/include/freetype2
  export FREETYPE_LIBS="-L/opt/host-freetype/lib -lfreetype"
  unset PULSE_CFLAGS PULSE_LIBS
  unset CFLAGS CXXFLAGS
  ../configure \
    --enable-archs=x86_64 \
    --without-x \
    --without-gstreamer \
    --without-pulse \
    --without-vulkan \
    --without-wayland
  make -j"$JOBS" __tooldeps__ nls/all
)

recc_wrap_compilers
recc_wrap_mingw_clang

./configure \
  --enable-archs=x86_64,i386 \
  --host="$TARGET" \
  --prefix="$WINE_PREFIX" \
  --bindir="$WINE_PREFIX/bin" \
  --libdir="$WINE_PREFIX/lib" \
  --exec-prefix="$WINE_PREFIX" \
  --with-mingw=clang \
  --with-wine-tools=./wine-tools \
  --enable-win64 \
  --disable-win16 \
  --enable-nls \
  --disable-amd_ags_x64 \
  --enable-wineandroid_drv=yes \
  --disable-tests \
  --with-alsa \
  --without-capi \
  --without-coreaudio \
  --without-cups \
  --without-dbus \
  --without-ffmpeg \
  --with-fontconfig \
  --with-freetype \
  --without-gcrypt \
  --without-gettext \
  --with-gettextpo=no \
  --without-gphoto \
  --with-gnutls \
  --without-gssapi \
  --with-gstreamer \
  --without-inotify \
  --without-krb5 \
  --without-netapi \
  --without-opencl \
  --with-opengl \
  --without-oss \
  --without-pcap \
  --without-pcsclite \
  --without-piper \
  --with-pthread \
  --with-pulse \
  --without-sane \
  --with-sdl \
  --without-udev \
  --without-unwind \
  --without-usb \
  --without-v4l2 \
  --without-vosk \
  --with-vulkan \
  --without-wayland \
  --without-xcomposite \
  --without-xfixes \
  --without-xinerama \
  --without-xrandr \
  --without-xrender \
  --without-xshape \
  --without-xshm \
  --without-xxf86vm

make -j"$JOBS"
rm -rf "$DESTDIR" "$PACKAGE_ROOT"
make -j"$JOBS" DESTDIR="$DESTDIR" install

installed="$DESTDIR$WINE_PREFIX"
test -d "$installed/lib/wine/x86_64-unix"
test -d "$installed/lib/wine/x86_64-windows"
test -d "$installed/lib/wine/i386-windows"
test -f "$installed/lib/wine/x86_64-unix/winepulse.so"
test -f "$installed/lib/wine/x86_64-windows/winepulse.drv"
test -f "$installed/lib/wine/i386-windows/winepulse.drv"
test -f "$installed/lib/wine/x86_64-unix/wineandroid.so"
test -f "$installed/lib/wine/x86_64-windows/wineandroid.drv"
mkdir -p "$PACKAGE_ROOT/bin" "$PACKAGE_ROOT/lib" "$PACKAGE_ROOT/share"
cp -a "$installed/bin/." "$PACKAGE_ROOT/bin/"
cp -a "$installed/lib/wine" "$PACKAGE_ROOT/lib/"
cp -a "$installed/share/wine" "$PACKAGE_ROOT/share/"

ln -sfn ../lib/wine/x86_64-unix/wine "$PACKAGE_ROOT/bin/wine"
ln -sfn ../lib/wine/x86_64-unix/wine-preloader "$PACKAGE_ROOT/bin/wine-preloader"

find "$PACKAGE_ROOT/lib/wine" "$PACKAGE_ROOT/bin" -type f -print0 |
  while IFS= read -r -d '' binary; do
    case "$(file -b "$binary")" in
      *ELF*) "$TOOLCHAIN/llvm-strip" --strip-unneeded "$binary" 2>/dev/null || true ;;
      *PE32*) "$LLVM_MINGW_ROOT/bin/llvm-strip" --strip-unneeded "$binary" 2>/dev/null || true ;;
    esac
  done

cp "$PREFIX_PACK" "$PACKAGE_ROOT/prefixPack.txz"
version="$(awk '/Wine version/{print $3; exit}' VERSION)"
test -n "$version"
commit_short="${PROTON_COMMIT:0:9}"
full_version="${version}-${commit_short}-x86_64"
wcp_name="Proton-${full_version}.wcp"

python3 - "$PACKAGE_ROOT/profile.json" "$full_version" "$PROTON_COMMIT" <<'PY'
import json
import sys

path, version, commit = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "type": "Proton",
            "versionName": version,
            # Required by the WCP schema, but not an update signal. Amphora
            # replaces installed content by manifest SHA-256.
            "versionCode": 0,
            "description": f"Amphora Proton {version}, Android API30/16KB, commit {commit}",
            "files": [],
            "wine": {
                "binPath": "bin",
                "libPath": "lib",
                "prefixPack": "prefixPack.txz",
            },
        },
        stream,
        indent=2,
    )
    stream.write("\n")
PY

mkdir -p "$OUTPUT_DIR"
tar \
  --sort=name \
  --mtime="@$SOURCE_DATE_EPOCH" \
  --clamp-mtime \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$PACKAGE_ROOT" \
  -cf - bin lib share prefixPack.txz profile.json |
  zstd -T0 -19 -o "$OUTPUT_DIR/$wcp_name"
(
  cd "$OUTPUT_DIR"
  sha256sum "$wcp_name" > "$wcp_name.sha256sum"
)
sha="$(awk '{print $1}' "$OUTPUT_DIR/$wcp_name.sha256sum")"
size="$(stat -c%s "$OUTPUT_DIR/$wcp_name")"
cat > "$OUTPUT_DIR/proton-wine-wcp.env" <<EOF
FULL_VERSION=$full_version
COMMIT_FULL=$PROTON_COMMIT
COMMIT_SHORT=$commit_short
VER_CODE=0
WCP_NAME=$wcp_name
SHA256=$sha
SIZE=$size
EOF

echo "Wrote $OUTPUT_DIR/$wcp_name ($size bytes, sha256=$sha)"
