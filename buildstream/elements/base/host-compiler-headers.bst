kind: manual

description: |
  Minimal host glibc/kernel development overlay for NDK Clang build generators.

  The NDK's pinned Clang is multi-target; with these host headers and crt files
  it can compile x86_64-linux-gnu helper programs without a separate GCC
  closure. The Ubuntu Base runtime is one patch revision older but ABI
  compatible; no base runtime files are replaced.

depends:
- filename: base/ubuntu.bst
  type: build

sources:
- kind: remote
  url: ubuntu-archive:pool/main/g/glibc/libc6-dev_2.39-0ubuntu8.8_amd64.deb
  ref: bb8741966e7c1d2e2c0b84bb311717a0908fb563d9b2247b7212710e3cd88b94
- kind: remote
  url: ubuntu-archive:pool/main/l/linux/linux-libc-dev_6.8.0-136.136_amd64.deb
  ref: adde3ef425ccf82bf5f14d45a3143fab6c6eea26c1fd0f8a5eb43989e5fe255d
- kind: remote
  url: ubuntu-archive:pool/main/g/gcc-13/libgcc-13-dev_13.3.0-6ubuntu2%7e24.04.1_amd64.deb
  ref: cd689db2691edaa10f37329307292796bb599e722e0505c79e14caaa1fe9a93a

config:
  install-commands:
  - |
    set -eu
    for package in ./*.deb; do
      dpkg-deb --extract "$package" "%{install-root}"
    done
    test -f "%{install-root}/usr/include/stdio.h"
    test -f "%{install-root}/usr/include/linux/futex.h"
    test -f "%{install-root}/usr/lib/x86_64-linux-gnu/crt1.o"
    test -f "%{install-root}/usr/lib/gcc/x86_64-linux-gnu/13/crtbeginS.o"

  strip-commands: []
