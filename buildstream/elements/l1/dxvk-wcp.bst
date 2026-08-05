kind: manual

description: |
  DXVK 3.0.2 gplasync WCP (x86_64 + i686 PE) from doitsujin/dxvk commit
  6b20f622a77b87b2921fe5d2c1774d2f2ba3e9b7.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/llvm-mingw-20250920-ucrt.bst
  junction: buildstream-sdk.bst
  type: build
- filename: host/glslang.bst
  type: build

sources:
- kind: git
  url: dxvk:dxvk.git
  ref: 6b20f622a77b87b2921fe5d2c1774d2f2ba3e9b7
  track: master
  checkout-submodules: true
- kind: local
  path: vendor/dxvk-patches/dxvk-gplasync-master.patch
  directory: .bst/patches
- kind: local
  path: ci/dxvk
  directory: .bst/ci/dxvk

environment:
  PATH: "/opt/glslang/bin:/opt/llvm-mingw/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  GLSLANG_ROOT: /opt/glslang
  DXVK_COMMIT: 6b20f622a77b87b2921fe5d2c1774d2f2ba3e9b7
  DXVK_VERSION: "3.0.2"
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/dxvk/build-dxvk-wcp.sh

  strip-commands: []
