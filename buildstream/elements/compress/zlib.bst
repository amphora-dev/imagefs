kind: manual

description: |
  zlib 1.3.1 for aarch64-linux-android26.

  This mirrors packages/compress/zlib.sh but writes only to install-root, so
  BuildStream can cache and reuse the package as an isolated artifact.

depends:
- base/ubuntu.bst
- toolchain/android-ndk-r29.bst

sources:
- kind: tar
  url: zlib:v1.3.1/zlib-1.3.1.tar.gz
  ref: 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23

config:
  build-commands:
  - |
    set -eu
    objects=
    for source in adler32 crc32 deflate infback inffast inflate inftrees trees \
                  zutil compress uncompr gzclose gzlib gzread gzwrite; do
      object="pic_${source}.o"
      "$CC" -O3 -fPIC -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN \
        -D_FILE_OFFSET_BITS=64 -I. -c -o "$object" "${source}.c"
      objects="$objects $object"
    done
    "$CC" -shared -Wl,-soname,libz.so.1 -O3 -DHAVE_HIDDEN \
      -o libz.so.1.3.1 $objects
    "$STRIP" libz.so.1.3.1

  install-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    includedir="%{install-root}%{prefix}/include"
    pcdir="$libdir/pkgconfig"
    mkdir -p "$libdir" "$includedir" "$pcdir"
    install -m 0755 libz.so.1.3.1 "$libdir/"
    ln -s libz.so.1.3.1 "$libdir/libz.so.1"
    ln -s libz.so.1.3.1 "$libdir/libz.so"
    install -m 0644 zlib.h zconf.h "$includedir/"
    cat > "$pcdir/zlib.pc" <<'EOF'
    prefix=/usr
    exec_prefix=${prefix}
    libdir=${exec_prefix}/lib
    includedir=${prefix}/include
    Name: zlib
    Description: zlib compression library
    Version: 1.3.1
    Libs: -L${libdir} -lz
    Cflags: -I${includedir}
    EOF

  strip-commands: []
