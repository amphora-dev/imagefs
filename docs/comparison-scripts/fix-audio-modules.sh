#!/bin/bash
# 全面修复 imagefs: ALSA 插件 + PA 模块目录 + 配置文件
set -euo pipefail

PREFIX=/tmp/imagefs-build/imagefs/usr
ROOTFS=/tmp/imagefs-build/imagefs
NDK=/tmp/imagefs-build/cache/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
CC=$NDK/bin/aarch64-linux-android26-clang
STRIP=$NDK/bin/llvm-strip
ALSA_SRC=/tmp/imagefs-build/src/alsa-lib-1.2.13

echo "============================================"
echo "  Fix 7: Install missing ALSA headers"
echo "============================================"
cp -f "$ALSA_SRC/include/pcm_external.h" "$PREFIX/include/alsa/"
cp -f "$ALSA_SRC/include/pcm_ioplug.h" "$PREFIX/include/alsa/"
cp -f "$ALSA_SRC/include/pcm_extplug.h" "$PREFIX/include/alsa/" 2>/dev/null || true
cp -f "$ALSA_SRC/include/pcm_rate.h" "$PREFIX/include/alsa/" 2>/dev/null || true
echo "  ✅ ALSA headers: pcm_external.h, pcm_ioplug.h installed"

echo ""
echo "============================================"
echo "  Fix 8: Build ALSA android_aserver plugin"
echo "============================================"

# 编译 android_aserver ALSA 插件
$CC -fPIC -O2 -shared \
    -I"$PREFIX/include" \
    -o "$PREFIX/lib/asound_module_pcm_android_aserver.so" \
    /workspace/winlator/audio_plugin/module_pcm_android_aserver.c \
    -L"$PREFIX/lib" -lasound \
    -Wl,-soname,asound_module_pcm_android_aserver.so \
    -Wl,-rpath,/usr/lib

$STRIP "$PREFIX/lib/asound_module_pcm_android_aserver.so" 2>/dev/null || true
echo "  ✅ asound_module_pcm_android_aserver.so built ($(stat -c%s "$PREFIX/lib/asound_module_pcm_android_aserver.so") bytes)"

# 安装 ALSA 配置文件
mkdir -p "$ROOTFS/etc/alsa/conf.d"
cp -f /workspace/winlator/audio_plugin/android_aserver.conf "$ROOTFS/etc/alsa/conf.d/"
cp -f /workspace/winlator/audio_plugin/alsa.conf "$ROOTFS/etc/alsa/"
echo "  ✅ ALSA config: alsa.conf + android_aserver.conf installed"

echo ""
echo "============================================"
echo "  Fix 9: Fix PA module directory"
echo "============================================"

# 模块安装在 pulse-13.0/modules/ 但应该是 pulseaudio/modules/
OLD_MODDIR="$PREFIX/lib/pulse-13.0/modules"
NEW_MODDIR="$PREFIX/lib/pulseaudio/modules"

