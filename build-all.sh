#!/usr/bin/env bash
# =============================================================================
# build-all.sh — winlator bionic imagefs 完整构建主控
#
# 参考:
#   - MiceWine-Packages build-all.sh (包管理系统结构)
#   - 官方 imagefs ELF 取证 (Bionic libc + merged-usr + NDK r29)
#   - termux-packages (Bionic port 补丁方法论)
#
# 用法:
#   ./build-all.sh              # 构建全部包
#   ./build-all.sh zlib glib    # 仅构建指定包
#   JOBS=8 ./build-all.sh       # 指定并发数
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ---- 包列表 (按依赖拓扑排序) ----
ALL_PACKAGES=(
    # Tier 1: 无依赖的基础库
    zlib
    # zstd: 图形栈硬依赖 (libvulkan_freedreno.so 与 libGL.so.1 的 NEEDED 都要
    # libzstd.so.1, Mesa 用它做 shader cache)。首轮 42 包漏了。
    zstd
    libffi
    libexpat
    libpng
    brotli

    # Tier 2: 依赖 Tier 1
    pcre2
    freetype
    libiconv

    # Tier 3: 依赖 Tier 2
    fontconfig
    glib

    # Tier 3.5: Bionic 兼容垫片 (X11/图形库依赖)
    # 两个 shmem 实现都要, 名字与实现都不同, 官方 imagefs 里同样并存:
    #   android-sysvshm  -> libsysvshm.so + libandroid-sysvshm.so, 走
    #                       ANDROID_SYSVSHM_SERVER socket。libX11 的 MIT-SHM
    #                       路径链接期需要这些符号, 必须在 libx11 之前。
    #   libandroid-shmem -> libandroid-shmem.so, Termux 的 ASharedMemory 实现,
    #                       libGL.so.1 (Mesa/Zink) 的 NEEDED 指名要它。
    android-sysvshm
    libandroid-shmem
    # NDK C++ runtime: libvulkan_wrapper.so NEEDED。Guest LD_LIBRARY_PATH 不含
    # APK nativeLibraryDir, 必须进 imagefs (官方镜像同样带)。
    libcxx-shared

    # Tier 4: 图形/显示
    #
    # 删掉的 4 个 X 扩展 (libxcomposite/libxinerama/libxxf86vm/libxrandr) 依据:
    # Wine unix 侧 31 个 .so 里引用次数实测为 0, proton-wine configure 本身就写了
    # --without-xcomposite/xfixes/xinerama/xrandr/xrender/xshape/xxf86vm, 且
    # libvulkan_wrapper.so / libvulkan_freedreno.so / libGL.so.1 的 NEEDED 里都
    # 没有它们。(注意 libxcb-randr 等由 libxcb 包提供, 与 libxrandr 无关。)
    #
    # libxrandr 能删掉的前提是 vulkan-loader.sh 关了
    # BUILD_WSI_XLIB_XRANDR_SUPPORT —— 上游默认 ON 且对 xrandr.pc 做 REQUIRED
    # 检查, 不关就整包 configure 失败。
    #
    # libxfixes 与 libxrender **不能删**: 运行期确实无人 NEEDED, 但 libxcursor 的
    # configure 要 (xrender >= 0.8.2 xfixes x11 fixesproto)、libxi 要 (xfixes >= 5),
    # 都是构建期 pkg-config 依赖。而 libxcursor/libxi 是 Wine dlopen 的, 得留。
    # 同理 libxshmfence 与 libexpat 是 libvulkan_freedreno.so 的 NEEDED。
    #
    # libglvnd 保留, 但理由跟原注释写的不一样: 官方 imagefs 里其实只有
    # libGL.so + libGL.so.1 (Mesa 的, 来自 extra_libs.tzst 的 libGL.so.1.5.0),
    # **没有** libglvnd 的 libGLdispatch/libGLX/libOpenGL/libGLESv1_CM, 所以那
    # 几个实体库运行期没有消费者。留它是为**构建期**: 它 -Dheaders=true 提供桌面
    # GL/gl.h, 而 sdl2.sh 开了 -DSDL_OPENGL=ON。真要去掉得先把 SDL2 的桌面 GL
    # 关掉 (Wine 的 opengl32 是自己 dlopen libGL.so.1, 不经过 SDL)。
    # 运行期 libEGL/libGLESv2 不需要 imagefs 里的软链 —— LD_LIBRARY_PATH 本身就
    # 带 /system/lib64。
    xorgproto
    libxcb
    xtrans
    libx11
    libxext
    libxfixes
    libxrender
    libxcursor
    libxi
    libxshmfence
    libdrm
    vulkan-headers
    vulkan-loader
    libglvnd

    # Tier 5: 加密
    # openssl 保留: GuestProgramLauncherComponent 的 LD_PRELOAD 候选链里有
    # imagefs 的 libcrypto.so.3 (前两个候选是 /system/lib64 与 /system_ext)。
    # curl 已删: Wine 走自己的 wininet/winhttp, 图形栈也不引用 libcurl。
    openssl

    # Tier 5.5: TLS 链 — Wine 的 bcrypt/secur32 运行期 dlopen("libgnutls.so"),
    # 缺了就没有 TLS (游戏登录 / 更新检查 / 任何 HTTPS 都失败)。
    # 依赖序: gmp < nettle (libhogweed 需要 gmp) < gnutls。
    gmp
    nettle
    gnutls

    # Tier 6: 音频
    alsa-lib
    libsndfile
    libltdl
    pulseaudio
    alsa-android-aserver

    # Tier 7: 多媒体
    sdl2

    # Tier 7.5: Wine 媒体栈。
    #
    # GStreamer 是默认且完整的那条路: winegstreamer 通过 COM 注册了 Generic
    # Decodebin Byte Stream Handler (demux) + wg_h264/wmv/mp3/wma/mpeg decoder
    # + wg_h264_encoder + DirectShow filters, 并给 wmvcore 提供 sync reader。
    # winegstreamer.so 的 7 个 NEEDED 由 core + plugins-base 提供 (后者依赖前者)。
    #
    # FFmpeg 只服务 winedmo.so, 而 winedmo 只导出 winedmo_demuxer_* (只拆容器,
    # 不解码), 是 MF 的**替代** demux 后端, 需注册表
    # HKCU\Software\Wine\MediaFoundation 下 DisableGstByteStreamHandler=1 才启用。
    # 所以它是可选增强, 不是媒体播放的前提 —— 上游 imagefs 装的 FFmpeg 7.1 跟
    # winedmo 要求的 8.0 soname 对不上, winedmo 在上游镜像里一直加载不了, 镜像
    # 照常可用。要装就必须 8.0, 见 packages/ffmpeg.sh。
    gstreamer
    gst-plugins-base
    ffmpeg

    # Tier 8: Bionic 垫片（Box64.wcp 的 NEEDED；box64 本体不在本仓库构建）
    android-spawn
    android-sysv-semaphore
)

