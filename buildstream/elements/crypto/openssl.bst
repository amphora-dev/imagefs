kind: manual

description: |
  OpenSSL 3.4.1 for Android arm64 with assembly/tests/legacy disabled.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: compress/zlib.bst
  type: build
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: openssl:openssl-3.4.1/openssl-3.4.1.tar.gz
  ref: 002a2d6b30b58bf4bea46c43bdd96365aaf8daa6c428782aa4feee06da197df3

environment:
  ANDROID_NDK_ROOT: "%{ndk-root}"
  ANDROID_NDK_HOME: "%{ndk-root}"

config:
  configure-commands:
  - |
    ./Configure \
      android-arm64 \
      --prefix=/usr \
      --libdir=lib \
      --openssldir=/usr/etc/ssl \
      shared \
      no-asm \
      no-tests \
      no-unit-test \
      no-legacy \
      -D__ANDROID_API__=26 \
      -Wl,-rpath,/usr/lib
  build-commands:
  - |
    make -j%{max-jobs}
  install-commands:
  - |
    make DESTDIR="%{install-root}" install_sw install_ssldirs
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f \
      \( -name 'libssl.so*' -o -name 'libcrypto.so*' \) \
      -exec "$STRIP" {} +
