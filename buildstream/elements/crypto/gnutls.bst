kind: autotools

description: |
  GnuTLS 3.8.8 runtime library for Wine TLS.

  Only LGPL gnulib and libgnutls are built; GPL command-line tooling and its
  unsupported timezone helpers are excluded exactly as in the production
  recipe.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- filename: crypto/gmp.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: crypto/nettle.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: text/libiconv.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: android/libcxx-shared.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: gnutls:v3.8/gnutls-3.8.8.tar.xz
  ref: ac4f020e583880b51380ed226e59033244bc536cad2623f2e26f5afa2939d8fb

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --host=aarch64-linux-android26
    --enable-shared
    --disable-static
    --without-p11-kit
    --without-tpm
    --without-tpm2
    --disable-doc
    --disable-tests
    --disable-tools
    --disable-nls
    --disable-libdane
    --with-included-libtasn1
    --with-included-unistring
    --without-idn

environment:
  NETTLE_CFLAGS: "-I/opt/android-sysroot/usr/include"
  NETTLE_LIBS: "-L/opt/android-sysroot/usr/lib -lnettle"
  HOGWEED_CFLAGS: "-I/opt/android-sysroot/usr/include"
  HOGWEED_LIBS: "-L/opt/android-sysroot/usr/lib -lhogweed -lnettle -lgmp"
  GMP_CFLAGS: "-I/opt/android-sysroot/usr/include"
  GMP_LIBS: "-L/opt/android-sysroot/usr/lib -lgmp"
  gl_cv_func_fmemopen_works: "yes"

config:
  build-commands:
  - |
    make -j%{max-jobs} -C gl
    make -j%{max-jobs} -C lib
  install-commands:
  - |
    make -C lib DESTDIR="%{install-root}" install
    test -e "%{install-root}%{prefix}/lib/pkgconfig/gnutls.pc"
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libgnutls*.so*' \
      -exec "$STRIP" {} +
