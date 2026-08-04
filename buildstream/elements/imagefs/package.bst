kind: manual

description: Reproducible imagefs.txz deployment artifact.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: imagefs/runtime.bst
  type: build
  config:
    location: /imagefs

config:
  install-commands:
  - |
    set -eu
    out="%{install-root}/artifacts"
    mkdir -p "$out"
    tar \
      --owner=0 \
      --group=0 \
      --numeric-owner \
      --mtime="@$SOURCE_DATE_EPOCH" \
      --clamp-mtime \
      --sort=name \
      -I 'xz -T1' \
      -cf "$out/imagefs.txz" \
      -C /imagefs .
    (
      cd "$out"
      sha256sum imagefs.txz |
        awk '{print $1"  imagefs.txz"}' > imagefs.txz.sha256sum
      split -b 52428800 -d -a 2 imagefs.txz imagefs.txz.
    )

  strip-commands: []
