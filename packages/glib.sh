#!/usr/bin/env bash
# glib 2.82.4 — meson (参考 MiceWine packages/glib)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.82.4"
PKG_NAME="glib-$VER"
SRC_URL="https://download.gnome.org/sources/glib/${VER%.*}/glib-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" glib.tar.xz "$SRC_URL"
cd "$PKG_NAME"

# 修补: 交叉编译时 frexpl()/frexp() 运行时检查失败 (无法在 x86_64 运行 ARM64 二进制)
# 参考 MiceWine: 直接跳过 gnulib 的 frexpl/frexp 检查
GNULIB_MB="glib/gnulib/meson.build"
if [ -f "$GNULIB_MB" ] && grep -q "frexpl.*missing or broken" "$GNULIB_MB"; then
    # 注释掉 error 行 (frexp 和 frexpl)
    sed -i "/error.*frexp.*missing or broken/s/^/# /" "$GNULIB_MB"
    # 强制设置 works = true
    sed -i "/gl_cv_func_frexpl_works = false/s/^.*$/  gl_cv_func_frexpl_works = true/" "$GNULIB_MB"
    sed -i "/gl_cv_func_frexp_works = false/s/^.*$/  gl_cv_func_frexp_works = true/" "$GNULIB_MB"
    log "  已修补 gnulib frexpl/frexp 检查"
fi

mkdir -p build_dir && cd build_dir

# 参考 MiceWine: -Dintrospection=disabled -Dlibmount=disabled -Dselinux=disabled
# glib 需要 libiconv.a (静态)
export LDFLAGS="$LDFLAGS -L$PREFIX/lib -l:libiconv.a"

meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Dintrospection=disabled \
    -Druntime_dir=$PREFIX/var/run \
    -Dlibmount=disabled \
    -Dman-pages=disabled \
    -Dtests=false \
    -Dselinux=disabled \
    -Dlibelf=disabled ..
ninja -j$JOBS
ninja install
$STRIP "$PREFIX/lib/libglib-2.0.so" "$PREFIX/lib/libgobject-2.0.so" \
       "$PREFIX/lib/libgio-2.0.so" "$PREFIX/lib/libgmodule-2.0.so" \
       "$PREFIX/lib/libgthread-2.0.so" 2>/dev/null || true

log "  glib $VER: $(ls $PREFIX/lib/libg*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
