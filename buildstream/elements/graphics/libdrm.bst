kind: meson

description: |
  libdrm 2.4.124 minimal Android/Bionic build.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

sources:
- kind: tar
  url: dri:libdrm/libdrm-2.4.124.tar.xz
  ref: ac36293f61ca4aafaf4b16a2a7afff312aa4f5c37c9fbd797de9e3c0863ca379
- kind: local
  path: buildstream/files/meson-aarch64-android26.ini
  directory: .bst

variables:
  meson-local: >-
    -Ddefault_library=shared
    -Dintel=disabled
    -Dradeon=disabled
    -Damdgpu=disabled
    -Dexynos=disabled
    -Dfreedreno=disabled
    -Dvc4=disabled
    -Dvmwgfx=disabled
    -Dnouveau=disabled
    -Dman-pages=disabled
    -Dvalgrind=disabled
    -Dtests=false

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libdrm*.so*' \
      -exec "$STRIP" {} +
