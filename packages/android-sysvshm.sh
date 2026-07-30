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
    # libvulkan_wrapper.so / libvulkan_freedreno.so 的 DT_NEEDED 是
    # libandroid-sysvshm.so, 但解析的是 libandroid_shm*（官方 imagefs 同 ABI）。
    # 上游源码只导出 shm*；缺别名时 loader 报:
    #   cannot locate symbol "libandroid_shmget" ... Ignoring this JSON
    # → vkCreateInstance = VK_ERROR_INCOMPATIBLE_DRIVER (-9) → DXVK 起不来。
    cat <<'ALIASES'

int libandroid_shmget(key_t key, size_t size, int flags) __attribute__((alias("shmget")));
void *libandroid_shmat(int shmid, const void *shmaddr, int shmflg) __attribute__((alias("shmat")));
int libandroid_shmdt(const void *shmaddr) __attribute__((alias("shmdt")));
int libandroid_shmctl(int shmid, int cmd, struct shmid_ds *buf) __attribute__((alias("shmctl")));
ALIASES
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

# 断言 wrapper 需要的符号已导出 — 缺了 DX11/DX12 会静默挂成 -9。
missing=0
for sym in libandroid_shmget libandroid_shmat libandroid_shmdt libandroid_shmctl \
           shmget shmat shmdt shmctl; do
    if ! "$NM" -D --defined-only "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null | grep -q " ${sym}$"; then
        # fallback: readelf (strip 后 nm 可能仍可用; 双保险)
        if ! readelf -Ws "$PREFIX/lib/libandroid-sysvshm.so" 2>/dev/null | awk '{print $8}' | grep -qx "$sym"; then
            error "  missing export: $sym"
            missing=1
        fi
    fi
done
if [ "$missing" -ne 0 ]; then
    error "libandroid-sysvshm.so is missing libandroid_shm* aliases required by wrapper/Turnip"
    exit 1
fi

# libsysvshm.so 软链: libx11.sh 用 -lsysvshm 链接这些符号 (Bionic 无 shmget 等)。
ln -sf libandroid-sysvshm.so "$PREFIX/lib/libsysvshm.so"

log "  android-sysvshm: libandroid-sysvshm.so (+ libandroid_shm* aliases, libsysvshm.so link)"
