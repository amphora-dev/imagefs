kind: manual

description: |
  Proton Wine 11 WCP from proton_11.0 commit
  d78fbdeefc9c2d025fe1a69f8c41179eae592d62
  (wineandroid upstream backport on mainline; skip wine-debug.apk; Proton ABI).

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
- filename: wine/sysroot-x86_64.bst
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
  ref: d78fbdeefc9c2d025fe1a69f8c41179eae592d62
  track: proton_11.0
  checkout-submodules: true
- kind: remote
  url: termux-packages-legacy:pool/main/p/pulseaudio/pulseaudio_13.0-1_x86_64.deb
  ref: e7931675771c92bfec0e1b2f7acbf94b5a468facf087c52f3980dc5616e30c60
  filename: pulseaudio_13.0-1_x86_64.deb
- kind: local
  path: ci/wine
  directory: .bst/ci/wine

environment:
  PATH: "/opt/llvm-mingw/bin:%{ndk-toolchain}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  ANDROID_NDK_HOME: "%{ndk-root}"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  ANDROID_X86_64_SYSROOT: /opt/android-x86_64-sysroot
  PREFIX_PACK: /opt/proton-assets/prefixPack-11.0-d12a5634a-x86_64-1.txz
  PULSE_DEV_DEB: pulseaudio_13.0-1_x86_64.deb
  PROTON_COMMIT: d78fbdeefc9c2d025fe1a69f8c41179eae592d62
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/wine/build-proton-wcp.sh

  strip-commands: []
