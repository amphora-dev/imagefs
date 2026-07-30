#!/usr/bin/env bash
# libglvnd 1.7.0 — meson (EGL/GL dispatch)
#
# 对齐官方 winlator bionic imagefs 的实际布局 (解包 imagefs.txz 取证):
#   libGLdispatch.so libGL.so libGLX.so libGLESv1_CM.so libOpenGL.so  → libglvnd 真实文件
#   libEGL.so → /system/lib64/libEGL.so      (系统软链, 运行时用手机 EGL)
#   libGLESv2.so → /system/lib64/libGLESv2.so (系统软链)
#   6 个 .pc (egl/glesv2/glesv1_cm/gl/glx/opengl) 全部安装 → 全功能编译
#   所有库无版本号后缀 (.so)
#
# 关键: create-rootfs.sh 预先创建了 libEGL.so/libGLESv2.so 指向 /system/lib64 的软链,
# 在 CI 构建机上是 dangling symlink。meson install 时以 'wb' 打开该软链会触发
# FileNotFoundError。因此 install 前删除占位软链, install 后再重建系统软链。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="1.7.0"
PKG_NAME="libglvnd-v$VER"
SRC_URL="https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v$VER/libglvnd-v$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" libglvnd.tar.gz "$SRC_URL"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 移除 create-rootfs.sh 预置的占位软链 (dangling, 会让 meson install 失败)
rm -f "$PREFIX/lib/libEGL.so" "$PREFIX/lib/libGLESv2.so"

# 全功能编译 (egl/gles1/gles2/glx 全开), 匹配官方 6 个 .pc。
# glx=enabled: 官方有 libGLX.so (winlator 经 box64 跑 x86 Linux 程序需要 GLX)
meson setup --cross-file="$CROSS_FILE" \
    -Dprefix=$PREFIX -Dlibdir=$PREFIX/lib -Dbuildtype=release \
    -Ddefault_library=shared \
    -Dglx=enabled \
    -Degl=true \
    -Dgles1=true \
    -Dgles2=true \
    -Dasm=disabled \
    -Dtls=false \
    -Dheaders=true ..
ninja -j$JOBS
ninja install

# ---- 去版本号: 官方所有 GL 库均为无后缀 .so ----
# meson version:'N.M.K' 生成 libFoo.so.N.M.K(实体) + libFoo.so.N + libFoo.so(软链)。
# 把实体改名为无版本号的 libFoo.so。注意: 先把实体挪到临时名再删软链, 否则
# readlink 拿到实体后 rm .so* 会把实体一起删掉 → mv cannot stat。
for base in GLdispatch GL GLX GLESv1_CM OpenGL EGL GLESv2; do
    link="$PREFIX/lib/lib${base}.so"
    [ -e "$link" ] || continue
    real=$(readlink -f "$link" 2>/dev/null || true)
    [ -n "$real" ] && [ -f "$real" ] || continue
    if [ "$real" != "$link" ]; then
        mv -f "$real" "$link.real"        # 实体挪走 (软链此刻悬空)
        rm -f "$link" "$link".[0-9]*      # 删软链和 .so.N 等残留
        mv -f "$link.real" "$link"        # 实体放回无版本名
    fi
done

# ---- 用系统软链覆盖 libEGL.so / libGLESv2.so (匹配官方: 运行时用手机库) ----
rm -f "$PREFIX/lib/libEGL.so" "$PREFIX/lib/libGLESv2.so"
ln -sf /system/lib64/libEGL.so    "$PREFIX/lib/libEGL.so"
ln -sf /system/lib64/libGLESv2.so "$PREFIX/lib/libGLESv2.so"

$STRIP "$PREFIX/lib/libGL.so" "$PREFIX/lib/libGLX.so" \
       "$PREFIX/lib/libGLdispatch.so" "$PREFIX/lib/libOpenGL.so" \
       "$PREFIX/lib/libGLESv1_CM.so" 2>/dev/null || true

log "  libglvnd $VER: $(ls $PREFIX/lib/lib{GL,GLX,GLdispatch,OpenGL,GLESv1_CM}.so 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
log "  libEGL.so/libGLESv2.so → /system/lib64 (系统软链)"
