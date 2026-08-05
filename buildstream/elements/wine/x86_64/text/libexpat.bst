kind: cmake

description: |
  Expat 2.6.4 shared library for Android/Bionic.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: expat:R_2_6_4/expat-2.6.4.tar.bz2
  ref: 8dc480b796163d4436e6f1352e71800a774f73dbae213f1860b60607d2a83ada

variables:
  target-triple: x86_64-linux-android35
  cmake-local: >-
    -DEXPAT_BUILD_SHARED=ON
    -DEXPAT_BUILD_STATIC=OFF
    -DEXPAT_BUILD_TESTS=OFF
    -DEXPAT_BUILD_EXAMPLES=OFF

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libexpat.so*' \
      -exec "$STRIP" {} +
