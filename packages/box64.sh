#!/usr/bin/env bash
# box64 — 已从 imagefs 构建列表移除（build-all.sh 不再调用本脚本）。
# Amphora 用独立 Box64.wcp 安装到 ${bindir}/box64；imagefs 只保留
# android-spawn / android-sysv-semaphore 等垫片供 WCP 里的 box64 NEEDED。
# 本文件保留作参考；若手动 bash packages/box64.sh，产物也会在 package-imagefs
# 裁剪阶段被删掉（不得进 imagefs.txz）。
#
# 历史备注: TERMUX=ON；需 libandroid-spawn.so + libandroid-sysv-semaphore.so
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
