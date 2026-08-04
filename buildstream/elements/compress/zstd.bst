kind: manual

description: |
  zstd 1.5.6 for aarch64-linux-android26.

  The production recipe uses CMake plus an Android SONAME patch. This isolated
  PoC links the same upstream library source set directly and writes the SONAME
  at link time, avoiding both undeclared host CMake and post-link patchelf.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: tar
  url: zstd:v1.5.6/zstd-1.5.6.tar.gz
  ref: 8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1

config:
  build-commands:
  - |
    set -eu
    sources="$(find \
      lib/common lib/compress lib/decompress lib/dictBuilder lib/deprecated \
      -type f -name '*.c' | LC_ALL=C sort)"
    # 32 portable C units. The remaining upstream .S file is the x86_64-only
    # Huffman decoder and must not enter this AArch64 build.
    test "$(printf '%s\n' "$sources" | grep -c .)" -eq 32
    "$CC" -O3 -fPIC -fvisibility=hidden \
      -DZSTD_MULTITHREAD -DZSTD_LEGACY_SUPPORT=0 \
      -Ilib -Ilib/common \
      -shared -Wl,-soname,libzstd.so.1 -Wl,-rpath,/usr/lib \
      $sources -o libzstd.so.1.5.6
    "$STRIP" libzstd.so.1.5.6

  install-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    includedir="%{install-root}%{prefix}/include"
    pcdir="$libdir/pkgconfig"
    mkdir -p "$libdir" "$includedir" "$pcdir"
    install -m 0755 libzstd.so.1.5.6 "$libdir/"
    ln -s libzstd.so.1.5.6 "$libdir/libzstd.so.1"
    ln -s libzstd.so.1.5.6 "$libdir/libzstd.so"
    install -m 0644 lib/zstd.h lib/zdict.h lib/zstd_errors.h "$includedir/"
    cat > "$pcdir/libzstd.pc" <<'EOF'
    prefix=/usr
    exec_prefix=${prefix}
    includedir=${prefix}/include
    libdir=${exec_prefix}/lib
    Name: zstd
    Description: fast lossless compression algorithm library
    URL: https://facebook.github.io/zstd/
    Version: 1.5.6
    Libs: -L${libdir} -lzstd
    Cflags: -I${includedir}
    EOF

  strip-commands: []
