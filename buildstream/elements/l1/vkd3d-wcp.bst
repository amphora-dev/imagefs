kind: manual

description: |
  VKD3D-Proton 3.0.1 WCP (x86_64 + i686 PE) from HansKristian-Work/vkd3d-proton
  commit 3b10bd7a7ec6a7347e616cf8bea59333afec2255.

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
  url: vkd3d:vkd3d-proton.git
  ref: 3b10bd7a7ec6a7347e616cf8bea59333afec2255
  track: master
  checkout-submodules: true
- kind: local
  path: ci/vkd3d
  directory: .bst/ci/vkd3d

environment:
  PATH: "/opt/glslang/bin:/opt/llvm-mingw/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  GLSLANG_ROOT: /opt/glslang
  VKD3D_COMMIT: 3b10bd7a7ec6a7347e616cf8bea59333afec2255
  VKD3D_VERSION: "3.0.1"
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/vkd3d/build-vkd3d-wcp.sh

  strip-commands: []
