kind: autotools

description: libXi 1.8.2 for Android/Bionic.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libx11.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxext.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxfixes.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libXi-1.8.2.tar.xz
  ref: d0e0555e53d6e2114eabfa44226ba162d2708501a25e18d99cfb35c094c6c104

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    host_alias=x86_64-linux-android
    --enable-shared
    --disable-static
    --enable-malloc0returnsnull
    xorg_cv_malloc0_returns_null=yes

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libXi.so*' \
      -exec "$STRIP" {} +
