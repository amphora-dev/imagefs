kind: autotools

description: |
  xtrans 1.5.2 transport headers and pkg-config metadata.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: xorg:lib/xtrans-1.5.2.tar.xz
  ref: 5c5cbfe34764a9131d048f03c31c19e57fb4c682d67713eab6a65541b4dff86c

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    --enable-shared
    --disable-static
