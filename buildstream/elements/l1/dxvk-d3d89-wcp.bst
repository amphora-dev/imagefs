kind: manual

description: |
  DXVK 2.6.2 WCP (x86_64 + i686 PE, no gplasync) from doitsujin/dxvk tag
  v2.6.2 (9d6f54a1ade20d1d27dd421024717a636f3d8c68). Amphora links only
  its d3d8/d3d9 when the Qualcomm driver rejects DXVK 3.0.2's
  fixed-function shaders; dxgi/d3d10core/d3d11 stay on l1/dxvk-wcp.bst.
  2.6.2 is the last 2.x before VK_KHR_maintenance5 became required.

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
  ref: 9d6f54a1ade20d1d27dd421024717a636f3d8c68
  track: v2.6.2
  checkout-submodules: true
- kind: local
  path: ci/dxvk
  directory: .bst/ci/dxvk

environment:
  PATH: "/opt/glslang/bin:/opt/llvm-mingw/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  GLSLANG_ROOT: /opt/glslang
  DXVK_COMMIT: 9d6f54a1ade20d1d27dd421024717a636f3d8c68
  DXVK_VERSION: "2.6.2"
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/dxvk/build-dxvk-wcp.sh

  strip-commands: []
