kind: cmake

description: |
  Box64 WCP from ptitSeb/box64 main at
  0db8df7757b523e41cf31b6204c47d22b8fb4f08.
  WCP identity includes the sha256 prefix of the pipetto controller patch
  (versionName `...-p<p8>`), so patch-only changes produce a distinct
  versionName and never collide with an already-installed profile.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: git
  url: box64:box64.git
  ref: 0db8df7757b523e41cf31b6204c47d22b8fb4f08
  track: main
  checkout-submodules: false
- kind: local
  path: vendor/box64-patches/pipetto-controller-fix.patch
  directory: .bst/patches
- kind: local
  path: ci/box64
  directory: .bst/ci/box64

environment:
  BOX64_COMMIT: 0db8df7757b523e41cf31b6204c47d22b8fb4f08
  BOX64_PATCH: .bst/patches/pipetto-controller-fix.patch
  BOX64_BINARY: "%{build-root}/%{build-dir}/box64"
  OUTPUT_DIR: "%{install-root}/artifacts"

variables:
  notparallel: true
  cmake-local: >-
    -DCMAKE_C_COMPILER=%{ndk-toolchain}/bin/aarch64-linux-android30-clang
    -DCMAKE_C_FLAGS=-Wno-int-conversion\ -Wno-incompatible-pointer-types\ -Wno-implicit-function-declaration
    -DANDROID=1
    -DBIONIC=1
    -DARM_DYNAREC=1
    -DBAD_SIGNAL=1
    -DTERMUX=0
    -DHAVE_TRACE=0
    -DNOGIT=ON

config:
  configure-commands:
  - |
    patch -p1 < .bst/patches/pipetto-controller-fix.patch
  - |
    %{cmake}
  install-commands:
  - |
    bash .bst/ci/box64/build-box64-wcp.sh
  strip-commands: []
