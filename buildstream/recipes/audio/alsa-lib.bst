# Platform-agnostic package recipe. Not a BuildStream element.
# Edit this file, then run: python3 buildstream/sync-arch-elements.py
kind: autotools

description: |
  ALSA lib 1.2.13 with the minimal Winlator PCM/control plugin set.

  pcm-plugins must include ioplug (pulls in extplug): android_aserver is an
  external PCM plugin that calls snd_pcm_ioplug_create. Without ioplug in the
  build, those symbols are absent from libasound and dlopen of the plugin fails
  with "cannot locate symbol snd_pcm_ioplug_create".

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: alsa:alsa-lib-1.2.13.tar.bz2
  ref: 8c4ff37553cbe89618e187e4c779f71a9bb2a8b27b91f87ed40987cc9233d8f6

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --host=%{target-triple}
    --enable-shared
    --disable-static
    --with-alsa-ucm-confdir=no
    --with-alsa-ucm-prefix=no
    --with-tmpdir=/usr/tmp
    --with-pcm-plugins=hw,dmix,dsnoop,plug,route,softvol,ioplug
    --with-ctl-plugins=hw

environment:
  PYTHON: ":"
  LDFLAGS: "-L/opt/android-sysroot/usr/lib -Wl,-rpath,/usr/lib -Wl,--allow-shlib-undefined -Wl,--undefined-version"

config:
  strip-commands:
  - |
    set -eu
    includedir="%{install-root}%{prefix}/include/alsa"
    for header in pcm_external.h pcm_ioplug.h pcm_extplug.h pcm_rate.h; do
      if [ -f "%{conf-root}/include/$header" ]; then
        install -m 0644 "%{conf-root}/include/$header" "$includedir/$header"
      fi
    done
    libdir="%{install-root}%{prefix}/lib"
    if [ -e "$libdir/libasound.so" ] && [ ! -e "$libdir/libasound.so.2" ]; then
      ln -s libasound.so "$libdir/libasound.so.2"
    fi
    find "%{install-root}" -type f -name '*.la' -delete
    find "$libdir" -type f \
      \( -name 'libasound.so*' -o -name 'libatopology.so*' \) \
      -exec "$STRIP" {} +
