kind: manual

description: Minimal native FreeType used by Wine's sfnt2fon build tool.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: freetype:freetype-2.13.3.tar.xz
  ref: 0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289

config:
  install-commands:
  - |
    set -eu
    export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export CC=/usr/bin/gcc
    export CXX=/usr/bin/g++
    export AR=/usr/bin/ar
    export RANLIB=/usr/bin/ranlib
    export STRIP=/usr/bin/strip
    unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS
    ./configure \
      --prefix=/opt/host-freetype \
      --without-zlib \
      --without-bzip2 \
      --without-png \
      --without-harfbuzz \
      --without-brotli
    make -j"%{max-jobs}"
    make DESTDIR="%{install-root}" install

  strip-commands: []
