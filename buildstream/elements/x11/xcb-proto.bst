kind: autotools

description: |
  xcb-proto 1.17.0 XML protocol descriptions and Python generator modules.

  This is host-executable build metadata, so it intentionally clears the
  project-wide Android --host configure argument.

depends:
- filename: base/host-sdk-autotools.bst
  type: build

sources:
- kind: tar
  url: xorg:proto/xcb-proto-1.17.0.tar.xz
  ref: 2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c

variables:
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-global: ""
  conf-local: >-
    --enable-shared
    --disable-static
