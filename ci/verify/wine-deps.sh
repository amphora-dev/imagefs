#!/usr/bin/env bash
# 断言 imagefs 提供了它的消费者实际需要的库, 且 soname 精确匹配。
#
# 消费者不只有 Wine。imagefs 还要喂图形栈:
#   libGL.so.1              (本包 mesa-gl)     Mesa/Zink — 自建, 已在 imagefs 内
#   libvulkan_wrapper.so    (wrapper.tzst)     adrenotools 包装的 Vulkan
#   libvulkan_freedreno.so  (可选 WN-Turnip)   Turnip
#
# 期望值的来源 (可复核):
#   readelf -dW <proton>/lib/wine/x86_64-unix/*.so | grep NEEDED           # Wine 硬依赖
#   strings -a <proton>/lib/wine/x86_64-unix/*.so | grep -oE '^lib.*\.so'  # Wine dlopen
#   objdump -p <proton>/lib/wine/x86_64-windows/*.dll | grep 'DLL Name'    # 谁消费
#   readelf -dW <解开的 wrapper.tzst>/usr/lib/*.so                         # 图形栈
#
# 分两级, 因为「是 NEEDED」不等于「不可缺」: unixlib 按需加载, 所以某个 unixlib
# 的 NEEDED 缺失只会让那一个 Wine 模块用不了, 而不是拖垮启动。
set -euo pipefail

# Repo root (ci/verify → ../..), same pattern as pkg-selftest.sh.
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

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
  # 自建 Mesa GL (packages/graphics/mesa-gl.sh): Wine opengl32 → WineD3D → zink
  # 的入口, 缺了 OpenGL/DX7 直接黑屏。Wine >=10.17 走 libEGL, 更早走 libGL。
  "libEGL.so.1:Wine >=10.17 win32u → EGL x11 → zink"
  "libGL.so.1:旧 Wine opengl32/ddraw → GLX → zink"
  "libzstd.so.1:Mesa GL + Turnip (Mesa shader cache)"
  "libandroid-shmem.so:Mesa GL — XShm (Bionic 无 SysV shm)"
  "libandroid-sysvshm.so:libvulkan_wrapper.so + Turnip + GPLC 的 LD_PRELOAD"
  "libc++_shared.so:libvulkan_wrapper.so — Guest LD_LIBRARY_PATH 不含 nativeLibraryDir"
  "libdrm.so:libvulkan_wrapper.so + Turnip + libGL.so.1"
  "libX11-xcb.so:libvulkan_wrapper.so + Turnip + Mesa EGL x11"
  "libxcb.so:libvulkan_wrapper.so + Turnip + Mesa EGL x11"
  "libxcb-dri3.so:libvulkan_wrapper.so + Turnip + Mesa EGL DRI3 呈现"
  "libxcb-present.so:libvulkan_wrapper.so + Turnip + Mesa EGL DRI3 呈现"
  "libxcb-sync.so:libvulkan_wrapper.so + Turnip + Mesa EGL fence"
  "libxcb-randr.so:libvulkan_wrapper.so + Turnip + Mesa EGL x11"
  "libxcb-shm.so:libvulkan_wrapper.so + Turnip + Mesa EGL swrast 回退"
  "libxcb-xfixes.so:Mesa EGL — x11_dri3_open 会无条件解引用 xfixes 应答"
  "libxshmfence.so:Turnip + Mesa DRI3 loader — 看着像可省, 实际是 NEEDED"
  "libexpat.so.1:Turnip + fontconfig"
  "libz.so:libGL.so.1 (NEEDED 无版本号)"
  "libz.so.1:Turnip"
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
  if [ -e "$PRUNE_ROOT/usr/lib/libGL.so.1" ]; then
    echo "  OK      libGL.so.1 (mesa-gl)"
  else
    echo "  MISSING libGL.so.1 — Wine OpenGL/DX7 会黑屏" >&2
    fail=1
  fi
  # Wine >=10.17 (Proton 11) 的 win32u dlopen 的是 libEGL.so.1，不是 libGL。
  if [ -e "$PRUNE_ROOT/usr/lib/libEGL.so.1" ]; then
    echo "  OK      libEGL.so.1 (mesa-gl, Wine >=10.17 GL 路径)"
  else
    echo "  MISSING libEGL.so.1 — Proton 11 会退回 GLX 并因缺 GLX 扩展而关掉 OpenGL" >&2
    fail=1
  fi
  # zink 在 DRI 前端里位于 megadriver，不在 libGL 内。
  megadriver="$(ls "$PRUNE_ROOT/usr/lib"/libgallium*.so 2>/dev/null | head -1)"
  if [ -n "$megadriver" ] && grep -q 'ZINK:' "$megadriver"; then
    if [ -e "$PRUNE_ROOT/usr/lib/.libgl-zink" ]; then
      echo "  OK      .libgl-zink 与 megadriver 内的 zink 一致"
    else
      echo "  MISSING usr/lib/.libgl-zink — Amphora 会退回软件光栅化" >&2
      fail=1
    fi
  else
    echo "  MISSING megadriver 里没有 zink — GL 只剩 softpipe" >&2
    fail=1
  fi
  # extra_libs.tzst 已废止, 它的其余内容不该被顺手搬进 imagefs。
  for stray in libvulkan_freedreno.so libvkbasalt.so libbcn_layer.so; do
    if [ -e "$PRUNE_ROOT/usr/lib/$stray" ]; then
      echo "  UNEXPECTED $stray (extra_libs 内容不入 imagefs)" >&2
      fail=1
    fi
  done
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

section "ELF LOAD 段页对齐同余 (patchelf 事后改写会破坏)"
# p_vaddr 与 p_offset 必须模页大小同余, 否则设备把 .dynstr 映射到错位置:
# 运行期按 DT_STRTAB 读出的 verneed/verdef 名字变成乱码 (真实事故:
# libpng 被 patchelf --set-soname 后报 cannot find "_chunk_fn" from verneed[0],
# 连累 libfreetype 加载失败 → Wine 无字体 → 窗口全白)。
# readelf 走 section header 看不出来, 只有真机 dlopen 会炸, 所以在这里断言。
load_segments_congruent() {
  # readelf -lW: "LOAD  0x031508 0x0000000000040000 ..." → (vaddr - offset) % page
  local off va
  while read -r off va; do
    [ -n "$off" ] || continue
    (( ((va - off) % 4096) == 0 )) || return 1
  done < <(readelf -lW "$1" 2>/dev/null | awk '$1 == "LOAD" { print $2, $3 }')
  return 0
}

misaligned=0
while IFS= read -r so; do
  if ! load_segments_congruent "$so"; then
    echo "  BAD     $(basename "$so") — LOAD p_vaddr/p_offset 不同余" >&2
    misaligned=$((misaligned + 1))
  fi
done < <(find "$LIB" -name '*.so*' -type f 2>/dev/null)
if [ "$misaligned" -ne 0 ]; then
  fail=1
else
  echo "  OK      所有 .so 的 LOAD 段同余"
fi

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
