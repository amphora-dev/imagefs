#!/usr/bin/env bash
# pulseaudio 13.0 — autotools (匹配 winlator bionic 实际版本)
# PA 13.0 使用 autotools (14.0+ 才迁移到 meson)
# 依赖: glib, libsndfile, alsa-lib, openssl, libltdl(stub)
# Bionic 适配: pthread_mutexattr_setprotocol, execinfo.h, sys/capability.h, ltdl.h stubs
# 输出匹配原始 winlator bionic:
#   - SONAME: libpulse.so (无版本号)
#   - NEEDED: 包含 libsndfile.so, libltdl.so (无版本号)
#   - daemon: 重命名为 libpulseaudio.so (匹配 jniLibs)
#   - 模块目录: pulseaudio/modules/ (不是 pulse-13.0/modules/)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="13.0"
PKG_NAME="pulseaudio-$VER"
SRC_URL="https://freedesktop.org/software/pulseaudio/releases/pulseaudio-$VER.tar.xz"

cd "$SRC_DIR"
[ -d "$PKG_NAME" ] || { curl -sL "$SRC_URL" -o pulseaudio.tar.xz && tar xf pulseaudio.tar.xz; }
cd "$PKG_NAME"

# ---- Bionic 补丁 ----
# PA 13.0 在 Bionic (NDK r29/API26) 下的不兼容点, 大部分用 configure cache 变量
# 或 --disable/--without 选项解决 (优于 sed 改源码), 详见下方 configure。
#
# 仍需 sed 的一处: backtrace()/backtrace_symbols() —— NDK 有 <execinfo.h> 头但函数
# 被 __INTRODUCED_IN(33) 守卫, configure 误判 HAVE_EXECINFO_H=1 → log.c 编译报错。
# 双保险: ① ac_cv_header_execinfo_h=no  ② log.c 内 #ifdef HAVE_EXECINFO_H → #if 0
if grep -q "#ifdef HAVE_EXECINFO_H" src/pulsecore/log.c 2>/dev/null; then
    sed -i 's@#ifdef HAVE_EXECINFO_H@#if 0 /* BIONIC_NO_EXECINFO */@g' src/pulsecore/log.c
fi

# ---- 交叉编译 configure ----
# ax_cv_check_cflags__pedantic__Werror__std_gnu11=yes 绕过 -std=gnu11 检查
# (NDK clang 支持 -std=gnu11, 但 -pedantic -Werror 导致 NDK 头文件警告变错误)
#
# 使用 -Os 优化体积 (匹配原始 winlator bionic 的库大小)
# 使用 -fno-asynchronous-unwind-tables -fno-unwind-tables 移除 .eh_frame 段
export CFLAGS="$CFLAGS -Os -fno-asynchronous-unwind-tables -fno-unwind-tables -std=gnu11 -Wno-int-conversion -Wno-error -Wno-incompatible-pointer-types"
export CXXFLAGS="$CXXFLAGS -Os -fno-asynchronous-unwind-tables -fno-unwind-tables"

# 确保 libsndfile 和 openssl 被检测到 (通过 pkg-config)
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export OPENSSL_CFLAGS="-I$PREFIX/include"
export OPENSSL_LIBS="-L$PREFIX/lib -lssl -lcrypto"

# Bionic (NDK r29/API26) 兼容: 用 configure cache 变量 + 选项绕过不兼容点
#   ac_cv_header_execinfo_h=no    backtrace() 是 __INTRODUCED_IN(33)
#   ac_cv_header_glob_h=no        glob()/globfree() 是 __INTRODUCED_IN(28), 头存在性门控会硬错
#   ax_cv_PTHREAD_PRIO_INHERIT=no pthread_mutexattr_setprotocol 是 __INTRODUCED_IN(28)
#                                 (彻底关掉 mutex-posix.c 两处调用, 替代旧 sed)
#   --without-caps                Linux capabilities 不存在; 否则 configure 检测到缺
#                                 sys/capability.h + host_has_caps=1 会直接 AC_MSG_ERROR abort
#   --disable-memfd               memfd_create 是 __INTRODUCED_IN(30); 不禁用则 memfd-wrappers.h
#                                 的 static inline 与 Bionic <sys/mman.h> 声明冲突 (重定义)
ax_cv_check_cflags__pedantic__Werror__std_gnu11=yes \
ac_cv_header_execinfo_h=no \
ac_cv_header_glob_h=no \
ax_cv_PTHREAD_PRIO_INHERIT=no \
./configure --host=$ARCH-linux-android \
    --prefix=$PREFIX --libdir=$PREFIX/lib \
    --enable-shared --disable-static --with-pic \
    --without-caps --disable-memfd \
    --enable-alsa --enable-glib --enable-openssl \
    --enable-sndfile \
    --disable-bluez5 --disable-avahi --disable-dbus \
    --disable-systemd --disable-systemd-login --disable-systemd-journal \
    --disable-x11 --disable-gconf --disable-gtk3 \
    --disable-oss --disable-coreaudio --disable-waveout \
    --disable-asyncns --disable-tcpwrap --disable-lirc \
    --disable-fftw --disable-jack --disable-samplerate \
    --disable-soxr --disable-speex --disable-webrtc-aec \
    --disable-elogind --disable-gdbm --disable-tdb \
    --disable-tests --disable-man \
    --disable-esound \
    --with-database=simple \
    --with-udev-rules-dir=$PREFIX/etc/udev/rules.d \
    --with-modlibexecdir=$PREFIX/lib/pulseaudio/modules \
    --with-alsadatadir=$PREFIX/share/alsa \
    LDFLAGS="$LDFLAGS"

