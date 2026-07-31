#!/usr/bin/env bash
# 断言 imagefs 提供了它的消费者实际需要的库, 且 soname 精确匹配。
#
# 消费者不只有 Wine。imagefs 还要喂图形栈 —— 那些库由 runtimeAssets 提供
# (wrapper.tzst / extra_libs.tzst), 但它们的 NEEDED 是从 imagefs/usr/lib 解析的:
#   libvulkan_wrapper.so    (wrapper.tzst)     adrenotools 包装的 Vulkan
#   libvulkan_freedreno.so  (extra_libs.tzst)  Turnip
#   libGL.so.1              (extra_libs.tzst)  Mesa/Zink
#
# 期望值的来源 (可复核):
#   readelf -dW <proton>/lib/wine/x86_64-unix/*.so | grep NEEDED           # Wine 硬依赖
#   strings -a <proton>/lib/wine/x86_64-unix/*.so | grep -oE '^lib.*\.so'  # Wine dlopen
#   objdump -p <proton>/lib/wine/x86_64-windows/*.dll | grep 'DLL Name'    # 谁消费
#   readelf -dW <解开的 wrapper.tzst / extra_libs.tzst>/usr/lib/*.so       # 图形栈
#
# 分两级, 因为「是 NEEDED」不等于「不可缺」: unixlib 按需加载, 所以某个 unixlib
# 的 NEEDED 缺失只会让那一个 Wine 模块用不了, 而不是拖垮启动。
set -euo pipefail
source "$(dirname "$0")/../config.sh"

LIB="$ROOTFS/usr/lib"
fail=0

# ---- 必需: 缺了影响基本使用 ----
# 格式: <文件名>:<消费者/影响>
required=(
  "libX11.so:winex11.so — 没有它就没有显示"
  "libXext.so:winex11.so + libGL.so.1"
  "libasound.so:winealsa.so — ALSA 是 MVP 的音频路径"
  "libglib-2.0.so:多个 unix 模块"
  "libgobject-2.0.so:多个 unix 模块"
  "libgio-2.0.so:多个 unix 模块"
  # 图形栈的 NEEDED。这几项缺了不是降级, 是 Vulkan/OpenGL 驱动直接加载失败,
  # 表现为黑屏而非报错, 所以必须断言。
  "libzstd.so.1:libvulkan_freedreno.so + libGL.so.1 (Mesa shader cache)"
  "libandroid-shmem.so:libGL.so.1 — Termux ASharedMemory 实现"
  "libandroid-sysvshm.so:libvulkan_wrapper.so + Turnip + GPLC 的 LD_PRELOAD"
  "libc++_shared.so:libvulkan_wrapper.so — Guest LD_LIBRARY_PATH 不含 nativeLibraryDir"
  "libdrm.so:libvulkan_wrapper.so + Turnip + libGL.so.1"
  "libX11-xcb.so:libvulkan_wrapper.so + Turnip"
  "libxcb.so:libvulkan_wrapper.so + Turnip"
  "libxcb-dri3.so:libvulkan_wrapper.so + Turnip"
  "libxcb-present.so:libvulkan_wrapper.so + Turnip"
  "libxcb-sync.so:libvulkan_wrapper.so + Turnip"
  "libxcb-randr.so:libvulkan_wrapper.so + Turnip"
  "libxcb-shm.so:libvulkan_wrapper.so + Turnip"
  "libxshmfence.so:Turnip — 看着像可省, 实际是 NEEDED"
  "libexpat.so.1:Turnip + fontconfig"
  "libz.so.1:Turnip + libGL.so.1"
  # gnutls 是 dlopen 而非 NEEDED, 但影响面比任何 NEEDED 都大: Wine 的
  # bcrypt/secur32 靠它做 TLS, 缺了游戏登录/更新检查/任何 HTTPS 全废。
  "libgnutls.so:bcrypt/secur32 的 TLS — 缺了没有 HTTPS"
  "libgmp.so:gnutls 依赖链"
  # winegstreamer 是 Wine 媒体的默认且完整路径: 通过 COM 注册了
  # Generic Decodebin Byte Stream Handler (demux) + wg_h264/wmv/mp3/wma/mpeg
  # decoder + wg_h264_encoder + DirectShow filters, 还给 wmvcore 提供
  # winegstreamer_create_wm_sync_reader。
  "libgstreamer-1.0.so:winegstreamer.so — 媒体默认路径"
  "libgstbase-1.0.so:winegstreamer.so"
  "libgstapp-1.0.so:winegstreamer.so"
  "libgstaudio-1.0.so:winegstreamer.so"
  "libgstvideo-1.0.so:winegstreamer.so"
  "libgsttag-1.0.so:winegstreamer.so"
  "libgstgl-1.0.so:winegstreamer.so"
)

