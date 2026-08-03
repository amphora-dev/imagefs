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
  conf-local: >-
    --enable-shared
    --disable-static

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libffi.so*' \
      -exec "$STRIP" {} +
