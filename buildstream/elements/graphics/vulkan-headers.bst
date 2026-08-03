kind: manual

description: |
  Vulkan-Headers 1.4.313 as an architecture-independent artifact.

  Downstream imagefs packages consume the headers and registry. CMake package
  metadata is deferred until CMake itself is available as a declared sandbox
  tool; no target binaries are involved.

depends:
- filename: base/ubuntu.bst
  type: build

sources:
- kind: tar
  url: khronos:Vulkan-Headers/archive/refs/tags/v1.4.313.tar.gz
  ref: f3298b8dc620530493296759858a69b622f98ececa0e8c75488ad2000778148f

config:
  install-commands:
  - |
    set -eu
    includedir="%{install-root}%{prefix}/include"
    sharedir="%{install-root}%{prefix}/share/vulkan"
    mkdir -p "$includedir" "$sharedir"
    cp -a include/vulkan include/vk_video "$includedir/"
    cp -a registry "$sharedir/"
    test -f "$includedir/vulkan/vulkan.h"
    test -f "$includedir/vk_video/vulkan_video_codecs_common.h"

  strip-commands: []
