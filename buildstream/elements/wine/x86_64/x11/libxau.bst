kind: autotools

description: |
  libXau 1.0.12 for Android/Bionic.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libXau-1.0.12.tar.xz
  ref: 74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-shared
    --disable-static

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libXau.so*' \
      -exec "$STRIP" {} +
