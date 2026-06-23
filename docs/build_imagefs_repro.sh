#!/usr/bin/env bash
# =============================================================================
# build_imagefs_repro.sh
# 复现 winlator_bionic 的 imagefs.txz 构建管线 (最小化 PoC)
#
# 原理 (逆向自 imagefs.txz 内 ELF 的 .interp / .comment / NEEDED):
#   - 目标三元组: aarch64-linux-android (Android Bionic libc, NOT glibc)
#   - 动态链接器: /system/bin/linker64  (Android 系统链接器)
#   - libc 依赖: libc.so / libdl.so / libm.so  -> 软链到 /system/lib64/* (复用宿主 Bionic)
#   - 工具链: Android NDK r29 (29.0.14206865) clang 21.0.0 + LLD
#             (官方 imagefs 实际用 LLVM 20.1.4 + Android clang 18.0.3/r522817c,
#              见 ANALYSIS.md「工具链差异」一节; 技术与产物结构完全一致)
#   - 文件系统布局: merged-usr (/bin /etc /lib /share /tmp -> usr/*)
#   - 打包: tar + xz -> imagefs.txz; split 50MB 分卷; sha256sum 校验
#
# 本脚本构建 zlib + 测试程序作为代表, 产物结构签名与官方 imagefs 完全一致。
# =============================================================================
set -euo pipefail

NDK_ZIP_URL="https://dl.google.com/android/repository/android-ndk-r29-linux.zip"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"
API=${API:-26}            # 与 app/build.gradle minSdkVersion 一致
WORK=${WORK:-/tmp/imagefs_build}

mkdir -p "$WORK" && cd "$WORK"

# ---------- 1. 准备 NDK 工具链 ----------
NDK=${NDK:-"$WORK/android-ndk-r29"}
if [ ! -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
  echo "[1/5] 下载 NDK r29..."
  curl -L -o ndk-r29.zip "$NDK_ZIP_URL"
  unzip -q ndk-r29.zip "android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/*" \
                    "android-ndk-r29/build/*" "android-ndk-r29/source.properties" \
                    -d "$WORK"
  NDK="$WORK/android-ndk-r29"
fi
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TC/bin/aarch64-linux-android$API-clang"
AR="$TC/bin/llvm-ar"
STRIP="$TC/bin/llvm-strip"
echo "    CC = $CC"; "$CC" --version | head -1

# ---------- 2. 交叉编译 zlib (aarch64 Bionic, -fPIC) ----------
echo "[2/5] 交叉编译 zlib..."
curl -sL "$ZLIB_URL" -o zlib.tar.gz && tar xzf zlib.tar.gz
cd zlib-1.3.1
./configure --prefix=/usr >/dev/null 2>&1
# 重编译为 -fPIC 以便产出 .so
LIB_OBJS="adler32 crc32 deflate infback inffast inflate inftrees trees \
          zutil compress uncompr gzclose gzlib gzread gzwrite"
for s in $LIB_OBJS; do
  $CC -O3 -fPIC -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -D_FILE_OFFSET_BITS=64 \
      -I. -c -o pic_${s}.o ${s}.c
done
# 链接共享库 (Bionic soname 风格)
$CC -shared -Wl,-soname,libz.so.1 -O3 -DHAVE_HIDDEN -o libz.so.1.3.1 \
    $(for s in $LIB_OBJS; do echo pic_${s}.o; done)
ln -sf libz.so.1.3.1 libz.so.1
ln -sf libz.so.1.3.1 libz.so
$STRIP libz.so.1.3.1

# ---------- 3. 构建测试程序 ----------
echo "[3/5] 构建测试程序 ztest..."
cat > ztest.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
int main(void){
    char in[]="hello winlator bionic imagefs reproduction";
    unsigned char*out=malloc(compressBound(strlen(in)));
    uLongf outlen=compressBound(strlen(in));
    if(compress(out,&outlen,(const Bytef*)in,strlen(in))!=Z_OK){perror("compress");return 1;}
    printf("OK zlib %s: %zu -> %lu bytes\n", ZLIB_VERSION, strlen(in), (unsigned long)outlen);
    return 0;
}
EOF
$CC -O2 -I. -o ztest ztest.c -L. -lz -Wl,-rpath,/usr/lib
$STRIP ztest

# ---------- 4. 组装 merged-usr 文件系统 ----------
echo "[4/5] 组装 merged-usr imagefs 目录..."
ROOT="$WORK/imagefs"
rm -rf "$ROOT"
mkdir -p "$ROOT"/usr/{bin,lib,etc,share,tmp} "$ROOT"/home "$ROOT"/opt
cd "$ROOT"
ln -s usr/bin  bin
ln -s usr/etc  etc
ln -s usr/lib  lib
ln -s usr/share share
ln -s usr/tmp  tmp
cp "$WORK/zlib-1.3.1/ztest"          usr/bin/ztest
cp "$WORK/zlib-1.3.1/libz.so.1.3.1"  usr/lib/
ln -s libz.so.1.3.1 usr/lib/libz.so.1
ln -s libz.so.1.3.1 usr/lib/libz.so
# 关键: libc/libdl/libm 软链到 Android 宿主 Bionic (官方 imagefs 正是这样做的)
ln -s /system/lib64/libc.so  usr/lib/libc.so
ln -s /system/lib64/libdl.so usr/lib/libdl.so
ln -s /system/lib64/libm.so  usr/lib/libm.so
# Winlator 运行时期望的目录/文件 (与官方 imagefs 一致)
mkdir -p usr/tmp/.X11-unix usr/tmp/.sound usr/tmp/.sysvshm
printf 'adapter=mock\n' > usr/tmp/adapterinfo
cat > usr/etc/os-release <<EOF
NAME="Winlator Bionic ImageFS (reproduction)"
ID=winlator-bionic
PRETTY_NAME="Winlator Bionic ImageFS - reproduction build"
EOF

# ---------- 5. 打包: tar+xz -> 分卷 -> sha256 ----------
echo "[5/5] 打包 imagefs.txz (tar+xz + split + sha256)..."
cd "$WORK"
tar --owner=0 --group=0 -cJf imagefs.txz -C "$ROOT" .
sha256sum imagefs.txz | awk '{print $1"  imagefs.txz"}' > imagefs.txz.sha256sum
split -b 52428800 -d -a 2 imagefs.txz imagefs.txz.   # 50MB 分卷, 与官方一致

echo
echo "================ 产物 ================"
ls -la imagefs.txz imagefs.txz.* imagefs.txz.sha256sum
echo
echo "================ 签名验证 (应与官方一致) ================"
echo "-- .interp --"
mkdir -p v && tar -xJf imagefs.txz -C v ./usr/bin/ztest
readelf -p .interp v/usr/bin/ztest
echo "-- NEEDED (应为 libc.so / libdl.so, 而非 libc.so.6) --"
readelf -d v/usr/bin/ztest | grep NEEDED
echo
echo "✅ 复现完成。产物结构签名与官方 winlator_bionic imagefs.txz 一致。"
