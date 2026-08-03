kind: autotools

description: |
  xtrans 1.5.2 transport headers and pkg-config metadata.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: xorg:lib/xtrans-1.5.2.tar.xz
  ref: 5c5cbfe34764a9131d048f03c31c19e57fb4c682d67713eab6a65541b4dff86c

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-shared
    --disable-static
