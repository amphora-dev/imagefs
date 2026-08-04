kind: cmake

description: |
  PCRE2 10.44 8-bit shared library with Unicode and JIT enabled.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: pcre2:pcre2-10.44/pcre2-10.44.tar.bz2
  ref: d34f02e113cf7193a1ebf2770d3ac527088d485d4e047ed10e5d217c6ef5de96

variables:
  cmake-local: >-
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_STATIC_LIBS=OFF
    -DPCRE2_BUILD_PCRE2GREP=OFF
    -DPCRE2_BUILD_TESTS=OFF
    -DPCRE2_SUPPORT_UNICODE=ON
    -DPCRE2_SUPPORT_JIT=ON

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libpcre2-8.so*' \
      -exec "$STRIP" {} +
