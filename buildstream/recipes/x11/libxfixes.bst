# Platform-agnostic package recipe. Not a BuildStream element.
# Edit this file, then run: python3 buildstream/sync-arch-elements.py
kind: autotools

description: libXfixes 6.0.1 for Android/Bionic.

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
  url: xorg:lib/libXfixes-6.0.1.tar.xz
  ref: b695f93cd2499421ab02d22744458e650ccc88c1d4c8130d60200213abc02d58

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
    find "%{install-root}%{prefix}/lib" -type f -name 'libXfixes.so*' \
      -exec "$STRIP" {} +