# 创建空 man 页面 (XML::Parser 不可用)
for f in pulseaudio.1 pax11publish.1 pacat.1 pacmd.1 pactl.1 pasuspender.1 padsp.1 \
         start-pulseaudio-x11.1 esdcompat.1 pulse-daemon.conf.5 pulse-client.conf.5 \
         default.pa.5 pulse-cli-syntax.5; do
    touch "man/$f"
done

# ---- 编译 ----
make -j$JOBS

# ---- 安装 ----
make install

# ---- 后处理: 修复模块目录 ----
# PA 13.0 的 make install 会安装到 pulse-13.0/modules/ 而不是 modlibexecdir 指定的路径
OLD_MODDIR="$PREFIX/lib/pulse-13.0/modules"
NEW_MODDIR="$PREFIX/lib/pulseaudio/modules"
if [ -d "$OLD_MODDIR" ] && [ "$OLD_MODDIR" != "$NEW_MODDIR" ]; then
    mkdir -p "$NEW_MODDIR"
    cp -f "$OLD_MODDIR"/*.so "$NEW_MODDIR/" 2>/dev/null || true
    rm -rf "$OLD_MODDIR"
fi

# ---- strip 所有库和可执行文件 ----
$STRIP "$PREFIX/lib/libpulse.so" "$PREFIX/lib/libpulse-simple.so" \
       "$PREFIX/lib/libpulse-mainloop-glib.so" \
       "$PREFIX/lib/pulseaudio/libpulsecommon"*.so \
       "$PREFIX/lib/pulseaudio/libpulsecore"*.so \
       "$PREFIX/bin/pulseaudio" 2>/dev/null || true

# strip 模块
for f in "$NEW_MODDIR"/*.so; do
    [ -f "$f" ] && $STRIP "$f" 2>/dev/null || true
done

# ---- 创建 libpulseaudio.so (daemon 重命名) ----
# 原始 winlator bionic 将 pulseaudio daemon 重命名为 libpulseaudio.so
# 放在 jniLibs 中供 Android 加载, 运行时从 pulseaudio/ 目录执行
cp -f "$PREFIX/bin/pulseaudio" "$PREFIX/lib/libpulseaudio.so"

# ---- 修复 NEEDED: 确保 libltdl.so (无版本号) ----
# 如果 libltdl 构建使用了 SONAME=libltdl.so, PA 链接时应该正确
# 但如果使用了 libltdl.so.7, 需要 patchelf 修复
PA_FIX_FILES=(
    "$PREFIX/lib/libpulse.so"
    "$PREFIX/lib/libpulse-simple.so"
    "$PREFIX/lib/libpulse-mainloop-glib.so"
    "$PREFIX/lib/pulseaudio/libpulsecommon"*.so
    "$PREFIX/lib/pulseaudio/libpulsecore"*.so
    "$PREFIX/lib/libpulseaudio.so"
)
for f in "${PA_FIX_FILES[@]}"; do
    [ -f "$f" ] || continue
    if readelf -d "$f" 2>/dev/null | grep -q 'libltdl.so.7'; then
        patchelf --replace-needed libltdl.so.7 libltdl.so "$f"
    fi
    if readelf -d "$f" 2>/dev/null | grep -q 'libsndfile.so.1'; then
        patchelf --replace-needed libsndfile.so.1 libsndfile.so "$f"
    fi
done

# 移除 .eh_frame 段以减小体积 (匹配原始)
OBJCOPY=$(dirname $CC)/llvm-objcopy
for f in "$PREFIX/lib/libpulse.so" "$PREFIX/lib/libpulse-simple.so" \
         "$PREFIX/lib/libpulse-mainloop-glib.so" \
         "$PREFIX/lib/pulseaudio/libpulsecommon"*.so \
         "$PREFIX/lib/pulseaudio/libpulsecore"*.so \
         "$PREFIX/lib/libpulseaudio.so"; do
    [ -f "$f" ] || continue
    $OBJCOPY --remove-section .eh_frame --remove-section .eh_frame_hdr "$f" 2>/dev/null || true
    $STRIP "$f" 2>/dev/null || true
done

MOD_COUNT=$(ls "$NEW_MODDIR"/*.so 2>/dev/null | wc -l)
log "  pulseaudio $VER: $MOD_COUNT modules, libpulseaudio.so daemon, SONAME/NEEDED matched"
