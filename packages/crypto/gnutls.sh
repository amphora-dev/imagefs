#!/usr/bin/env bash
# GnuTLS 3.8.8 — autotools.
#
# Wine 的 bcrypt / secur32 在运行期 dlopen("libgnutls.so"), 所以它不出现在
# NEEDED 里但缺了就没有 TLS: 游戏登录 / 更新检查 / 任何 HTTPS 都会失败。
# 官方 imagefs 带 libgnutls.so + libgnutls-dane.so, 我们此前完全没有。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="3.8.8"
PKG_NAME="gnutls-$VER"
SRC_URL="https://www.gnupg.org/ftp/gcrypt/gnutls/v${VER%.*}/gnutls-$VER.tar.xz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" gnutls.tar.xz "$SRC_URL" \
    "https://mirrors.dotsrc.org/gcrypt/gnutls/v${VER%.*}/gnutls-$VER.tar.xz"
cd "$PKG_NAME"

export CFLAGS="$CFLAGS -I$PREFIX/include"
export LDFLAGS="$LDFLAGS -L$PREFIX/lib"
export NETTLE_CFLAGS="-I$PREFIX/include"
export NETTLE_LIBS="-L$PREFIX/lib -lnettle"
export HOGWEED_CFLAGS="-I$PREFIX/include"
export HOGWEED_LIBS="-L$PREFIX/lib -lhogweed -lnettle -lgmp"
export GMP_CFLAGS="-I$PREFIX/include"
export GMP_LIBS="-L$PREFIX/lib -lgmp"

# Bionic 缺 fmemopen 之外的若干 glibc 扩展, 交叉编译时这些 AC 探测无法运行
# 目标二进制, 用缓存变量直接给结论 (与本仓其他包同一手法)。
export gl_cv_func_fmemopen_works=yes

# --disable-libdane 省掉 libunbound 依赖 (DNSSEC 验证, Wine 不用)。注意 3.8.8 只有
# --disable-libdane, 没有 --disable-dane。
# --without-p11-kit 省掉 PKCS#11。--disable-doc/tests 省体积与构建时间。
# --with-included-libtasn1/unistring 避免再拉两个外部包。
./configure \
    --host=${ARCH}-linux-android${ANDROID_API} \
    --prefix=$PREFIX \
    --libdir=$PREFIX/lib \
    --enable-shared \
    --disable-static \
    --without-p11-kit \
    --without-tpm \
    --without-tpm2 \
    --disable-doc \
    --disable-tests \
    --disable-tools \
    --disable-nls \
    --disable-libdane \
    --with-included-libtasn1 \
    --with-included-unistring \
    --without-idn

# 只构建 gl (LGPL gnulib) + lib (libgnutls 本体), 用 SUBDIRS 覆盖顶层默认值。
#
# 原因: 顶层 Makefile.am 是
#   if ENABLE_TOOLS
#     SUBDIRS += src/gl src
#   else
#     SUBDIRS += src/gl        <-- 即使 --disable-tools 也照编
#   endif
# 而 src/gl 的 libgnu_gpl 编 parse-datetime.y 与 nstrftime.c, 需要 Bionic 没有的
# mktime_z / tzalloc / localtime_rz / tzfree, 于是报一串
# "call to undeclared function". 那部分只服务命令行工具 (certtool 等), 我们不装,
# 所以直接不编。libgnutls 只依赖 gl/。
#
# 必须用 `make -C <dir>` 而不是 `make SUBDIRS="gl lib"`: 后者会把 SUBDIRS 经
# MAKEFLAGS 递归传给子 make, 进入 gl/ 后子 make 又去找 gl/gl/, 报
#   /bin/bash: line 21: cd: gl: No such file or directory
make -j$JOBS -C gl
make -j$JOBS -C lib
make -C lib install

# gnutls.pc 出自 lib/Makefile.am 的 pkgconfig_DATA, 所以 lib/ 的 install 会带上它。
# 断言一下: 缺了它后续包的 pkg-config 探测会静默失败。
if [ ! -e "$PREFIX/lib/pkgconfig/gnutls.pc" ]; then
    error "  缺 gnutls.pc — 检查 lib/ 的 install 是否真的跑了"
    exit 1
fi

$STRIP "$PREFIX/lib/libgnutls.so" 2>/dev/null || true

log "  gnutls $VER: $(ls $PREFIX/lib/libgnutls*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
