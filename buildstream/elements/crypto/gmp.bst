kind: autotools

description: |
  GMP 6.3.0 for Android/Bionic using portable C arithmetic.

  GMP runs build-time generators. CC_FOR_BUILD reuses the pinned NDK's
  multi-target Clang in x86_64-linux-gnu mode; target CC remains the API-26
  Android wrapper.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: base/host-sdk-autotools.bst
  type: build
- filename: base/host-compiler-headers.bst
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
  CC_FOR_BUILD: "%{ndk-toolchain}/bin/clang-21 --target=x86_64-linux-gnu --sysroot=/ -fuse-ld=lld"
  CPP_FOR_BUILD: "%{ndk-toolchain}/bin/clang-21 --target=x86_64-linux-gnu --sysroot=/ -E"

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libgmp.so*' \
      -exec "$STRIP" {} +
