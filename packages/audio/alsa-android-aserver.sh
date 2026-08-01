#!/usr/bin/env bash
# alsa-android-aserver — ALSA PCM 插件 (Android 音频服务器)
# 源码: vendor/winlator-bionic/audio_plugin/
# 依赖: alsa-lib
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VENDOR="$(cd "$(dirname "$0")/../../vendor/winlator-bionic/audio_plugin" && pwd)"
SRC_FILE="$VENDOR/module_pcm_android_aserver.c"

if [ ! -f "$SRC_FILE" ]; then
    error "audio_plugin source not found: $SRC_FILE"
    exit 1
fi

$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -o "$PREFIX/lib/asound_module_pcm_android_aserver.so" \
    "$SRC_FILE" \
    -L"$PREFIX/lib" -lasound \
    -Wl,-soname,asound_module_pcm_android_aserver.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/asound_module_pcm_android_aserver.so" 2>/dev/null || true

mkdir -p "$ROOTFS/etc/alsa/conf.d"
cp -f "$VENDOR/android_aserver.conf" "$ROOTFS/etc/alsa/conf.d/"
cp -f "$VENDOR/alsa.conf" "$ROOTFS/etc/alsa/"

log "  alsa-android-aserver: plugin + config installed"
