kind: meson

description: |
  FreeType 2.13.3 for Android/Bionic with target zlib, libpng and Brotli.

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
- filename: compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: compress/libpng.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: compress/brotli.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: freetype:freetype-2.13.3.tar.xz
  ref: 0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289

variables:
  meson-local: >-
    -Dbrotli=enabled
    -Dbzip2=disabled
    -Dharfbuzz=disabled
    -Dpng=enabled
    -Dzlib=enabled

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libfreetype.so*' \
      -exec "$STRIP" {} +
