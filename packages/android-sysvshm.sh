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

# 实体命名 libandroid-sysvshm.so, 与官方 imagefs 一致 (那边是 22KB 实体文件, 且
# **没有** libsysvshm.so)。这个文件名是硬要求:
#   - libvulkan_wrapper.so 与 libvulkan_freedreno.so 的 DT_NEEDED 写的是它
#   - amphora GuestProgramLauncherComponent 用它做 LD_PRELOAD, 并在
#     XServerWineSessionPreparer 的 wrapperDeps 里按此名拷贝
# 之前只产 libsysvshm.so, 于是自建 imagefs 上 Vulkan 驱动会因缺 NEEDED 而加载失败。
$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -I"$(dirname "$SRC_FILE")" \
    -o "$PREFIX/lib/libandroid-sysvshm.so" \
    "$FIXED_SRC" \
    -Wl,-soname,libandroid-sysvshm.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null || true

# libsysvshm.so 软链: libx11.sh 用 -lsysvshm 链接这些符号 (Bionic 无 shmget 等)。
ln -sf libandroid-sysvshm.so "$PREFIX/lib/libsysvshm.so"

log "  android-sysvshm: libandroid-sysvshm.so (+ libsysvshm.so 软链, ashmem-based SysV IPC)"
