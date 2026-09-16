kind: manual

description: |
  Proton Wine 11 WCP from wip/ahb-dxvk-from-knife-tip commit
  65119895331899dc35d1d807be5f9699ddddbf9c
  (WSI bridge size IPC + adapter geometry cache; AHB/DXVK ANW).

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
- filename: tools/recc.bst
  type: build

sandbox:
  remote-apis-socket:
    path: /tmp/reapi.sock
    action-cache-enable-update: True

sources:
- kind: git
  url: amphora:proton-wine.git
  ref: 65119895331899dc35d1d807be5f9699ddddbf9c
  track: wip/ahb-dxvk-from-knife-tip
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
  PROTON_COMMIT: 65119895331899dc35d1d807be5f9699ddddbf9c
  OUTPUT_DIR: "%{install-root}/artifacts"
  # Local cache-only recc against buildbox-casd (no remote workers required).
  RECC_SERVER: unix:/tmp/reapi.sock
  RECC_CAS_SERVER: unix:/tmp/reapi.sock
  RECC_ACTION_CACHE_SERVER: unix:/tmp/reapi.sock
  RECC_CACHE_ONLY: "1"
  # Required: CACHE_ONLY local misses do not UpdateActionResult unless this is set.
  RECC_CACHE_UPLOAD_LOCAL_BUILD: "1"
  RECC_USE_LOCALCAS: "1"
  # Stabilize action digests / silence empty-platform warning.
  RECC_REMOTE_PLATFORM_OSFamily: linux
  RECC_REMOTE_PLATFORM_ISA: x86_64
  RECC_LOG_LEVEL: warning

config:
  install-commands:
  - |
    bash .bst/ci/wine/build-proton-wcp.sh

  strip-commands: []
