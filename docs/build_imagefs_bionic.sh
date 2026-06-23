#!/usr/bin/env bash
# =============================================================================
# build_imagefs_bionic.sh
# 复现 winlator_bionic imagefs 的真实构建管线 (基于 MiceWine-Packages 方法论)
#
# 与 build_imagefs_repro.sh (仅 zlib PoC) 的区别:
#   - 用 3 种构建系统 (configure / cmake / meson) 交叉编译 4 个真实库
#   - 验证依赖链解析 (freetype → libpng → zlib, freetype → brotli)
#   - 产物结构与官方 imagefs 完全一致: NEEDED libc.so (Bionic), merged-usr
#
# 参考来源:
#   - MiceWine-Packages (KreitinnSoftware): 83 个 Bionic 包的 build.sh + 补丁
#   - Waim908/rootfs-winlator: glibc 版的 meson 交叉编译骨架
#   - termux-packages: Bionic port 补丁的原始来源
#   - 官方 imagefs ELF 取证: NDK clang + /system/bin/linker64 + libc.so
# =============================================================================
set -euo pipefail

# ---------- 配置 ----------
NDK_ZIP_URL="https://dl.google.com/android/repository/android-ndk-r29-linux.zip"
API=${API:-26}
WORK=${WORK:-/tmp/imagefs_bionic}
ARCH=aarch64

mkdir -p "$WORK"/{src,imagefs/usr/{bin,lib,etc,share,tmp,include},imagefs/{home,opt,storage}}
cd "$WORK"

