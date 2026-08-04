kind: autotools

description: |
  Nettle 3.10.1 and Hogweed for Android/Bionic.

  GMP is staged only under /opt/android-sysroot. The build fails if Hogweed is
  absent, catching target GMP discovery failures at this package boundary.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/crypto/gmp.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: gnu:nettle/nettle-3.10.1.tar.gz
  ref: b0fcdd7fc0cdea6e80dcf1dd85ba794af0d5b4a57e26397eee3bc193272d9132

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --host=x86_64-linux-android35
    --enable-shared
    --disable-static
    --disable-documentation
    --disable-openssl
    --with-include-path=/opt/android-sysroot/usr/include
    --with-lib-path=/opt/android-sysroot/usr/lib

config:
  strip-commands:
  - |
    test -e "%{install-root}%{prefix}/lib/libhogweed.so"
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f \
      \( -name 'libnettle.so*' -o -name 'libhogweed.so*' \) \
      -exec "$STRIP" {} +
