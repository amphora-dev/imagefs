#!/usr/bin/env bash
# alsa-android-aserver — ALSA PCM 插件 (Android 音频服务器)
# 来源: winlator/audio_plugin/module_pcm_android_aserver.c
# 功能: 通过 Unix socket 连接 Android 音频服务器, 实现 ALSA → Android 音频路由
# 依赖: alsa-lib
# 这是 winlator bionic 的关键音频组件 (替代 PulseAudio 路径)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

WINLATOR_DIR="${WINLATOR_DIR:-/workspace/winlator}"
SRC_FILE="$WINLATOR_DIR/audio_plugin/module_pcm_android_aserver.c"

if [ ! -f "$SRC_FILE" ]; then
    error "audio_plugin source not found: $SRC_FILE"
    error "Set WINLATOR_DIR to the winlator project root"
    exit 1
fi

# 编译 ALSA 插件
$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -o "$PREFIX/lib/asound_module_pcm_android_aserver.so" \
    "$SRC_FILE" \
    -L"$PREFIX/lib" -lasound \
    -Wl,-soname,asound_module_pcm_android_aserver.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/asound_module_pcm_android_aserver.so" 2>/dev/null || true

# 安装 ALSA 配置文件
mkdir -p "$ROOTFS/etc/alsa/conf.d"
cp -f "$WINLATOR_DIR/audio_plugin/android_aserver.conf" "$ROOTFS/etc/alsa/conf.d/"
cp -f "$WINLATOR_DIR/audio_plugin/alsa.conf" "$ROOTFS/etc/alsa/"

log "  alsa-android-aserver: plugin + config installed"
