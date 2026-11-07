kind: manual

description: |
  Mesa 26.2.6 Turnip (freedreno Vulkan, KGSL kernel interface) for Adreno:
  libvulkan_freedreno.so + meta.json, packed as the adrenotools driver
  package behind the Amphora runtime asset adrenotools/turnip.zip
  (AdrenotoolsManager.installFromZip unpacks it; the guest wrapper ICD loads
  it through ADRENOTOOLS_DRIVER_PATH/NAME). Replaces WN-Turnip 1.06-b.

  Mesa version is independent of graphics/mesa-gl.bst and l1/mesa-wgl.bst:
  Turnip follows the latest stable release on its own cadence.

  vendor/turnip-patches (README there):
  - 0001-0011: Mesa MR 44838 KGSL fixes (zero-timeout poll waited forever;
    timestamp + sync-file syncobj merge dereferenced NULL). First released
    in 26.3.0-rc2, not in 26.2.x.
  - 0012: u_gralloc fallback reads Qualcomm's UBWC bit without the gmsm
    magic, so Amphora's imported linear AHB swapchain images are not laid
    out tiled/UBWC.

  Real Android build (meson host system 'android', -Dplatforms=android,
  -Dandroid-stub=true, platform-sdk-version 30, libc++ linked statically),
  not the Bionic/Linux profile meson-mesa-api30.ini: adrenotools loads the
  driver in a linker namespace that only sees /system libraries and the
  driver dir, so it must not need imagefs libs, libc++_shared.so or libdrm.

  Every meson flag is in ci/turnip/build-turnip.sh; the sha256 of that
  script plus vendor/turnip-patches/*.patch is part of the asset name.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: host/glslang.bst
  type: build

sources:
- kind: tar
  url: mesa:mesa-26.2.6.tar.xz
  ref: b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92
- kind: local
  path: ci/turnip
  directory: .bst/ci/turnip
- kind: local
  path: vendor/turnip-patches
  directory: .bst/turnip-patches

environment:
  PATH: "/opt/glslang/bin:/usr/local/bin:%{ndk-toolchain}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  ANDROID_NDK_HOME: "%{ndk-root}"
  MESA_VERSION: "26.2.6"
  MESA_TARBALL_SHA256: b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash .bst/ci/turnip/build-turnip.sh

  strip-commands: []
