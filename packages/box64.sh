#!/usr/bin/env bash
# box64 — cmake (ELF 二进制, x86_64→ARM64 翻译器)
# 参考: MiceWine packages/box64 + 官方 imagefs box64 ELF
# 这是 imagefs 中最关键的 ELF 可执行文件, 动态链接到 Bionic libc
# 关键: TERMUX=ON 跳过 Bionic 不支持的 pthread 函数
# 关键: 需要提供 libandroid-spawn.so (posix_spawn) 和 libandroid-sysv-semaphore.so
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="latest"
PKG_NAME="box64-git"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { git clone --depth=1 https://github.com/ptitSeb/box64.git "$PKG_NAME"; }
cd "$PKG_NAME" && rm -rf build_dir && mkdir build_dir && cd build_dir

cmake -DCMAKE_C_COMPILER=$CC \
    -DCMAKE_AR=$AR -DCMAKE_STRIP=$STRIP -DCMAKE_RANLIB=$RANLIB \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-function-declaration" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -landroid-spawn" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
    -DARM_DYNAREC=ON -DARM64=ON -DANDROID=ON -DTERMUX=ON -DNOGIT=ON \
    ..

# Use -j1 to avoid race conditions in box64's build system
make -j1
$STRIP box64
cp box64 $PREFIX/bin/box64

# 验证: box64 必须链接到 /system/bin/linker64 (Bionic)
log "  box64 $VER ELF 验证:"
if command -v readelf >/dev/null 2>&1; then
    INTERP=$(readelf -l "$PREFIX/bin/box64" 2>/dev/null | grep "interpreter" | sed 's/.*interpreter: \([^]]*\).*/\1/')
    log "    interpreter: $INTERP"
    NEEDED=$(readelf -d "$PREFIX/bin/box64" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\].*/\1/' | tr '\n' ' ')
    log "    NEEDED: $NEEDED"
fi

log "  box64 $VER: box64 $(ls -la $PREFIX/bin/box64 2>/dev/null | awk '{print $5}') bytes"
