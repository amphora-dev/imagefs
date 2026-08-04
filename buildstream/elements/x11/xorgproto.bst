kind: autotools

description: |
  xorgproto 2024.1 headers and pkg-config metadata for the Android target
  sysroot.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: xorg:proto/xorgproto-2024.1.tar.xz
  ref: 372225fd40815b8423547f5d890c5debc72e88b91088fbfb13158c20495ccb59

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
