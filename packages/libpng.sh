#!/usr/bin/env bash
# libpng — follow MiceWine-Packages intent, with Android-safe SONAME.
#
# History:
#   cmake -DPNG_ARM_NEON=on + LDFLAGS=--allow-shlib-undefined shipped
#   libpng16.so with *undefined* png_*_neon symbols → Box64 failed
#   dlopen(libfreetype) → Wine "graphics driver is missing" (black screen).
#   Autotools --enable-arm-neon=no fixed neon, but Android libtool emitted
#   SONAME=libpng16.so while freetype NEEDED=libpng16.so.16 → Box64 verneed
#   still failed.
#
# Fix: cmake + PNG_ARM_NEON=off (no neon refs), force SONAME libpng16.so.16,
# install classic libpng16.so.16.44.0 + symlink layout.
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.6.44"
PKG_NAME="libpng-$VER"
SRC_URL="https://download.sourceforge.net/libpng/libpng-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libpng.tar.xz "$SRC_URL"
cd "$PKG_NAME"

rm -rf build_dir && mkdir build_dir && cd build_dir

# Do NOT pass --allow-shlib-undefined for this package.
PNG_LDFLAGS="$(echo "${LDFLAGS:-}" | sed -E 's/-Wl,--allow-shlib-undefined//g; s/-Wl,--undefined-version//g')"
PNG_LDFLAGS="$PNG_LDFLAGS -Wl,-soname,libpng16.so.16"

cmake \
    -DCMAKE_SYSTEM_NAME=Android \
    -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
    -DCMAKE_ANDROID_NDK="${NDK_DIR:-$CACHE_DIR/android-ndk-$NDK_VERSION}" \
    -DCMAKE_ANDROID_API="$ANDROID_API" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_AR="$AR" \
    -DCMAKE_STRIP="$STRIP" \
    -DCMAKE_RANLIB="$RANLIB" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib $PNG_LDFLAGS" \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DZLIB_ROOT="$PREFIX" \
    -DZLIB_INCLUDE_DIR="$PREFIX/include" \
    -DZLIB_LIBRARY="$PREFIX/lib/libz.so" \
    -DPNG_SHARED=ON \
    -DPNG_STATIC=OFF \
    -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF \
    -DPNG_ARM_NEON=off \
    ..

make -j"$JOBS"

# Headers / pkg-config from cmake install first, then force the versioned
# shared-lib layout freetype expects (NEEDED libpng16.so.16). Android cmake
# often stamps SONAME=libpng16.so; patchelf corrects it.
make install
install -m 755 libpng16.so "$PREFIX/lib/libpng16.so.16.44.0"
if ! command -v patchelf >/dev/null 2>&1; then
    error "patchelf required to set libpng SONAME=libpng16.so.16"
    exit 1
fi
patchelf --set-soname libpng16.so.16 "$PREFIX/lib/libpng16.so.16.44.0"
ln -sfn libpng16.so.16.44.0 "$PREFIX/lib/libpng16.so.16"
ln -sfn libpng16.so.16 "$PREFIX/lib/libpng16.so"
ln -sfn libpng16.so "$PREFIX/lib/libpng.so"
"$STRIP" "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null || true

if nm -D "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null | grep -E ' U png_.*_neon$'; then
    error "libpng still has undefined NEON symbols — refusing to ship"
    nm -D "$PREFIX/lib/libpng16.so.16.44.0" | grep -E ' U png_.*_neon$'
    exit 1
fi
soname="$(readelf -d "$PREFIX/lib/libpng16.so.16.44.0" | awk '/SONAME/ {print $5}' | tr -d '[]')"
if [[ "$soname" != "libpng16.so.16" ]]; then
    error "libpng SONAME is '$soname' (want libpng16.so.16) — install patchelf in CI image"
    exit 1
fi

log "  libpng $VER: $(ls "$PREFIX/lib"/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ') (SONAME=$soname)"
