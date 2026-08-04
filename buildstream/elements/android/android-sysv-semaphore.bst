kind: manual

description: |
  System V semaphore ENOSYS compatibility stubs for Bionic.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

config:
  configure-commands:
  - |
    cat > android_sysv_semaphore_stub.c <<'EOF'
    #include <errno.h>
    #include <sys/types.h>
    int semget(key_t key, int nsems, int semflg) { (void)key; (void)nsems; (void)semflg; errno = ENOSYS; return -1; }
    int semop(int semid, void *sops, size_t nsops) { (void)semid; (void)sops; (void)nsops; errno = ENOSYS; return -1; }
    int semctl(int semid, int semnum, int cmd, ...) { (void)semid; (void)semnum; (void)cmd; errno = ENOSYS; return -1; }
    int semtimedop(int semid, void *sops, size_t nsops, const void *timeout) { (void)semid; (void)sops; (void)nsops; (void)timeout; errno = ENOSYS; return -1; }
    EOF

  build-commands:
  - |
    "$CC" -fPIC -O2 -shared \
      -o libandroid-sysv-semaphore.so android_sysv_semaphore_stub.c \
      -Wl,-soname,libandroid-sysv-semaphore.so \
      -Wl,-rpath,/usr/lib
    "$STRIP" libandroid-sysv-semaphore.so

  install-commands:
  - |
    libdir="%{install-root}%{prefix}/lib"
    mkdir -p "$libdir"
    install -m 0755 libandroid-sysv-semaphore.so "$libdir/"

  strip-commands: []
