kind: autotools

description: libXxf86vm 1.1.6 for Android/Bionic.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- filename: x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: x11/libx11.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: x11/libxext.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libXxf86vm-1.1.6.tar.xz
  ref: 96af414c73ce1d5449ad04be7f9f27fa8330f844b6dda843ef22e3e1befb3ee3

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
    find "%{install-root}%{prefix}/lib" -type f -name 'libXxf86vm.so*' \
      -exec "$STRIP" {} +
