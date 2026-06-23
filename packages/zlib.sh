#!/usr/bin/env bash
# zlib 1.3.1 — 手动编译 (参考 MiceWine packages/zlib)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.3.1"
PKG_NAME="zlib-$VER"
SRC_URL="https://github.com/madler/zlib/releases/download/v$VER/zlib-$VER.tar.gz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o zlib.tar.gz && tar xzf zlib.tar.gz; }
cd "$PKG_NAME"

# 手动编译 (与 MiceWine 一致: 不用 configure, 直接 -fPIC)
OBJS=""
for s in adler32 crc32 deflate infback inffast inflate inftrees trees \
         zutil compress uncompr gzclose gzlib gzread gzwrite; do
    $CC -O3 -fPIC -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -D_FILE_OFFSET_BITS=64 -I. -c -o pic_${s}.o ${s}.c
    OBJS="$OBJS pic_${s}.o"
done

$CC -shared -Wl,-soname,libz.so.1 -O3 -DHAVE_HIDDEN -o libz.so.1.3.1 $OBJS
$STRIP libz.so.1.3.1

cp libz.so.1.3.1 "$PREFIX/lib/"
ln -sf libz.so.1.3.1 "$PREFIX/lib/libz.so.1"
ln -sf libz.so.1.3.1 "$PREFIX/lib/libz.so"
cp zlib.h zconf.h "$PREFIX/include/"

cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: zlib
Description: zlib compression library
Version: $VER
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF

log "  zlib $VER: libz.so.1.3.1"
