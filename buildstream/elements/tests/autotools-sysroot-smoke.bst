kind: manual

description: |
  Assert host Autotools and Android target artifacts occupy separate roots.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: base/host-sdk-autotools.bst
  type: build
- filename: compress/zlib.bst
  type: build
  config:
    location: /opt/android-sysroot

environment:
  PKG_CONFIG_PATH: ""
  PKG_CONFIG_SYSROOT_DIR: /opt/android-sysroot
  PKG_CONFIG_LIBDIR: "/opt/android-sysroot/usr/lib/pkgconfig:/opt/android-sysroot/usr/share/pkgconfig"

config:
  build-commands:
  - |
    set -eu
    for tool in autoconf automake autoreconf libtoolize make pkg-config perl; do
      command -v "$tool" >/dev/null
    done
    test -f /opt/android-sysroot/usr/include/zlib.h
    test -L /opt/android-sysroot/usr/lib/libz.so
    test ! -e /usr/lib/libz.so
    test "$PKG_CONFIG_SYSROOT_DIR" = /opt/android-sysroot
    test "$(pkg-config --modversion zlib)" = 1.3.1

  install-commands:
  - |
    mkdir -p "%{install-root}/share/imagefs"
    printf 'host-sdk and target sysroot isolated\n' \
      > "%{install-root}/share/imagefs/autotools-sysroot.ok"

  strip-commands: []
