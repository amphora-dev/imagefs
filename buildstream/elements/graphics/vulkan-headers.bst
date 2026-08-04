kind: manual

description: |
  Vulkan-Headers 1.4.313 as an architecture-independent artifact.

  The upstream CMake install provides headers, registry and VulkanHeadersConfig
  metadata required by Vulkan-Loader.

depends:
- filename: base/host-sdk-autotools.bst
  type: build

sources:
- kind: tar
  url: khronos:Vulkan-Headers/archive/refs/tags/v1.4.313.tar.gz
  ref: f3298b8dc620530493296759858a69b622f98ececa0e8c75488ad2000778148f

config:
  configure-commands:
  - |
    cmake -S . -B _build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib
  build-commands:
  - |
    cmake --build _build -j%{max-jobs}
  install-commands:
  - |
    env DESTDIR="%{install-root}" cmake --install _build
    set -eu
    includedir="%{install-root}%{prefix}/include"
    sharedir="%{install-root}%{prefix}/share/vulkan"
    test -f "$includedir/vulkan/vulkan.h"
    test -f "$includedir/vk_video/vulkan_video_codecs_common.h"
    test -f "%{install-root}%{prefix}/share/cmake/VulkanHeaders/VulkanHeadersConfig.cmake"

  strip-commands: []
