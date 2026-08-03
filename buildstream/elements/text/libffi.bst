kind: autotools

description: |
  libffi 3.4.6 cross-compiled for aarch64-linux-android26.

  This is the first package using the pinned upstream Autotools host SDK. Host
  tools run from sandbox / while the NDK remains under /opt/android-ndk and all
  future target dependencies are reserved for /opt/android-sysroot.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: libffi:v3.4.6/libffi-3.4.6.tar.gz
  ref: b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: |
    --host=aarch64-linux-android
    --enable-shared
    --disable-static
  remove-libtool-libraries: "true"

environment:
  CFLAGS: "-fPIC -O2 -I/opt/android-sysroot%{prefix}/include"
  CPPFLAGS: "-I/opt/android-sysroot%{prefix}/include"
  LDFLAGS: "-L/opt/android-sysroot%{prefix}/lib -Wl,-rpath,/usr/lib -Wl,--allow-shlib-undefined"
  PKG_CONFIG_PATH: ""
  PKG_CONFIG_SYSROOT_DIR: /opt/android-sysroot
  PKG_CONFIG_LIBDIR: "/opt/android-sysroot%{prefix}/lib/pkgconfig:/opt/android-sysroot%{prefix}/share/pkgconfig"

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libffi.so*' \
      -exec "$STRIP" {} +
