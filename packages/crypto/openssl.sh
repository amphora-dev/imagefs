#!/usr/bin/env bash
# OpenSSL 3.4.1 — 自定义 Configure (参考 MiceWine packages/openssl)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="3.4.1"
PKG_NAME="openssl-$VER"
SRC_URL="https://github.com/openssl/openssl/releases/download/openssl-$VER/openssl-$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" openssl.tar.gz "$SRC_URL"
cd "$PKG_NAME"

export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$NDK_DIR}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$NDK_DIR}"

# 参考 MiceWine: android-aarch64 target, no-asm 避免汇编兼容问题
# OpenSSL 的 android-arm64 target 会自动检测 NDK 环境变量 ($CC, $CXX, $CFLAGS)
./Configure \
    android-arm64 \
    --prefix=$PREFIX \
    --libdir=lib \
    --openssldir=$PREFIX/etc/ssl \
    shared \
    no-asm \
    no-tests \
    no-unit-test \
    no-legacy \
    -D__ANDROID_API__=$ANDROID_API \
    -Wl,-rpath,/usr/lib

make -j$JOBS
make install_sw install_ssldirs

$STRIP "$PREFIX/lib/libssl.so" "$PREFIX/lib/libcrypto.so" 2>/dev/null || true

log "  OpenSSL $VER: $(ls $PREFIX/lib/lib{ssl,crypto}.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
