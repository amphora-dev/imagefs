#!/usr/bin/env bash
# Shared Proton Wine WCP configure/env fragment.
# Sourced by build-proton-wcp.sh (CI/BuildStream) and dev-fast-build.sh (local).
# Keep these two paths flag-identical so local artifacts stay drop-in with CI WCP.
#
# Required env (CI always sets all; local may set via bst-artifacts/dev-env.sh):
#   ANDROID_NDK_HOME, LLVM_MINGW_ROOT, ANDROID_X86_64_SYSROOT, PULSE_DEV_DEB
# Optional:
#   PREFIX_PACK   — required for full WCP packaging
#   HOST_FREETYPE — default /opt/host-freetype (CI) or local checkout
#   WINE_PREFIX   — default /opt/wine
#   JOBS, SOURCE_DATE_EPOCH

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is required}"
: "${LLVM_MINGW_ROOT:?LLVM_MINGW_ROOT is required}"
: "${ANDROID_X86_64_SYSROOT:?ANDROID_X86_64_SYSROOT is required}"
: "${PULSE_DEV_DEB:?PULSE_DEV_DEB is required}"

PROTON_WCP_TARGET="${PROTON_WCP_TARGET:-x86_64-linux-android30}"
PROTON_WCP_NDK_TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
PROTON_WCP_TOOLCHAIN="${PROTON_WCP_NDK_TOOLCHAIN}/bin"
PROTON_WCP_DEPS="${ANDROID_X86_64_SYSROOT}/usr"
PROTON_WCP_HOST_FREETYPE="${HOST_FREETYPE:-/opt/host-freetype}"
PROTON_WCP_WINE_PREFIX="${WINE_PREFIX:-/opt/wine}"
PROTON_WCP_JOBS="${JOBS:-$(nproc)}"
PROTON_WCP_SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

# Extract Termux pulseaudio -dev tree once per process (idempotent).
proton_wcp_prepare_pulse() {
  local root="${PULSE_DEV_ROOT:-/tmp/termux-pulse-dev}"
  if [ ! -f "$root/data/data/com.termux/files/usr/include/pulse/pulseaudio.h" ]; then
    rm -rf "$root"
    mkdir -p "$root"
    dpkg-deb --fsys-tarfile "$PULSE_DEV_DEB" |
      tar --no-same-owner -xf - -C "$root"
  fi
  PULSE_DEV_PREFIX="$root/data/data/com.termux/files/usr"
  test -f "$PULSE_DEV_PREFIX/include/pulse/pulseaudio.h"
  test -f "$PULSE_DEV_PREFIX/include/pulse/version.h"
  test -f "$PULSE_DEV_PREFIX/lib/libpulse.so"
  grep -Eq '^#define PA_MAJOR +13$' "$PULSE_DEV_PREFIX/include/pulse/version.h"
  grep -Eq '^#define PA_PROTOCOL_VERSION +33$' "$PULSE_DEV_PREFIX/include/pulse/version.h"
  readelf -dW "$PULSE_DEV_PREFIX/lib/libpulse.so" |
    grep -q 'Shared library: \[libpulsecommon-13\.0\.so\]'
  export PULSE_DEV_PREFIX
}

