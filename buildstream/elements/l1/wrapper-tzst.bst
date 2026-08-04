kind: manual

description: |
  Pipetto Vulkan wrapper TZST from wrapper-25 commit
  7eae6442f5d8a7414e66adc0d42857c143f20fa9.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- { filename: compress/zlib.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: compress/zstd.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: text/libffi.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: text/libexpat.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: android/android-sysvshm.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: android/libcxx-shared.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/xorgproto.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/libxcb.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/xtrans.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/libx11.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/libxext.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/libxfixes.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: x11/libxshmfence.bst, type: build, config: { location: /tmp/imagefs-build/staging } }
- { filename: graphics/libdrm.bst, type: build, config: { location: /tmp/imagefs-build/staging } }

sources:
- kind: git
  url: pipetto:mesa.git
  ref: 7eae6442f5d8a7414e66adc0d42857c143f20fa9
  track: wrapper-25
  checkout-submodules: false
  directory: wrapper-mesa-src
- kind: git
  url: pipetto:libadrenotools.git
  ref: 8483dfdaa2abf97ee89ad0e5f337e7b508550c6b
  checkout-submodules: true
  directory: wrapper-mesa-src/subprojects/libadrenotools
- kind: local
  path: ci/wrapper
  directory: repo/ci/wrapper
- kind: local
  path: ci/upstream.sh
  directory: repo/ci
- kind: local
  path: lib
  directory: repo/lib
- kind: local
  path: vendor/wrapper-patches
  directory: repo/vendor/wrapper-patches

environment:
  PATH: "/usr/local/bin:%{ndk-toolchain}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  ANDROID_NDK_HOME: "%{ndk-root}"
  ANDROID_NDK_ROOT: "%{ndk-root}"
  BUILD_DIR: /tmp/imagefs-build
  SKIP_STAGING: "1"
  WRAPPER_PRESTAGED_MESA: "1"
  WRAPPER_MESA_SRC: "%{build-root}/wrapper-mesa-src"
  WRAPPER_MESA_COMMIT: 7eae6442f5d8a7414e66adc0d42857c143f20fa9
  MESA_REF: 7eae6442f5d8a7414e66adc0d42857c143f20fa9
  OUTPUT_DIR: "%{install-root}/artifacts"

config:
  install-commands:
  - |
    bash repo/ci/wrapper/build-tzst.sh
  strip-commands: []
