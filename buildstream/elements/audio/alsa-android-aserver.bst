kind: manual

description: |
  Winlator Android audio-server ALSA PCM plugin and runtime configuration.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- filename: audio/alsa-lib.bst
  type: build
  config:
    location: /opt/android-sysroot

sources:
- kind: local
  path: vendor/winlator-bionic/audio_plugin
  directory: source

config:
  build-commands:
  - |
    "$CC" -fPIC -O2 -shared \
      -I/opt/android-sysroot/usr/include \
      -o asound_module_pcm_android_aserver.so \
      source/module_pcm_android_aserver.c \
      -L/opt/android-sysroot/usr/lib -lasound \
      -Wl,-soname,asound_module_pcm_android_aserver.so \
      -Wl,-rpath,/usr/lib
    "$STRIP" asound_module_pcm_android_aserver.so

  install-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    plugindir="$libdir/alsa-lib"
    mkdir -p "$plugindir" "%{install-root}/etc/alsa/conf.d"
    install -m 0755 asound_module_pcm_android_aserver.so "$libdir/"
    ln -s ../asound_module_pcm_android_aserver.so \
      "$plugindir/libasound_module_pcm_android_aserver.so"
    ln -s ../asound_module_pcm_android_aserver.so \
      "$plugindir/asound_module_pcm_android_aserver.so"
    install -m 0644 source/android_aserver.conf \
      "%{install-root}/etc/alsa/conf.d/"
    install -m 0644 source/alsa.conf "%{install-root}/etc/alsa/"

  strip-commands: []
