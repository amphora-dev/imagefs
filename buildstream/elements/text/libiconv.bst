kind: autotools

description: |
  GNU libiconv 1.17 static target library for glib/gnutls builds.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: gnu:libiconv/libiconv-1.17.tar.gz
  ref: 8f74213b56238c85a50a5329f77e06198771e70dd9a739779f4c02f65d971313

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-static
    --disable-shared

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
