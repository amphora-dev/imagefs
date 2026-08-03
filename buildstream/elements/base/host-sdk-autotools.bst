kind: import

description: |
  Pinned upstream Autotools host SDK.

  Docker Official Images' buildpack-deps:bookworm supplies a coherent glibc
  rootfs with autoconf, automake, libtool, GNU make, pkg-config and Perl. It is
  used only as a build dependency; Android target artifacts are staged under a
  separate sysroot location.

sources:
- kind: docker
  registry-url: https://registry.hub.docker.com
  image: library/buildpack-deps
  track: bookworm
  architecture: amd64
  os: linux
  # linux/amd64 manifest selected from the bookworm OCI index on 2026-08-03.
  ref: 5009ae2bfc9ff32268f48dd81844776a977a88cdfba28577db9b5857127a044a
  version: bookworm
