#!/usr/bin/env bash
# android-sysvshm — System V 共享内存 (Bionic 缺失)
# 源码: vendor/winlator-bionic/android_sysvshm/
# 导出 shm* + libandroid_shm*（wrapper/Turnip DT_NEEDED / 符号）
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VENDOR="$(cd "$(dirname "$0")/../vendor/winlator-bionic/android_sysvshm" && pwd)"
SRC_FILE="$VENDOR/android_sysvshm.c"

if [ ! -f "$SRC_FILE" ]; then
    error "android_sysvshm source not found: $SRC_FILE"
    exit 1
fi

FIXED_SRC="$WORK_DIR/sysvshm_fixed.c"
{
    echo '#include <string.h>'
    cat "$SRC_FILE"
    cat <<'ALIASES'

int libandroid_shmget(key_t key, size_t size, int flags) __attribute__((alias("shmget")));
void *libandroid_shmat(int shmid, const void *shmaddr, int shmflg) __attribute__((alias("shmat")));
int libandroid_shmdt(const void *shmaddr) __attribute__((alias("shmdt")));
int libandroid_shmctl(int shmid, int cmd, struct shmid_ds *buf) __attribute__((alias("shmctl")));
ALIASES
} > "$FIXED_SRC"

$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -I"$VENDOR" \
    -o "$PREFIX/lib/libandroid-sysvshm.so" \
    "$FIXED_SRC" \
    -Wl,-soname,libandroid-sysvshm.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null || true

missing=0
for sym in libandroid_shmget libandroid_shmat libandroid_shmdt libandroid_shmctl \
           shmget shmat shmdt shmctl; do
    if ! "$NM" -D --defined-only "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null | grep -q " ${sym}$"; then
        if ! readelf -Ws "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null | awk '{print $8}' | grep -qx "$sym"; then
            error "  missing export: $sym"
            missing=1
        fi
    fi
done
if [ "$missing" -ne 0 ]; then
    error "libandroid-sysvshm.so missing required exports"
    exit 1
fi

ln -sf libandroid-sysvshm.so "$PREFIX/lib/libsysvshm.so"
log "  android-sysvshm: libandroid-sysvshm.so (+ aliases, libsysvshm.so link)"
