#!/usr/bin/env bash
# android-sysvshm — System V 共享内存 (Bionic 缺失)
# 来源: winlator/android_sysvshm/android_sysvshm.c
# 功能: 通过 ashmem 实现 System V 共享内存 IPC (shmget/shmat/shmdt/shmctl)
# 依赖: 无 (仅 Bionic libc)
# Bionic 适配: 添加 #include <string.h>, 修复 ipc64_perm 字段名 (__key→key, __seq→seq)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

WINLATOR_DIR="${WINLATOR_DIR:-/workspace/winlator}"
SRC_FILE="$WINLATOR_DIR/android_sysvshm/android_sysvshm.c"

if [ ! -f "$SRC_FILE" ]; then
    error "android_sysvshm source not found: $SRC_FILE"
    error "Set WINLATOR_DIR to the winlator project root"
    exit 1
fi

# Bionic 适配: 添加 string.h (android_sysvshm.c 需要 memcpy 等)
# 注: sys/shm.h 自定义的 debian_ipc_perm 字段名本身就是 __key/__seq,
# 与源码一致, 无需 sed 替换
FIXED_SRC="$WORK_DIR/sysvshm_fixed.c"
{
    echo '#include <string.h>'
    cat "$SRC_FILE"
} > "$FIXED_SRC"

$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -I"$(dirname "$SRC_FILE")" \
    -o "$PREFIX/lib/libsysvshm.so" \
    "$FIXED_SRC" \
    -Wl,-soname,libsysvshm.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/libsysvshm.so" 2>/dev/null || true

log "  android-sysvshm: libsysvshm.so (ashmem-based SysV IPC)"
