kind: cmake

description: |
  Vulkan Loader 1.4.313 for Android/Bionic with XCB/Xlib WSI.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/graphics/vulkan-headers.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxcb.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libx11.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: khronos:Vulkan-Loader/archive/refs/tags/v1.4.313.tar.gz
  ref: 0c2436993597f5bd0ee420b6b27632758ed3ab439043d251795fd13d4e70a2f3

variables:
  target-triple: x86_64-linux-android35
  cmake-local: >-
    -DBUILD_TESTS=OFF
    -DBUILD_WSI_XCB_SUPPORT=ON
    -DBUILD_WSI_XLIB_SUPPORT=ON
    -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF
    -DVULKAN_HEADERS_INSTALL_DIR=/opt/android-sysroot/usr

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libvulkan.so*' \
      -exec "$STRIP" {} +
