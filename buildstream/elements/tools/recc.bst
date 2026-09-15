kind: manual

description: |
  BuildGrid recc 1.4.15 — Remote Execution Caching Compiler (cache-only
  against the BuildStream/buildbox-casd remote-apis socket).

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: remote
  url: https://gitlab.com/api/v4/projects/8347934/packages/generic/releases/1.4.15/recc-1.4.15-x86_64-linux-gnu.tgz
  ref: 3e4ebe6ce1f33de5788d58343338bde9758297f458768d224671698f92c1bed3
  filename: recc-1.4.15-x86_64-linux-gnu.tgz

config:
  install-commands:
  - |
    set -eu
    mkdir -p "%{install-root}/usr/bin"
    tar -xzf recc-1.4.15-x86_64-linux-gnu.tgz -C "%{install-root}/usr/bin"
    chmod +x "%{install-root}/usr/bin/recc"
    "%{install-root}/usr/bin/recc" --help >/dev/null

  strip-commands: []