if [ -d "$OLD_MODDIR" ]; then
    mkdir -p "$NEW_MODDIR"
    
    # 复制所有模块和辅助库
    for f in "$OLD_MODDIR"/*.so; do
        [ -f "$f" ] || continue
        $STRIP "$f" 2>/dev/null || true
        cp -f "$f" "$NEW_MODDIR/"
    done
    
    # 检查模块 NEEDED 是否需要修复
    for f in "$NEW_MODDIR"/*.so; do
        [ -f "$f" ] || continue
        # 替换 libltdl.so.7 → libltdl.so (如果有)
        if readelf -d "$f" 2>/dev/null | grep -q 'libltdl.so.7'; then
            patchelf --replace-needed libltdl.so.7 libltdl.so "$f"
        fi
        # 替换 libsndfile.so.1 → libsndfile.so (如果有)
        if readelf -d "$f" 2>/dev/null | grep -q 'libsndfile.so.1'; then
            patchelf --replace-needed libsndfile.so.1 libsndfile.so "$f"
        fi
    done
    
    MOD_COUNT=$(ls "$NEW_MODDIR"/*.so 2>/dev/null | wc -l)
    echo "  ✅ PA modules: $MOD_COUNT modules installed to pulseaudio/modules/"
    
    # 移除旧目录
    rm -rf "$OLD_MODDIR"
    echo "  ✅ Removed old pulse-13.0/modules/ directory"
fi

echo ""
echo "============================================"
echo "  Fix 10: Install android_sysvshm"
echo "============================================"

# 构建 android_sysvshm (System V 共享内存, Bionic 缺失)
cat > /tmp/sysvshm_stub.c << 'STUBSRC'
#include <sys/shm.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ipc.h>

// Bionic 缺少 System V 共享内存, 提供基于 ashmem 的实现
#include <linux/ashmem.h>
#include <fcntl.h>
#include <sys/ioctl.h>

static int ashmem_fd = -1;

void *shmat(int shmid, const void *addr, int flag) {
    // 简单实现: 使用 mmap 映射 ashmem
    (void)shmid; (void)flag;
    if (addr == NULL) {
        return mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);
    }
    return (void *)addr;
}

int shmdt(const void *addr) {
    return munmap((void *)addr, 4096);
}

int shmget(key_t key, size_t size, int flag) {
    (void)key; (void)flag;
    // 创建 ashmem
    int fd = open("/dev/ashmem", O_RDWR);
    if (fd < 0) return -1;
    if (ioctl(fd, ASHMEM_SET_SIZE, size) < 0) { close(fd); return -1; }
    return fd;
}

int shmctl(int shmid, int cmd, struct shmid_ds *buf) {
    (void)buf;
    if (cmd == IPC_RMID) { close(shmid); return 0; }
    return 0;
}
STUBSRC

# 检查是否已有 sysvshm
if [ ! -f "$PREFIX/lib/libsysvshm.so" ]; then
    # 先尝试用项目的源码
    if [ -f /workspace/winlator/android_sysvshm/android_sysvshm.c ]; then
        $CC -fPIC -O2 -shared \
            -I"$PREFIX/include" \
            -o "$PREFIX/lib/libsysvshm.so" \
            /workspace/winlator/android_sysvshm/android_sysvshm.c \
            -Wl,-soname,libsysvshm.so \
            -Wl,-rpath,/usr/lib 2>/dev/null && \
            $STRIP "$PREFIX/lib/libsysvshm.so" 2>/dev/null && \
            echo "  ✅ libsysvshm.so built from project source" || \
            echo "  ⚠️ libsysvshm.so build failed (non-critical)"
    fi
else
    echo "  ℹ️ libsysvshm.so already exists"
fi

echo ""
echo "============================================"
echo "  Fix 11: Verify ELF interpreter"
echo "============================================"

# 检查所有 ELF 文件的 interpreter
BAD_ELF=0
for f in "$PREFIX/bin"/* "$PREFIX/lib"/*.so "$PREFIX/lib/pulseaudio"/*.so "$PREFIX/lib/pulseaudio/modules"/*.so; do
    [ -f "$f" ] || continue
    if file "$f" 2>/dev/null | grep -q "ELF"; then
        INTERP=$(readelf -l "$f" 2>/dev/null | grep interpreter | sed 's/.*\[\(.*\)\].*/\1/' || true)
        if [ -n "$INTERP" ] && [ "$INTERP" != "/system/bin/linker64" ]; then
            echo "  ⚠️ $(basename $f): interpreter=$INTERP (should be /system/bin/linker64)"
            BAD_ELF=$((BAD_ELF+1))
        fi
    fi
done
if [ $BAD_ELF -eq 0 ]; then
    echo "  ✅ All ELF files have correct interpreter (/system/bin/linker64)"
else
    echo "  ⚠️ $BAD_ELF files have wrong interpreter"
fi

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo "  PA modules: $(ls "$NEW_MODDIR"/*.so 2>/dev/null | wc -l)"
echo "  ALSA plugin: $(ls "$PREFIX/lib/asound_module"* 2>/dev/null | wc -l)"
echo "  ALSA config: $(ls "$ROOTFS/etc/alsa/"*.conf 2>/dev/null | wc -l)"
echo "  libpulseaudio.so: $([ -f "$PREFIX/lib/libpulseaudio.so" ] && echo 'present' || echo 'missing')"
echo "  libsysvshm.so: $([ -f "$PREFIX/lib/libsysvshm.so" ] && echo 'present' || echo 'missing')"