# Export the Android/cross toolchain env used for the main Wine configure+make.
proton_wcp_export_cross_env() {
  local deps="$PROTON_WCP_DEPS"
  local toolchain="$PROTON_WCP_TOOLCHAIN"
  local target="$PROTON_WCP_TARGET"
  local ndk_sysroot="$PROTON_WCP_NDK_TOOLCHAIN/sysroot"

  : "${PULSE_DEV_PREFIX:?run proton_wcp_prepare_pulse first}"

  export PATH="$LLVM_MINGW_ROOT/bin:$toolchain:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export LD_LIBRARY_PATH="${PROTON_WCP_HOST_FREETYPE}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export CC="$toolchain/$target-clang"
  export AS="$CC"
  export CXX="$toolchain/$target-clang++"
  export AR="$toolchain/llvm-ar"
  export LD="$toolchain/ld.lld"
  export RANLIB="$toolchain/llvm-ranlib"
  export STRIP="$toolchain/llvm-strip"
  export DLLTOOL="$LLVM_MINGW_ROOT/bin/llvm-dlltool"
  export PKG_CONFIG_PATH=
  export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig:$deps/share/pkgconfig"
  export ACLOCAL_PATH="$deps/lib/aclocal:$deps/share/aclocal"
  export CPPFLAGS="-I$deps/include --sysroot=$ndk_sysroot"
  export CFLAGS="-march=x86-64 -mtune=generic -fPIC -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion"
  export CXXFLAGS="$CFLAGS"
  # NDK r29's Clang driver injects both --pack-dyn-relocs=relr and
  # --use-android-relr-tags for Android targets. Box64 understands standard
  # DT_RELR but not the Android-private aliases, so override both parts of that
  # driver default. Without the explicit --no-use switch, ntdll's free_areas
  # remains the raw 0xd6978 file address and Wine crashes in virtual_init.
  export LDFLAGS="-L$deps/lib -Wl,-rpath,/usr/lib -Wl,-z,max-page-size=16384 -Wl,--pack-dyn-relocs=relr -Wl,--no-use-android-relr-tags"
  export FREETYPE_CFLAGS="-I$deps/include/freetype2"
  export PULSE_CFLAGS="-I$PULSE_DEV_PREFIX/include"
  export PULSE_LIBS="-L$PULSE_DEV_PREFIX/lib -lpulse -pthread"
  export SDL2_CFLAGS="-I$deps/include/SDL2"
  export SDL2_LIBS="-L$deps/lib -lSDL2"
  export FONTCONFIG_LIBS="-L$deps/lib -lfontconfig -lfreetype -lexpat"
  export X_CFLAGS="-I$deps/include/X11"
  export X_LIBS=
  export GSTREAMER_CFLAGS="-I$deps/include/gstreamer-1.0 -I$deps/include/glib-2.0 -I$deps/lib/glib-2.0/include -I$deps/lib/gstreamer-1.0/include"
  export GSTREAMER_LIBS="-L$deps/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"
}

