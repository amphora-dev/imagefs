kind: manual

description: |
  Host glslang 16.5.0 (linux-x86_64 release binaries) for DXVK / VKD3D
  shader compilation.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: glslang:16.5.0/glslang-16.5.0-linux-x86_64-release.tar.gz
  ref: b9b1f96acb898a62251b171f7695efcecfc206a530299054071919b06820f657
  base-dir: ""

config:
  install-commands:
  - |
    set -eu
    root="%{install-root}/opt/glslang"
    mkdir -p "$root"
    cp -a . "$root/"
    test -x "$root/bin/glslang" || test -x "$root/bin/glslangValidator"

  strip-commands: []
