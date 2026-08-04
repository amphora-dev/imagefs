kind: meson

description: |
  Fontconfig 2.15.0 for Android/Bionic with imagefs runtime paths.

depends:
- filename: profiles/android-cross-files.bst
  junction: buildstream-sdk.bst
  type: build
  config:
    location: /opt/amphora-sdk/profiles
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: text/freetype.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: text/libexpat.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: compress/libpng.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: fontconfig:fontconfig-2.15.0.tar.xz
  ref: 63a0658d0e06e0fa886106452b58ef04f21f58202ea02a94c39de0d3335d7c0e

variables:
  sysconfdir: /usr/etc
  meson-local: >-
    -Ddefault-fonts-dirs=/usr/share/fonts
    -Dcache-dir=/usr/var/cache/fontconfig
    -Dtests=disabled
    -Ddoc=disabled

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libfontconfig.so*' \
      -exec "$STRIP" {} +