# Host (native) env for wine-tools / __tooldeps__.
proton_wcp_export_wine_tools_env() {
  local ft="$PROTON_WCP_HOST_FREETYPE"
  export CC=/usr/bin/gcc
  export CXX=/usr/bin/g++
  export AS=/usr/bin/as
  export AR=/usr/bin/ar
  export LD=/usr/bin/ld
  export RANLIB=/usr/bin/ranlib
  export STRIP=/usr/bin/strip
  unset DLLTOOL PKG_CONFIG_PATH ACLOCAL_PATH || true
  export PKG_CONFIG_LIBDIR="$ft/lib/pkgconfig"
  export CPPFLAGS="-I$ft/include/freetype2"
  export LDFLAGS="-L$ft/lib"
  export FREETYPE_CFLAGS="-I$ft/include/freetype2"
  export FREETYPE_LIBS="-L$ft/lib -lfreetype"
  unset PULSE_CFLAGS PULSE_LIBS || true
  unset CFLAGS CXXFLAGS || true
  export LD_LIBRARY_PATH="$ft/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

# Print exact ./configure args for wine-tools (host).
proton_wcp_wine_tools_configure_args() {
  cat <<'ARGS'
--enable-archs=x86_64
--without-x
--without-gstreamer
--without-pulse
--without-vulkan
--without-wayland
ARGS
}

# Print exact ./configure args for the Android cross build (identical to CI).
# $1 = path to wine-tools build dir (relative or absolute), default ./wine-tools
proton_wcp_cross_configure_args() {
  local wine_tools="${1:-./wine-tools}"
  local prefix="$PROTON_WCP_WINE_PREFIX"
  local target="$PROTON_WCP_TARGET"
  cat <<ARGS
--enable-archs=x86_64,i386
--host=$target
--prefix=$prefix
--bindir=$prefix/bin
--libdir=$prefix/lib
--exec-prefix=$prefix
--with-mingw=clang
--with-wine-tools=$wine_tools
--enable-win64
--disable-win16
--enable-nls
--disable-amd_ags_x64
--enable-wineandroid_drv=yes
--disable-tests
--with-alsa
--without-capi
--without-coreaudio
--without-cups
--without-dbus
--without-ffmpeg
--with-fontconfig
--with-freetype
--without-gcrypt
--without-gettext
--with-gettextpo=no
--without-gphoto
--with-gnutls
--without-gssapi
--with-gstreamer
--without-inotify
--without-krb5
--without-netapi
--without-opencl
--with-opengl
--without-oss
--without-pcap
--without-pcsclite
--without-piper
--with-pthread
--with-pulse
--without-sane
--with-sdl
--without-udev
--without-unwind
--without-usb
--without-v4l2
--without-vosk
--with-vulkan
--without-wayland
--without-xcomposite
--without-xfixes
--without-xinerama
--without-xrandr
--without-xrender
--without-xshape
--without-xshm
--without-xxf86vm
ARGS
}

# Stable stamp of configure flags (for rebuild-when-flags-change).
proton_wcp_configure_stamp() {
  local wine_tools="${1:-./wine-tools}"
  {
    echo "PROTON_COMMIT=${PROTON_COMMIT:-unknown}"
    echo "ANDROID_X86_64_SYSROOT=$ANDROID_X86_64_SYSROOT"
    echo "HOST_FREETYPE=$PROTON_WCP_HOST_FREETYPE"
    echo "PULSE_DEV_DEB=$PULSE_DEV_DEB"
    proton_wcp_cross_configure_args "$wine_tools"
  } | sha256sum | awk '{print $1}'
}

# Verify toolchain + deps presence (same checks as CI, PREFIX_PACK optional).
proton_wcp_require_tools() {
  local require_prefix_pack="${1:-0}"
  local tool target="$PROTON_WCP_TARGET" toolchain="$PROTON_WCP_TOOLCHAIN"
  for tool in autoconf autoreconf bison dpkg-deb file flex make meson patch pkg-config \
              python3 readelf tar zstd; do
    command -v "$tool" >/dev/null || {
      echo "missing build tool: $tool" >&2
      return 1
    }
  done
  for tool in \
    "$toolchain/$target-clang" \
    "$toolchain/$target-clang++" \
    "$toolchain/llvm-strip" \
    "$LLVM_MINGW_ROOT/bin/llvm-dlltool" \
    "$LLVM_MINGW_ROOT/bin/x86_64-w64-mingw32-clang" \
    "$LLVM_MINGW_ROOT/bin/i686-w64-mingw32-clang"; do
    test -x "$tool" || {
      echo "missing compiler: $tool" >&2
      return 1
    }
  done
  test -d "$PROTON_WCP_DEPS/lib" || {
    echo "missing sysroot libdir: $PROTON_WCP_DEPS/lib" >&2
    return 1
  }
  test -d "$PROTON_WCP_DEPS/include" || {
    echo "missing sysroot include: $PROTON_WCP_DEPS/include" >&2
    return 1
  }
  test -f "$PULSE_DEV_DEB" || {
    echo "missing PULSE_DEV_DEB: $PULSE_DEV_DEB" >&2
    return 1
  }
  if [ "$require_prefix_pack" = 1 ]; then
    : "${PREFIX_PACK:?PREFIX_PACK required for WCP packaging}"
    test -f "$PREFIX_PACK" || {
      echo "missing PREFIX_PACK: $PREFIX_PACK" >&2
      return 1
    }
  fi
}

# Pack a CI-identical WCP from an installed tree + prefixPack.
# Args: package_root output_dir proton_commit [version_file]
# package_root must already contain bin/ lib/ share/ prefixPack.txz layout.
proton_wcp_write_profile_and_pack() {
  local package_root="$1"
  local output_dir="$2"
  local proton_commit="$3"
  local version_file="${4:-VERSION}"
  local version commit_short full_version wcp_name sha size

  test -f "$version_file"
  test -f "$package_root/prefixPack.txz"
  version="$(awk '/Wine version/{print $3; exit}' "$version_file")"
  test -n "$version"
  commit_short="${proton_commit:0:9}"
  full_version="${version}-${commit_short}-x86_64"
  wcp_name="Proton-${full_version}.wcp"

  python3 - "$package_root/profile.json" "$full_version" "$proton_commit" <<'PY'
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

  mkdir -p "$output_dir"
  tar \
    --sort=name \
    --mtime="@${PROTON_WCP_SOURCE_DATE_EPOCH}" \
    --clamp-mtime \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -C "$package_root" \
    -cf - bin lib share prefixPack.txz profile.json |
    zstd -T0 -19 -o "$output_dir/$wcp_name"
  (
    cd "$output_dir"
    sha256sum "$wcp_name" > "$wcp_name.sha256sum"
  )
  sha="$(awk '{print $1}' "$output_dir/$wcp_name.sha256sum")"
  size="$(stat -c%s "$output_dir/$wcp_name")"
  cat > "$output_dir/proton-wine-wcp.env" <<EOF_ENV
FULL_VERSION=$full_version
COMMIT_FULL=$proton_commit
COMMIT_SHORT=$commit_short
VER_CODE=0
WCP_NAME=$wcp_name
SHA256=$sha
SIZE=$size
EOF_ENV
  echo "Wrote $output_dir/$wcp_name ($size bytes, sha256=$sha)"
}

# Strip ELF/PE under package_root the same way CI does.
proton_wcp_strip_package() {
  local package_root="$1"
  local toolchain="$PROTON_WCP_TOOLCHAIN"
  find "$package_root/lib/wine" "$package_root/bin" -type f -print0 |
    while IFS= read -r -d '' binary; do
      case "$(file -b "$binary")" in
        *ELF*) "$toolchain/llvm-strip" --strip-unneeded "$binary" 2>/dev/null || true ;;
        *PE32*) "$LLVM_MINGW_ROOT/bin/llvm-strip" --strip-unneeded "$binary" 2>/dev/null || true ;;
      esac
    done
}

