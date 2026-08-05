kind: autotools

description: |
  libxshmfence 1.3.2 for Bionic using the pollfd fallback.

  xorgproto is relocated under /opt/android-sysroot, proving a real package
  dependency can be consumed without mixing target headers into host /usr.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libxshmfence-1.3.2.tar.xz
  ref: 870df257bc40b126d91b5a8f1da6ca8a524555268c50b59c0acd1a27f361606f

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-shared
    --disable-static
    --enable-malloc0returnsnull
    --disable-futex
    xorg_cv_malloc0_returns_null=yes
    --with-pic

environment:
  CFLAGS: "-fPIC -O2 -D_GNU_SOURCE -I/opt/android-sysroot%{prefix}/include"

config:
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libxshmfence.so*' \
      -exec "$STRIP" {} +
