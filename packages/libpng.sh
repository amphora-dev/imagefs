#!/usr/bin/env bash
# libpng — autotools（Android cmake 不生成 version script，会丢掉 PNG16_0）
# neon 关闭；从 .libs 取 SO；强制 SONAME=libpng16.so.16（freetype NEEDED）
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.6.44"
PKG_NAME="libpng-$VER"
SRC_URL="https://download.sourceforge.net/libpng/libpng-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libpng.tar.xz "$SRC_URL"
cd "$PKG_NAME"

rm -rf build_dir && mkdir build_dir && cd build_dir

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
    error "libpng missing PNG16_0 (version script not applied)"
    exit 1
fi

rm -f "$PREFIX/lib"/libpng*.so*
make install

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
    error "libpng missing PNG16_0 after install"
    exit 1
fi

log "  libpng $VER: $(ls "$PREFIX/lib"/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ') (SONAME=$soname, PNG16_0=yes)"
