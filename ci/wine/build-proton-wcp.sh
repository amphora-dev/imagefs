#!/usr/bin/env bash
# Build the pinned Proton Wine source inside a BuildStream sandbox and emit WCP.
set -euo pipefail

: "${ANDROID_NDK_HOME:?BuildStream must provide ANDROID_NDK_HOME}"
: "${LLVM_MINGW_ROOT:?BuildStream must provide LLVM_MINGW_ROOT}"
: "${ANDROID_X86_64_SYSROOT:?BuildStream must provide ANDROID_X86_64_SYSROOT}"
: "${PREFIX_PACK:?BuildStream must provide PREFIX_PACK}"
: "${OUTPUT_DIR:?BuildStream must provide OUTPUT_DIR}"
: "${PROTON_COMMIT:?BuildStream must provide PROTON_COMMIT}"

JOBS="${JOBS:-$(nproc)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
TARGET=x86_64-linux-android35
NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
TOOLCHAIN="$NDK_TOOLCHAIN/bin"
DEPS="$ANDROID_X86_64_SYSROOT"
DESTDIR=/tmp/proton-wine-dest
PACKAGE_ROOT=/tmp/proton-wine-package
WINE_PREFIX=/opt/wine

for tool in autoconf autoreconf bison file flex make meson patch pkg-config \
            python3 tar zstd; do
  command -v "$tool" >/dev/null || {
    echo "missing build tool: $tool" >&2
    exit 1
  }
done
for tool in \
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
test -f VERSION

export PATH="$LLVM_MINGW_ROOT/bin:$TOOLCHAIN:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export CC="$TOOLCHAIN/$TARGET-clang"
export AS="$CC"
export CXX="$TOOLCHAIN/$TARGET-clang++"
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
export LDFLAGS="-L$DEPS/lib -Wl,-rpath,/usr/lib -Wl,-z,max-page-size=16384"
export FREETYPE_CFLAGS="-I$DEPS/include/freetype2"
export SDL2_CFLAGS="-I$DEPS/include/SDL2"
export SDL2_LIBS="-L$DEPS/lib -lSDL2"
export FONTCONFIG_LIBS="-L$DEPS/lib -lfontconfig -lfreetype -lexpat"
export X_CFLAGS="-I$DEPS/include/X11"
export X_LIBS=
export GSTREAMER_CFLAGS="-I$DEPS/include/gstreamer-1.0 -I$DEPS/include/glib-2.0 -I$DEPS/lib/glib-2.0/include -I$DEPS/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$DEPS/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"

./autogen.sh

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
  unset DLLTOOL PKG_CONFIG_PATH ACLOCAL_PATH
  export PKG_CONFIG_LIBDIR=/opt/host-freetype/lib/pkgconfig
  export CPPFLAGS=-I/opt/host-freetype/include/freetype2
  export LDFLAGS=-L/opt/host-freetype/lib
  export FREETYPE_CFLAGS=-I/opt/host-freetype/include/freetype2
  export FREETYPE_LIBS="/opt/host-freetype/lib/libfreetype.a -lm"
  unset CFLAGS CXXFLAGS
  ../configure \
    --enable-archs=x86_64 \
    --without-x \
    --without-gstreamer \
    --without-vulkan \
    --without-wayland
  make -j"$JOBS" __tooldeps__ nls/all
)

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
  --enable-wineandroid_drv=no \
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
  --without-pulse \
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
            "versionCode": 0,
            "description": f"Amphora Proton {version}, Android API35/16KB, commit {commit}",
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
WCP_NAME=$wcp_name
SHA256=$sha
SIZE=$size
EOF

echo "Wrote $OUTPUT_DIR/$wcp_name ($size bytes, sha256=$sha)"
