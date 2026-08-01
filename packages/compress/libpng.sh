#!/usr/bin/env bash
# libpng — autotools（Android cmake 不生成 version script，会丢掉 PNG16_0）
# neon 关闭；从 .libs 取 SO；SONAME=libpng16.so.16（freetype NEEDED）
#
# 注意: setup-env 的全局 LDFLAGS 含 --undefined-version（给别的包用）。
# libtool 链接时会再读环境 LDFLAGS；该旗标会让 lld「接受」version-script
# 却不写出 PNG16_0。本脚本全程用干净 LDFLAGS，缺版本则强制重链。
#
# SONAME 只能在链接时定，**不要**事后 patchelf --set-soname:
# patchelf 会把 .dynstr 搬到一个新的 LOAD 段，而该段 p_vaddr 与 p_offset 不再
# 页对齐同余，设备上 (16 KB 页) 映射出来的字符串表与文件里的对不上。症状是
# 运行期 DT_STRTAB 读出乱码, 例如 `cannot find "_chunk_fn" from verneed[0]`,
# 连带 libfreetype 加载失败 → Wine 无字体 → 窗口全白。readelf 走 section
# header 看一切正常, 只有真机 dlopen 才暴露。MiceWine 的 libpng 就是普通
# autotools、不做任何 patchelf。ci/verify/wine-deps.sh 现在会断言段对齐。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.6.44"
PKG_NAME="libpng-$VER"
SRC_URL="https://download.sourceforge.net/libpng/libpng-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libpng.tar.xz "$SRC_URL"
cd "$PKG_NAME"

rm -rf build_dir && mkdir build_dir && cd build_dir

# 全程覆盖环境 LDFLAGS，避免 make/libtool 重新带上 --undefined-version
PNG_LDFLAGS="${LDFLAGS_BASE:--L$PREFIX/lib -Wl,-rpath,/usr/lib} -L$PREFIX/lib"
export LDFLAGS="$PNG_LDFLAGS"

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
    LDFLAGS="$PNG_LDFLAGS"

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

soname_of() {
    readelf -dW "$1" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}'
}

relink_libpng() {
    # 用同一批 .o 重链，soname 与 version script 一次给全（不事后 patch）。
    local out="$1"
    if [[ ! -f libpng.vers ]] || ! grep -q 'PNG16_0' libpng.vers; then
        error "libpng.vers missing or has no PNG16_0"
        head -20 libpng.vers 2>/dev/null || true
        exit 1
    fi
    mapfile -t objs < <(find .libs mips/.libs powerpc/.libs intel/.libs arm/.libs \
        -name '*.o' -type f 2>/dev/null | sort)
    if [[ ${#objs[@]} -eq 0 ]]; then
        error "no object files found for libpng re-link"
        exit 1
    fi
    "$CC" -shared -fPIC -O2 \
        -o "$out" \
        "${objs[@]}" \
        -L"$PREFIX/lib" -lz -lm \
        -Wl,--version-script="$PWD/libpng.vers" \
        -Wl,--no-undefined-version \
        -Wl,-soname,libpng16.so.16 \
        -Wl,-rpath,/usr/lib
}

has_png16() {
    # Prefer system readelf; NDK llvm-readelf also works but keep path stable.
    local re
    for re in /usr/bin/readelf readelf llvm-readelf; do
        if command -v "$re" >/dev/null 2>&1 || [[ -x "$re" ]]; then
            "$re" -V "$1" 2>/dev/null | grep -q 'PNG16_0' && return 0
        fi
    done
    return 1
}

# version-script 被静默丢掉, 或 libtool 给的 soname 不是 freetype NEEDED 的
# libpng16.so.16 —— 两种情况都用同一批 .o 重链修正。
if ! has_png16 "$real" || [[ "$(soname_of "$real")" != "libpng16.so.16" ]]; then
    warn "libpng needs re-link (PNG16_0 / SONAME): soname='$(soname_of "$real")'"
    relink_libpng "$real"
fi

if ! has_png16 "$real"; then
    error "libpng still missing PNG16_0 after re-link"
    /usr/bin/readelf -V "$real" 2>/dev/null | head -40 || true
    head -20 libpng.vers 2>/dev/null || true
    exit 1
fi

rm -f "$PREFIX/lib"/libpng*.so*
make install

install -m 755 "$real" "$PREFIX/lib/libpng16.so.16.44.0"
ln -sfn libpng16.so.16.44.0 "$PREFIX/lib/libpng16.so.16"
ln -sfn libpng16.so.16 "$PREFIX/lib/libpng16.so"
ln -sfn libpng16.so "$PREFIX/lib/libpng.so"
"$STRIP" "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null || true

if nm -D "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null | grep -E ' U png_.*_neon$'; then
    error "libpng still has undefined NEON symbols — refusing to ship"
    nm -D "$PREFIX/lib/libpng16.so.16.44.0" | grep -E ' U png_.*_neon$'
    exit 1
fi
soname="$(soname_of "$PREFIX/lib/libpng16.so.16.44.0")"
if [[ "$soname" != "libpng16.so.16" ]]; then
    error "libpng SONAME is '$soname' (want libpng16.so.16)"
    exit 1
fi
# LOAD 段的 p_vaddr 与 p_offset 必须页对齐同余, 否则设备上映射错位
# (patchelf 事后改 SONAME 就会破坏这点, 见文件头注释)。
while read -r seg_off seg_va; do
    [ -n "$seg_off" ] || continue
    if (( ((seg_va - seg_off) % 4096) != 0 )); then
        error "libpng LOAD segments are not page-congruent (会在设备上读出乱码字符串表)"
        readelf -lW "$PREFIX/lib/libpng16.so.16.44.0" | head -20
        exit 1
    fi
done < <(readelf -lW "$PREFIX/lib/libpng16.so.16.44.0" 2>/dev/null | awk '$1 == "LOAD" { print $2, $3 }')
if ! has_png16 "$PREFIX/lib/libpng16.so.16.44.0"; then
    error "libpng missing PNG16_0 after install"
    exit 1
fi

log "  libpng $VER: $(ls "$PREFIX/lib"/libpng*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ') (SONAME=$soname, PNG16_0=yes)"
