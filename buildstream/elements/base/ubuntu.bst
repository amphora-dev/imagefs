kind: import

description: |
  Minimal glibc runtime for BuildStream build sandboxes.

  This is a build dependency only. It supplies /bin/sh and coreutils needed to
  execute the NDK host binaries; it is never included in the imagefs artifact.

sources:
- kind: tar
  url: ubuntu:ubuntu-base-24.04.4-base-amd64.tar.gz
  ref: c1e67ef7b17a6300e136118bd1dc04725009cb376c1aad10abcf8cd453628d58
  base-dir: ""
