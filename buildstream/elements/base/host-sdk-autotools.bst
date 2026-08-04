kind: import

description: |
  Complete host-only build SDK generated from pinned Ubuntu Base 24.04.4.

  The fixed Release asset includes GCC/G++, Autotools, CMake, Meson/Ninja,
  Perl/Python/Mako and other graph build tools. Its package manifest and archive
  SHA are produced by ci/buildstream/build-host-sdk.sh and locked in
  ci/buildstream/host-sdk.lock.

sources:
- kind: tar
  url: imagefs-release:buildstream-host-sdk/imagefs-host-sdk-noble-amd64.tar.xz
  ref: 942776693e88cdc95a93e2e9b351e75f3a8be1fddfa1b85d3081787946852af3
  base-dir: ""
