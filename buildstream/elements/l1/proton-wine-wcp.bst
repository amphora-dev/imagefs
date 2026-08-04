kind: manual

description: |
  Proton Wine 11 WCP from amphora/x86_64-min commit
  421d427b97a9c17cfcfdbeb66058cb7d41da7abc.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/llvm-mingw-20250920-ucrt.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/host-freetype.bst
  type: build
- filename: wine/termuxfs-x86_64.bst
  type: build
  config:
    location: /opt/android-x86_64-sysroot
- filename: wine/prefix-pack-x86_64.bst
  type: build
  config:
    location: /opt/proton-assets

sources:
- kind: git
  url: amphora:proton-wine.git
  ref: 421d427b97a9c17cfcfdbeb66058cb7d41da7abc
  track: amphora/x86_64-min
  checkout-submodules: true
- kind: local
  path: ci/wine
  directory: .bst/ci/wine

environment:
  PATH: "/opt/llvm-mingw/bin:%{ndk-toolchain}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  ANDROID_NDK_HOME: "%{ndk-root}"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  ANDROID_X86_64_SYSROOT: /opt/android-x86_64-sysroot
  PREFIX_PACK: /opt/proton-assets/prefixPack.txz
  PROTON_COMMIT: 421d427b97a9c17cfcfdbeb66058cb7d41da7abc
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/wine/build-proton-wcp.sh

  strip-commands: []
