#!/usr/bin/env bash
# libc++_shared — NDK C++ 运行时
#
# libvulkan_wrapper.so (wrapper.tzst) 的 DT_NEEDED 含 libc++_shared.so。
# Guest LD_LIBRARY_PATH 只有 imagefs/usr/lib:/system/lib64, **不包含**
# APK nativeLibraryDir, 所以必须把 NDK 这份打进 imagefs; 官方 imagefs 也带。
# 缺了则 ICD dlopen 失败 → vkCreateInstance -9 → DXVK「Failed to initialize」。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

# setup-env.sh 已 export TC=.../toolchains/llvm/prebuilt/linux-x86_64
SRC="$TC/sysroot/usr/lib/${ARCH}-linux-android/libc++_shared.so"
if [ ! -f "$SRC" ]; then
    error "NDK libc++_shared.so not found: $SRC"
    exit 1
fi

cp -f "$SRC" "$PREFIX/lib/libc++_shared.so"
chmod 755 "$PREFIX/lib/libc++_shared.so"
$STRIP "$PREFIX/lib/libc++_shared.so" 2>/dev/null || true

# soname 必须是裸名 (wrapper NEEDED 写的是 libc++_shared.so, 无版本后缀)
soname=$(readelf -dW "$PREFIX/lib/libc++_shared.so" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ -n "$soname" ] && [ "$soname" != "libc++_shared.so" ]; then
    warn "  unexpected SONAME='$soname' (wrapper NEEDED is libc++_shared.so)"
fi

log "  libc++_shared: $(ls -la "$PREFIX/lib/libc++_shared.so" | awk '{print $5}') bytes from NDK"