# ---- 命令行参数: 仅构建指定包 ----
if [ $# -gt 0 ]; then
    SELECTED_PACKAGES=("$@")
else
    SELECTED_PACKAGES=("${ALL_PACKAGES[@]}")
fi

# ---- 初始化 ----
section "winlator bionic imagefs 构建系统"
log "架构: $ARCH-linux-android$ANDROID_API"
log "包数量: ${#SELECTED_PACKAGES[@]}"
log "并发: $JOBS"
log "构建目录: $BUILD_DIR"

mkdir -p "$CACHE_DIR" "$SRC_DIR" "$WORK_DIR" "$LOGS_DIR" "$BUILT_DIR"

# ---- 1. 设置 NDK + 交叉编译环境 ----
source "$SCRIPT_DIR/setup-env.sh"

# ---- 2. 创建 rootfs 布局 ----
bash "$SCRIPT_DIR/create-rootfs.sh"

# 增量缓存可能留下已移出包列表的产物（如旧 box64）
rm -f "$PREFIX/bin/box64" "$BUILT_DIR/box64.done"

# ---- 3. 逐包构建 ----
section "开始编译 ${#SELECTED_PACKAGES[@]} 个包"

TOTAL=${#SELECTED_PACKAGES[@]}
CURRENT=0
SUCCESS=0
FAILED=0
FAILED_PACKAGES=()

for package in "${SELECTED_PACKAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    PKG_SCRIPT="$SCRIPT_DIR/packages/${package}.sh"

    if [ ! -f "$PKG_SCRIPT" ]; then
        error "[$CURRENT/$TOTAL] $package: 构建脚本不存在 ($PKG_SCRIPT)"
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        continue
    fi

    # ---- 增量缓存: marker 记录包脚本 hash, 脚本变了则失效重编 ----
    # marker 内容 = 包脚本的 sha256。命中条件: marker 存在且 hash 与当前脚本一致。
    # (BUILT_DIR 持久化在 CI cache volume)
    MARKER="$BUILT_DIR/${package}.done"
    PKG_HASH=$(sha256sum "$PKG_SCRIPT" 2>/dev/null | awk '{print $1}')
    if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$PKG_HASH" ]; then
        log "[$CURRENT/$TOTAL] $package: 已构建 (缓存命中), 跳过"
        SUCCESS=$((SUCCESS + 1))
        continue
    fi

    echo ""
    log "[$CURRENT/$TOTAL] 编译 $package..."

    # 执行构建
    LOG_FILE="$LOGS_DIR/${package}.log"
    ERR_FILE="$LOGS_DIR/${package}.err"

    if bash "$PKG_SCRIPT" > "$LOG_FILE" 2> "$ERR_FILE"; then
        echo "$PKG_HASH" > "$MARKER"
        SUCCESS=$((SUCCESS + 1))
        log "[$CURRENT/$TOTAL] ✅ $package 完成"
    else
        FAILED=$((FAILED + 1))
        FAILED_PACKAGES+=("$package")
        error "[$CURRENT/$TOTAL] ❌ $package 失败 (见 $ERR_FILE)"
        # ---- 诊断输出 ----
        # 关键: 真正的 make/install/link 错误在 stderr/stdout **末尾**, 不是开头
        # (开头通常是大量 configure warning, head 会把真错误挤掉)
        # 1) 先 grep 出所有关键错误行 (最快定位根因)
        echo "    ----- 关键错误行 (grep) -----"
        grep -nEi "error:|undefined reference|cannot find|No package |No such file|fatal|\*\*\* |Permission denied|not found" \
            "$ERR_FILE" "$LOG_FILE" 2>/dev/null | tail -40 | sed 's/^/    /' || echo "    (无匹配关键错误行)"
        # 2) stderr 末尾 50 行 (真正的失败点)
        echo "    ----- stderr (末尾 50 行) -----"
        tail -50 "$ERR_FILE" 2>/dev/null | sed 's/^/    /'
        # 3) stdout 末尾 20 行 (失败时正在执行的步骤)
        echo "    ----- stdout (末尾 20 行) -----"
        tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
        echo "    ----- 错误详情结束 -----"
    fi
done

# ---- 4. 汇总 ----
section "构建汇总"
log "成功: $SUCCESS / $TOTAL"
if [ $FAILED -gt 0 ]; then
    warn "失败: $FAILED (${FAILED_PACKAGES[*]})"
fi

# 统计产物
SO_COUNT=$(find "$PREFIX/lib" -name "*.so*" -type f 2>/dev/null | wc -l)
SO_LINK_COUNT=$(find "$PREFIX/lib" -name "*.so*" -type l 2>/dev/null | wc -l)
BIN_COUNT=$(find "$PREFIX/bin" -type f 2>/dev/null | wc -l)
PC_COUNT=$(find "$PREFIX/lib/pkgconfig" -name "*.pc" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$ROOTFS" 2>/dev/null | awk '{print $1}')

echo ""
echo "  .so 文件:     $SO_COUNT"
echo "  .so 软链:     $SO_LINK_COUNT"
echo "  可执行文件:   $BIN_COUNT"
echo "  pkgconfig:    $PC_COUNT"
echo "  总大小:       $TOTAL_SIZE"

# ---- 5. 打包 ----
if [ $FAILED -eq 0 ] || [ $SUCCESS -gt 5 ]; then
    bash "$SCRIPT_DIR/package-imagefs.sh"
else
    warn "失败包过多, 跳过打包。请检查日志后重试。"
fi

if command -v ccache >/dev/null 2>&1; then
    section "ccache 统计"
    ccache -s || true
fi

section "完成"
