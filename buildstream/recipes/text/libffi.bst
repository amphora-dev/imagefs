# Platform-agnostic package recipe. Not a BuildStream element.
# Edit this file, then run: python3 buildstream/sync-arch-elements.py
kind: autotools

description: |
  libffi 3.4.6 cross-compiled for the configured Android target.

  This is the first package using the pinned upstream Autotools host SDK. Host
  tools run from sandbox / while the NDK remains under /opt/android-ndk and all
  future target dependencies are reserved for /opt/android-sysroot.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
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
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libffi.so*' \
      -exec "$STRIP" {} +
