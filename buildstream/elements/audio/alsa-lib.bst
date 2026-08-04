kind: autotools

description: |
  ALSA lib 1.2.13 with the minimal Winlator PCM/control plugin set.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: alsa:alsa-lib-1.2.13.tar.bz2
  ref: 8c4ff37553cbe89618e187e4c779f71a9bb2a8b27b91f87ed40987cc9233d8f6

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --host=aarch64-linux-android26
    --enable-shared
    --disable-static
    --with-alsa-ucm-confdir=no
    --with-alsa-ucm-prefix=no
    --with-tmpdir=/usr/tmp
    --with-pcm-plugins=hw,dmix,dsnoop,plug,route,softvol
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