# ---- 可选: 缺了功能降级, 有明确回退路径 ----
optional=(
  "libfreetype.so:字体"
  "libfontconfig.so:字体配置"
  "libvulkan.so.1:Vulkan"
  "libSDL2-2.0.so:手柄/输入"
  "libXi.so:X 输入扩展"
  "libXcursor.so:X 光标"
)

# ---- 打包裁剪断言（仅当 package-imagefs 设置了 IMAGEFS_RUNTIME_STAGE）----
section "运行时裁剪断言"
if [ -n "${IMAGEFS_RUNTIME_STAGE:-}" ]; then
  PRUNE_ROOT="$IMAGEFS_RUNTIME_STAGE"
  if [ -d "$PRUNE_ROOT/usr/include" ]; then
    echo "  UNEXPECTED usr/include" >&2
    fail=1
  else
    echo "  OK      no usr/include"
  fi
  if [ -e "$PRUNE_ROOT/usr/bin/box64" ]; then
    echo "  UNEXPECTED usr/bin/box64" >&2
    fail=1
  else
    echo "  OK      no usr/bin/box64"
  fi
  if ls "$PRUNE_ROOT/usr/lib"/libGLdispatch.so* >/dev/null 2>&1; then
    echo "  UNEXPECTED libGLdispatch" >&2
    fail=1
  else
    echo "  OK      no glvnd libGLdispatch"
  fi
else
  echo "  SKIP    IMAGEFS_RUNTIME_STAGE unset"
fi

# ---- 已确认无消费者: 若重新出现在 rootfs 里, 说明有人又把它加回来了 ----
unused=(
  "libXrandr.so" "libXcomposite.so" "libXinerama.so" "libXxf86vm.so"
  "libharfbuzz.so" "libxml2.so" "libcurl.so"
  "libpulse.so" "libGLdispatch.so" "libavcodec.so"
)

section "验证必需依赖"
for entry in "${required[@]}"; do
  name="${entry%%:*}"
  who="${entry#*:}"
  if [ -e "$LIB/$name" ]; then
    echo "  OK      $name  ($who)"
  else
    echo "  MISSING $name  ($who)" >&2
    fail=1
  fi
done

section "验证可选依赖"
for entry in "${optional[@]}"; do
  name="${entry%%:*}"
  who="${entry#*:}"
  if [ -e "$LIB/$name" ]; then
    echo "  OK      $name  ($who)"
  else
    echo "  WARN    $name  ($who) — 功能降级" >&2
  fi
done

section "已判定无消费者的库 (若出现说明被重新引入)"
extra=0
for name in "${unused[@]}"; do
  if [ -e "$LIB/$name" ]; then
    echo "  UNEXPECTED $name — 见 build-all.sh Tier 4 注释, 确认是否真有消费者"
    extra=$((extra + 1))
  fi
done
[ "$extra" -eq 0 ] && echo "  (无)"

section "libzstd SONAME (Turnip NEEDED libzstd.so.1)"
zstd="$LIB/libzstd.so"
if [ -e "$zstd" ] || [ -e "$LIB/libzstd.so.1" ]; then
  target="$zstd"
  [ -e "$target" ] || target="$LIB/libzstd.so.1"
  soname=$(readelf -dW "$target" 2>/dev/null | awk -F'[][]' '/SONAME/{print $2}')
  if [ "$soname" = "libzstd.so.1" ]; then
    echo "  OK      SONAME=$soname"
  else
    echo "  BAD     SONAME='$soname' (expected libzstd.so.1)" >&2
    fail=1
  fi
fi

section "libandroid-sysvshm 符号 (wrapper 解析 libandroid_shm*)"
# 自建曾只导出 shmget 等, wrapper 需要 libandroid_shmget → ICD 加载失败 → -9。
sysvshm="$LIB/libandroid-sysvshm.so"
if [ -e "$sysvshm" ]; then
  for sym in libandroid_shmget libandroid_shmat libandroid_shmdt libandroid_shmctl; do
    if readelf -Ws "$sysvshm" 2>/dev/null | awk '{print $8}' | grep -qx "$sym"; then
      echo "  OK      $sym"
    else
      echo "  MISSING $sym  (wrapper ICD will fail to dlopen)" >&2
      fail=1
    fi
  done
else
  echo "  SKIP    libandroid-sysvshm.so missing (already reported above)" >&2
fi

if [ "$fail" -ne 0 ]; then
  echo >&2
  echo "有硬依赖缺失: 对应的 Wine unix 模块会加载失败。" >&2
  exit 1
fi

echo
log "Wine 依赖验证通过"
