#!/usr/bin/env bash
# libpng — follow MiceWine-Packages (autotools), not cmake+PNG_ARM_NEON=on.
#
# cmake -DPNG_ARM_NEON=on with our global LDFLAGS (--allow-shlib-undefined)
# produced libpng16.so that *references* png_riffle_palette_neon but never
# defines it. Box64 then fails dlopen(libfreetype) → Wine "cannot find FreeType"
# → explorer/winex11 never comes up (black screen).
#
# MiceWine uses plain ./configure for 1.6.43; we keep 1.6.44 but same path,
# and explicitly disable ARM NEON so the shared lib is self-contained.
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

# Drop --allow-shlib-undefined for this package so a missing neon object
# cannot silently ship (that was the black-screen footgun).
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
make install
"$STRIP" "$PREFIX/lib/libpng16.so" 2>/dev/null || true

# configure may install only libpng16.so (SONAME=libpng16.so). Freetype and
# other consumers NEEDED libpng16.so.16 — keep a real file + classic symlink.
if [ -f "$PREFIX/lib/libpng16.so" ] && [ ! -e "$PREFIX/lib/libpng16.so.16.44.0" ]; then
    cp -a "$PREFIX/lib/libpng16.so" "$PREFIX/lib/libpng16.so.16.44.0"
fi
ensure_soname_link "libpng16.so.16" "libpng16.so.16.44.0" "libpng16.so"
ln -sfn libpng16.so "$PREFIX/lib/libpng.so" 2>/dev/null || true

# Sanity: no unresolved neon helpers in the shipped shared lib.
if nm -D "$PREFIX/lib/libpng16.so" 2>/dev/null | grep -E ' U png_.*_neon$'; then
    error "libpng still has undefined NEON symbols — refusing to ship"
    nm -D "$PREFIX/lib/libpng16.so" | grep -E ' U png_.*_neon$'
    exit 1
fi

log "  libpng $VER: $(ls "$PREFIX/lib"/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
