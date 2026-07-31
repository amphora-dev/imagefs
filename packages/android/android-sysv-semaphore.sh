#!/usr/bin/env bash
# libandroid-sysv-semaphore — SysV IPC semaphores for Bionic
# Bionic 不实现 SysV IPC semaphores (semget/semop/semctl)
# box64 (TERMUX=ON) 链接此库
set -euo pipefail
source "$(dirname "$0")/../config.sh"

cat > /tmp/android_sysv_semaphore_stub.c << 'STUBSRC'
#include <errno.h>
#include <sys/types.h>
int semget(key_t key, int nsems, int semflg) { (void)key; (void)nsems; (void)semflg; errno = ENOSYS; return -1; }
int semop(int semid, void *sops, size_t nsops) { (void)semid; (void)sops; (void)nsops; errno = ENOSYS; return -1; }
int semctl(int semid, int semnum, int cmd, ...) { (void)semid; (void)semnum; (void)cmd; errno = ENOSYS; return -1; }
int semtimedop(int semid, void *sops, size_t nsops, const void *timeout) { (void)semid; (void)sops; (void)nsops; (void)timeout; errno = ENOSYS; return -1; }
STUBSRC

$CC -fPIC -O2 -shared -o "$PREFIX/lib/libandroid-sysv-semaphore.so" /tmp/android_sysv_semaphore_stub.c \
    -Wl,-soname,libandroid-sysv-semaphore.so -Wl,-rpath,/usr/lib
$STRIP "$PREFIX/lib/libandroid-sysv-semaphore.so"

log "  libandroid-sysv-semaphore: semget/semop/semctl stubs for Bionic"
