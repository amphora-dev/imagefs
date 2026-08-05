# Platform-agnostic package recipe. Not a BuildStream element.
# Edit this file, then run: python3 buildstream/sync-arch-elements.py
kind: autotools

description: libXrender 0.9.11 for Android/Bionic.

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
- filename: x11/libx11.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libXrender-0.9.11.tar.xz
  ref: bc53759a3a83d1ff702fb59641b3d2f7c56e05051fa0cfa93501166fa782dc24

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    host_alias=aarch64-linux-android
    --enable-shared
    --disable-static
    --enable-malloc0returnsnull
    xorg_cv_malloc0_returns_null=yes

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libXrender.so*' \
      -exec "$STRIP" {} +
