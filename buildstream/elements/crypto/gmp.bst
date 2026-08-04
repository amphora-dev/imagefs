kind: autotools

description: |
  GMP 6.3.0 for Android/Bionic using portable C arithmetic.

  Build-time generators use the pinned host SDK GCC. Target sources use the
  Android NDK API-26 Clang wrapper; the two compiler roles never overlap.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: gnu:gmp/gmp-6.3.0.tar.xz
  ref: a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --host=aarch64-linux-android26
    --build=x86_64-pc-linux-gnu
    --enable-shared
    --disable-static
    --disable-assembly

environment:
  CC_FOR_BUILD: /usr/bin/gcc
  CPP_FOR_BUILD: /usr/bin/cpp

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libgmp.so*' \
      -exec "$STRIP" {} +
