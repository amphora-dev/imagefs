kind: manual

description: |
  Termux System V shared-memory implementation at commit 7f0bd7e.

  The full upstream commit and GitHub archive SHA-256 are pinned. Only the
  runtime DSO is published; shm.h is deliberately omitted because its macro
  redirects would contaminate downstream package builds. _PATH_TMP matches
  imagefs base-layout (/usr/tmp), not Termux app data paths.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: termux:libandroid-shmem/archive/7f0bd7e25dbdd146265aff7c6a890029e374622d.tar.gz
  ref: 48e80a854df55dd8eb2a5026cb3cc90a10165aae68c591acdabad24488ce621f

config:
  build-commands:
  - |
    set -eu
    "$CC" -O2 -std=c11 -fPIC -shared \
      -D_PATH_TMP='"/usr/tmp/"' \
      -Wl,--version-script=exports.txt \
      -Wl,--undefined-version \
      -Wl,-soname,libandroid-shmem.so \
      -Wl,-rpath,/usr/lib \
      -o libandroid-shmem.so \
      shmem.c \
      -llog -landroid
    "$STRIP" libandroid-shmem.so

  install-commands:
  - |
    libdir="%{install-root}%{prefix}/lib"
    mkdir -p "$libdir"
    install -m 0755 libandroid-shmem.so "$libdir/"

  strip-commands: []
