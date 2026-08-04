kind: manual

description: |
  Winlator System V shared-memory client for Bionic.

  The local source is hashed directly from vendor/winlator-bionic, so edits
  invalidate only this artifact and its downstream consumers.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: local
  path: vendor/winlator-bionic/android_sysvshm
  directory: source

config:
  build-commands:
  - |
    set -eu
    {
      echo '#include <string.h>'
      cat source/android_sysvshm.c
      cat <<'EOF'

    int libandroid_shmget(key_t key, size_t size, int flags) __attribute__((alias("shmget")));
    void *libandroid_shmat(int shmid, const void *shmaddr, int shmflg) __attribute__((alias("shmat")));
    int libandroid_shmdt(const void *shmaddr) __attribute__((alias("shmdt")));
    int libandroid_shmctl(int shmid, int cmd, struct shmid_ds *buf) __attribute__((alias("shmctl")));
    EOF
    } > sysvshm_fixed.c
    "$CC" -fPIC -O2 -shared \
      -Isource \
      -o libandroid-sysvshm.so \
      sysvshm_fixed.c \
      -Wl,-soname,libandroid-sysvshm.so \
      -Wl,-rpath,/usr/lib
    "$STRIP" libandroid-sysvshm.so

  install-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    mkdir -p "$libdir"
    install -m 0755 libandroid-sysvshm.so "$libdir/"
    ln -s libandroid-sysvshm.so "$libdir/libsysvshm.so"

  strip-commands: []
