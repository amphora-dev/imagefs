#!/usr/bin/env bash
# libandroid-shmem — Termux 的 System V 共享内存实现。
#
# 与本仓的 android-sysvshm.sh **不是同一个东西**, 官方 imagefs 里两者并存:
#   libandroid-shmem.so    Termux 实现, API>=26 走 ASharedMemory
#   libandroid-sysvshm.so  winlator 实现, 走 ANDROID_SYSVSHM_SERVER socket
#
# libGL.so.1 (Mesa/Zink, 由 extra_libs.tzst 提供) 的 NEEDED 指名要
# libandroid-shmem.so, 缺了 OpenGL 路径起不来。首轮 42 包只做了 winlator 那份。
#
# 上游无 release tarball, 按 commit 锁定。上游 Makefile 假定在 Termux 里原生
# 编译, 这里按它的编译方式手工交叉编译 (源码就一个 shmem.c)。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

# 7f0bd7e = "Use ASharedMemory if targeting API level 26 or later" —— 与本仓
# ANDROID_API=26 正好对应, 走 ASharedMemory 而非已废弃的 ashmem ioctl。
COMMIT="7f0bd7e"
PKG_NAME="libandroid-shmem"
SRC_URL="https://github.com/termux/libandroid-shmem.git"

cd "$SRC_DIR"
if [ ! -d "$PKG_NAME" ]; then
    git clone "$SRC_URL" "$PKG_NAME"
fi
cd "$PKG_NAME"
git checkout -q "$COMMIT"

# shmem.c 用 _PATH_TMP 拼 key→fd 的 symlink 路径 (ASHV_KEY_SYMLINK_PATH)。Bionic
# 的 <paths.h> 故意不定义 _PATH_TMP (Android 没有全局 /tmp), Termux 是打补丁加的,
# 所以这里必须显式给值, 否则报 "use of undeclared identifier '_PATH_TMP'"。
#
# 取值照抄官方 imagefs 里那份的实测字符串:
#   strings libandroid-shmem.so -> /data/data/com.termux/files/usr/tmp/ashv_key_%d
# 与 Wine .so 的 DT_RUNPATH=/data/data/com.termux/files/usr/lib 是同一套 Termux
# 路径假设 (见 amphora docs/RESEARCH-proton-wine-selfbuild.md §3.1)。该目录在
# Amphora 设备上并不存在, 但自建 imagefs 的目标是做官方的精确子集, 保持行为一致;
# 是否改到 app 私有目录属于单独的行为变更, 不在本包内擅自决定。
TERMUX_TMP="/data/data/com.termux/files/usr/tmp/"

# 与上游 Makefile 等价: -llog -landroid, exports.txt 作 version script。
# 注意 setup-env.sh 的全局 LDFLAGS 带 --undefined-version, 与 version script
# 里列出但未实现的符号并存不会报错。
# shellcheck disable=SC2086
$CC $CFLAGS -std=c11 -fPIC -shared \
    -D_PATH_TMP="\"$TERMUX_TMP\"" \
    -Wl,--version-script=exports.txt \
    -Wl,-soname,libandroid-shmem.so \
    -o "$PREFIX/lib/libandroid-shmem.so" \
    shmem.c \
    -llog -landroid

# **不要**装 shm.h。上游的 install 目标会把它放到 $PREFIX/include/sys/shm.h, 而那个
# 头做符号宏重定向:
#   #define shmget libandroid_shmget   (shmat / shmdt / shmctl 同)
# 一旦它出现在 include 路径里, 后续任何 #include <sys/shm.h> 的包都会把 shm 调用
# 改写成 libandroid_* 符号, 而它们并不链接 -landroid-shmem, 于是链接期报
#   ld.lld: error: undefined symbol: libandroid_shmget
# 实测这样会连带打挂 alsa-lib / pulseaudio / sdl2 / alsa-android-aserver /
# gst-plugins-base 五个包。
#
# 我们只需要这个 .so 本体: 消费者是预编译的 libGL.so.1 (extra_libs.tzst), 它的
# NEEDED 里写着 libandroid-shmem.so, 运行期由 linker 解析, 不需要头文件。

$STRIP "$PREFIX/lib/libandroid-shmem.so" 2>/dev/null || true

# soname 必须与 Mesa 的 NEEDED 完全一致, 否则装了也找不到。
soname=$(readelf -dW "$PREFIX/lib/libandroid-shmem.so" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
if [ "$soname" != "libandroid-shmem.so" ]; then
    error "  soname 不符: 得到 '$soname', 期望 'libandroid-shmem.so'"
    exit 1
fi

log "  libandroid-shmem @$COMMIT: soname=$soname"