# Assemble package_root from a DESTDIR install (CI layout).
proton_wcp_assemble_from_destdir() {
  local destdir="$1"
  local package_root="$2"
  local prefix_pack="$3"
  local installed="$destdir$PROTON_WCP_WINE_PREFIX"

  test -d "$installed/lib/wine/x86_64-unix"
  test -d "$installed/lib/wine/x86_64-windows"
  test -d "$installed/lib/wine/i386-windows"
  test -f "$installed/lib/wine/x86_64-unix/winepulse.so"
  test -f "$installed/lib/wine/x86_64-windows/winepulse.drv"
  test -f "$installed/lib/wine/i386-windows/winepulse.drv"
  test -f "$installed/lib/wine/x86_64-unix/wineandroid.so"
  test -f "$installed/lib/wine/x86_64-windows/wineandroid.drv"

  rm -rf "$package_root"
  mkdir -p "$package_root/bin" "$package_root/lib" "$package_root/share"
  cp -a "$installed/bin/." "$package_root/bin/"
  cp -a "$installed/lib/wine" "$package_root/lib/"
  cp -a "$installed/share/wine" "$package_root/share/"
  ln -sfn ../lib/wine/x86_64-unix/wine "$package_root/bin/wine"
  ln -sfn ../lib/wine/x86_64-unix/wine-preloader "$package_root/bin/wine-preloader"
  cp "$prefix_pack" "$package_root/prefixPack.txz"
}
