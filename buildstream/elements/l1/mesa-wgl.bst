kind: manual

description: |
  Mesa 26.2.0 WGL for Windows programs: opengl32.dll + libgallium_wgl.dll
  (x86_64 + i686 PE) with the zink and softpipe gallium drivers, packed as
  the Amphora runtime asset graphics_driver/mesa-wgl.tzst.

  Amphora links both DLLs into every prefix's system32/syswow64 and runs
  Wine with opengl32=n,b. Wine's builtin opengl32 has no working backend
  under wineandroid (its EGL driver gets zero configs). zink renders GL on
  the guest Vulkan driver through winevulkan; Mesa falls back to softpipe on
  the CPU when zink cannot create a screen on that driver. No LLVM, so no
  llvmpipe.

  Uses the same mesa-26.2.0 tarball as graphics/mesa-gl.bst (the native
  Bionic/Linux Mesa). Every meson flag is in ci/mesa-wgl/build-mesa-wgl.sh;
  its sha256 is part of the asset name.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/llvm-mingw-20250920-ucrt.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: mesa:mesa-26.2.0.tar.xz
  ref: efd4bb08cdb7c365a812cd4e6c9202ab55b2f22cdcd13c7d6c4f9647b799a4ef
- kind: local
  path: ci/mesa-wgl
  directory: .bst/ci/mesa-wgl

environment:
  PATH: "/opt/llvm-mingw/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  LLVM_MINGW_ROOT: /opt/llvm-mingw
  MESA_VERSION: "26.2.0"
  MESA_TARBALL_SHA256: efd4bb08cdb7c365a812cd4e6c9202ab55b2f22cdcd13c7d6c4f9647b799a4ef
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/mesa-wgl/build-mesa-wgl.sh

  strip-commands: []
