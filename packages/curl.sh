#!/usr/bin/env bash
# curl 8.11.1 — cmake (依赖 openssl, zlib)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="8.11.1"
PKG_NAME="curl-$VER"
SRC_URL="https://github.com/curl/curl/releases/download/curl-${VER//./_}/curl-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o curl.tar.xz && tar xf curl.tar.xz; }
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 参考 MiceWine: OpenSSL 已安装到 $PREFIX, 使用 cmake
# 禁用不需要的功能以减少依赖
cmake -DCMAKE_C_COMPILER=$CC -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DOPENSSL_ROOT_DIR=$PREFIX \
    -DOPENSSL_SSL_LIBRARY=$PREFIX/lib/libssl.so \
    -DOPENSSL_CRYPTO_LIBRARY=$PREFIX/lib/libcrypto.so \
    -DCURL_USE_OPENSSL=ON \
    -DCURL_USE_LIBSSH2=OFF \
    -DUSE_LIBIDN2=OFF \
    -DUSE_NGHTTP2=OFF \
    -DUSE_NGHTTP3=OFF \
    -DUSE_NGTCP2=OFF \
    -DUSE_QUICHE=OFF \
    -DCURL_BROTLI=OFF \
    -DCURL_ZLIB=ON \
    -DCURL_ZSTD=OFF \
    -DENABLE_ARES=OFF \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_CURL_EXE=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DCURL_ENABLE_LDAP=OFF \
    -DCURL_ENABLE_LDAPS=OFF ..
make -j$JOBS
make install
$STRIP "$PREFIX/lib/libcurl.so" "$PREFIX/bin/curl" 2>/dev/null || true

log "  curl $VER: $(ls $PREFIX/lib/libcurl.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
