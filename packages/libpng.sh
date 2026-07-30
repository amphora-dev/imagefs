#!/usr/bin/env bash
# libpng — autotools so we keep the PNG16_0 ELF symbol version that freetype
# (and Box64 verneed) require.
#
# History:
#   cmake -DPNG_ARM_NEON=on + LDFLAGS=--allow-shlib-undefined shipped
#   libpng16.so with *undefined* png_*_neon symbols → Box64 failed
#   dlopen(libfreetype) → Wine "graphics driver is missing".
#   cmake -DPNG_ARM_NEON=off fixed neon but Android cmake disables the ld
#   version script, so PNG16_0 vanished and Box64 verneed still failed.
#   Autotools --enable-arm-neon=no emits PNG16_0, but Android libtool stamps
#   SONAME=libpng16.so while freetype NEEDED=libpng16.so.16.
#   Post-install used to prefer PREFIX/lib/libpng16.so.16.44.0 — on incremental
#   CI that path was a *stale cmake* artifact without PNG16_0, while the fresh
#   autotools build lived at libpng16.so. Assertion then failed wrongly.
#
# Fix: autotools + neon off; take the just-built .libs/*.so; wipe old PREFIX
# libpng*.so*; patchelf SONAME=libpng16.so.16; assert PNG16_0.
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.6.44"
PKG_NAME="libpng-$VER"
SRC_URL="https://download.sourceforge.net/libpng/libpng-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libpng.tar.xz "$SRC_URL"
cd "$PKG_NAME"

# Out-of-tree build keeps the source tree clean for incremental rebuilds.
rm -rf build_dir && mkdir build_dir && cd build_dir

# Do NOT pass --allow-shlib-undefined for this package.
PNG_LDFLAGS="$(echo "${LDFLAGS:-}" | sed -E 's/-Wl,--allow-shlib-undefined//g; s/-Wl,--undefined-version//g')"

../configure \
    --host="${ARCH}-linux-android" \
    host_alias="${ARCH}-linux-android" \
    --prefix="$PREFIX" \
    --libdir="$PREFIX/lib" \
    --enable-shared \
    --disable-static \
    --enable-arm-neon=no \
    CPPFLAGS="-I$PREFIX/include" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="-L$PREFIX/lib $PNG_LDFLAGS"

make -j"$JOBS"

# Prefer the just-linked shared object from the build tree — never a leftover
# under $PREFIX from a previous cmake/autotools layout.
real=""
for cand in \
    .libs/libpng16.so \
    .libs/libpng16.so.16 \
    .libs/libpng16.so.16.44 \
    .libs/libpng16.so.16.44.0 \
    .libs/libpng16.so."$VER"; do
    if [[ -f "$cand" && ! -L "$cand" ]]; then
        real="$cand"
        break
    fi
done
if [[ -z "$real" ]]; then
    error "libpng shared library not found in build_dir/.libs after make"
    ls -la .libs 2>/dev/null || true
    exit 1
fi

if ! readelf -V "$real" 2>/dev/null | grep -q 'PNG16_0'; then
    error "fresh libpng build missing PNG16_0 (HAVE_LD_VERSION_SCRIPT likely off)"
    readelf -V "$real" 2>/dev/null | head -40 || true
    grep -E 'version script|versioned symbols|HAVE_LD_VERSION' config.log 2>/dev/null | tail -20 || true
    exit 1
fi

# Drop stale PREFIX copies (cmake left libpng16.so.16.44.0 without PNG16_0).
rm -f "$PREFIX/lib"/libpng*.so*

make install

# Android libtool often stamps SONAME=libpng16.so. Force the classic layout
# freetype expects (NEEDED libpng16.so.16) and keep PNG16_0 from the verscript.
install -m 755 "$real" "$PREFIX/lib/libpng16.so.16.44.0"
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
    error "libpng SONAME is '$soname' (want libpng16.so.16)"
    exit 1
fi
if ! readelf -V "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null | grep -q 'PNG16_0'; then
    error "libpng missing PNG16_0 symbol version after install/patchelf/strip"
    exit 1
fi

log "  libpng $VER: $(ls "$PREFIX/lib"/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ') (SONAME=$soname, PNG16_0=yes)"