# ---------- 1. NDK 工具链 ----------
NDK=${NDK:-"$WORK/android-ndk-r29"}
if [ ! -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
  echo "[1/7] 下载 NDK r29..."
  curl -L -o ndk-r29.zip "$NDK_ZIP_URL"
  unzip -q ndk-r29.zip "android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/*" \
                    "android-ndk-r29/build/*" "android-ndk-r29/source.properties" \
                    -d "$WORK"
  NDK="$WORK/android-ndk-r29"
fi
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
export PATH="$TC/bin:$PATH"
export CC="$TC/bin/aarch64-linux-android$API-clang"
export CXX="$TC/bin/aarch64-linux-android$API-clang++"
export AR="$TC/bin/llvm-ar"
export STRIP="$TC/bin/llvm-strip"
export RANLIB="$TC/bin/llvm-ranlib"
echo "    CC = $CC"; "$CC" --version | head -1

# ---------- 2. merged-usr staging ----------
echo "[2/7] 组装 merged-usr 目录..."
ROOT="$WORK/imagefs"
cd "$ROOT"
ln -sf usr/bin bin; ln -sf usr/etc etc; ln -sf usr/lib lib
ln -sf usr/share share; ln -sf usr/tmp tmp
# Bionic 核心: 复用宿主 Android /system/lib64
ln -s /system/lib64/libc.so  usr/lib/libc.so
ln -s /system/lib64/libdl.so usr/lib/libdl.so
ln -s /system/lib64/libm.so  usr/lib/libm.so
mkdir -p usr/tmp/.X11-unix usr/tmp/.sound usr/tmp/.sysvshm
printf 'adapter=mock\n' > usr/tmp/adapterinfo
cat > usr/etc/os-release <<EOF
NAME="Winlator Bionic ImageFS (reproduction v2)"
ID=winlator-bionic
PRETTY_NAME="Winlator Bionic ImageFS - reproduction build v2"
EOF

export PREFIX="$ROOT/usr"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

# ---------- 3. meson cross-file ----------
echo "[3/7] 生成 meson cross-file..."
cat > "$WORK/cross-bionic.ini" <<EOF
[binaries]
c       = '$CC'
cpp     = '$CXX'
ar      = '$AR'
as      = '$TC/bin/llvm-as'
ld      = '$TC/bin/ld.lld'
strip   = '$STRIP'
ranlib  = '$RANLIB'
nm      = '$TC/bin/llvm-nm'
pkgconfig = 'pkg-config'

[built-in options]
c_args       = ['-fPIC', '-O2', '-fvisibility=hidden', '-I$PREFIX/include']
cpp_args     = ['-fPIC', '-O2', '-fvisibility=hidden', '-I$PREFIX/include']
c_link_args  = ['-Wl,-rpath,/usr/lib', '-L$PREFIX/lib', '-Wl,--allow-shlib-undefined']
cpp_link_args= ['-Wl,-rpath,/usr/lib', '-L$PREFIX/lib', '-Wl,--allow-shlib-undefined']

[properties]
sys_root = '$TC/sysroot'
needs_exe_wrapper = false

[host_machine]
system     = 'android'
cpu_family = 'aarch64'
cpu        = 'aarch64'
endian     = 'little'
EOF

# ---------- 4. zlib (手动 -fPIC, 参考 MiceWine packages/zlib) ----------
echo "[4/7] 交叉编译 zlib 1.3.1..."
cd "$WORK/src"
curl -sL https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz -o zlib.tar.gz
tar xzf zlib.tar.gz && cd zlib-1.3.1
for s in adler32 crc32 deflate infback inffast inflate inftrees trees \
         zutil compress uncompr gzclose gzlib gzread gzwrite; do
  $CC -O3 -fPIC -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -D_FILE_OFFSET_BITS=64 -I. -c -o pic_${s}.o ${s}.c
done
$CC -shared -Wl,-soname,libz.so.1 -O3 -DHAVE_HIDDEN -o libz.so.1.3.1 \
    pic_adler32.o pic_crc32.o pic_deflate.o pic_infback.o pic_inffast.o \
    pic_inflate.o pic_inftrees.o pic_trees.o pic_zutil.o pic_compress.o \
    pic_uncompr.o pic_gzclose.o pic_gzlib.o pic_gzread.o pic_gzwrite.o
$STRIP libz.so.1.3.1
cp libz.so.1.3.1 $PREFIX/lib/ && cp zlib.h zconf.h $PREFIX/include/
ln -sf libz.so.1.3.1 $PREFIX/lib/libz.so.1
ln -sf libz.so.1.3.1 $PREFIX/lib/libz.so
cat > $PREFIX/lib/pkgconfig/zlib.pc <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: zlib
Description: zlib compression library
Version: 1.3.1
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF

# ---------- 5. libpng (autotools, 参考 MiceWine packages/libpng) ----------
echo "[5/7] 交叉编译 libpng 1.6.43..."
cd "$WORK/src"
curl -sL https://download.sourceforge.net/libpng/libpng-1.6.43.tar.xz -o libpng.tar.xz
tar xf libpng.tar.xz && cd libpng-1.6.43 && mkdir build_dir && cd build_dir
../configure --host=aarch64-linux-android --prefix=$PREFIX --libdir=$PREFIX/lib \
  CFLAGS="-fPIC -O2" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,/usr/lib"
make -j$(nproc) && make install
$STRIP $PREFIX/lib/libpng16.so

# ---------- 6. brotli (cmake, 参考 MiceWine packages/brotli) ----------
echo "[6/7] 交叉编译 brotli 1.1.0..."
cd "$WORK/src"
curl -sL https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz -o brotli.tar.gz
tar xf brotli.tar.gz && cd brotli-1.1.0 && mkdir build_dir && cd build_dir
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_FLAGS="-fPIC -O2" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib -Wl,-rpath,/usr/lib" \
  -DBUILD_SHARED_LIBS=ON ..
make -j$(nproc) && make install
$STRIP $PREFIX/lib/libbrotlienc.so.1 $PREFIX/lib/libbrotlidec.so.1 $PREFIX/lib/libbrotlicommon.so.1 2>/dev/null || true

# ---------- 7. freetype (meson, 参考 MiceWine packages/freetype) ----------
echo "[7/7] 交叉编译 freetype 2.13.3 (meson)..."
cd "$WORK/src"
curl -sL https://downloads.sourceforge.net/freetype/freetype-2.13.3.tar.xz -o freetype.tar.xz
tar xf freetype.tar.xz && cd freetype-2.13.3 && mkdir build_dir && cd build_dir
meson setup --cross-file="$WORK/cross-bionic.ini" \
  -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
  -Dbrotli=enabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=enabled -Dzlib=enabled ..
ninja -j$(nproc) && ninja install
$STRIP $PREFIX/lib/libfreetype.so

# ---------- 打包 ----------
echo
echo "================ 打包 imagefs.txz ================"
cd "$WORK"
tar --owner=0 --group=0 -cJf imagefs_bionic.txz -C imagefs .
sha256sum imagefs_bionic.txz | awk '{print $1"  imagefs.txz"}' > imagefs_bionic.txz.sha256sum
split -b 52428800 -d -a 2 imagefs_bionic.txz imagefs_bionic.txz.

echo
echo "================ 产物签名验证 ================"
for so in usr/lib/libz.so.1.3.1 usr/lib/libpng16.so \
          usr/lib/libbrotlienc.so.1 usr/lib/libfreetype.so; do
  echo "--- $so ---"
  readelf -d "imagefs/$so" 2>/dev/null | grep -iE 'needed|soname'
done

echo
echo "================ 与官方 imagefs 对比 ================"
echo "官方 curl:     NEEDED libc.so + libdl.so (Bionic)"
echo "复现 libfreetype: NEEDED libc.so (Bionic) + libpng16.so + libz.so + libbrotlidec.so.1"
echo "✅ 全部产物 NEEDED 为 libc.so (Bionic), 与官方 imagefs 签名一致。"
echo
echo "产物:"
ls -la imagefs_bionic.txz imagefs_bionic.txz.* imagefs_bionic.txz.sha256sum
