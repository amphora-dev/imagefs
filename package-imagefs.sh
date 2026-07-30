#!/usr/bin/env bash
# =============================================================================
# package-imagefs.sh — 打包前裁剪运行时无关文件，再打 imagefs.txz
# =============================================================================
# Amphora 的 imagefs 是 **运行时 rootfs**，不是 sysroot：
#   - 头文件 / pkg-config / 静态库 / man / locale → 构建期产物，不进包
#   - box64 二进制 → 走独立 Box64.wcp，不进包
#   - glvnd 的 libGL/libGLX/… → 运行期 Mesa libGL.so.1 来自 extra_libs；
#     留在 LD_LIBRARY_PATH 还会污染系统 GLES（glColorPointerBounds）
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

section "打包 imagefs.txz"

OUTPUT_DIR="${OUTPUT_DIR:-/workspace/winlator-imagefs-build/output}"
mkdir -p "$OUTPUT_DIR"

# ---- 运行时裁剪（在 **staging 副本** 上删，保留 $ROOTFS 完整以便 CI 缓存增量重编）----
prune_runtime_rootfs() {
    local root="$1"
    section "裁剪运行时无关文件"

    local before after
    before=$(du -sm "$root" 2>/dev/null | awk '{print $1}')

    # 1) 头文件 / cmake / pkg-config（构建期）
    rm -rf \
        "$root/usr/include" \
        "$root/usr/cmake" \
        "$root/usr/lib/pkgconfig" \
        "$root/usr/lib/cmake" \
        "$root/usr/share/pkgconfig" \
        "$root/usr/share/cmake" \
        "$root/usr/share/aclocal" \
        "$root/usr/share/vala" \
        "$root/usr/local"

    # lib 下残留的 *-config.h 目录（glib/gstreamer/graphene）
    find "$root/usr/lib" -type d -name include -prune -exec rm -rf {} + 2>/dev/null || true

    # 2) 静态库 / libtool 档案
    find "$root/usr/lib" \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true

    # 3) 文档 / 本地化 / 补全 / 调试辅助
    rm -rf \
        "$root/usr/share/man" \
        "$root/usr/share/doc" \
        "$root/usr/share/info" \
        "$root/usr/share/locale" \
        "$root/usr/share/bash-completion" \
        "$root/usr/share/zsh" \
        "$root/usr/share/gdb" \
        "$root/usr/share/gettext" \
        "$root/usr/share/GConf" \
        "$root/usr/share/licenses" \
        "$root/usr/share/ffmpeg" \
        "$root/usr/share/vulkan/registry" \
        "$root/usr/share/xcb" \
        "$root/usr/share/xml" \
        "$root/usr/share/gir-1.0" \
        "$root/usr/lib/girepository-1.0"

    # 4) glvnd 运行时 .so（Mesa libGL.so.1 由 extra_libs.tzst 提供）
    #    以及指向 /system 的 EGL/GLES 软链（LD_LIBRARY_PATH 会优先命中它们）
    rm -f \
        "$root/usr/lib"/libGLdispatch.so* \
        "$root/usr/lib"/libGLESv1_CM.so* \
        "$root/usr/lib"/libGLX.so* \
        "$root/usr/lib"/libOpenGL.so* \
        "$root/usr/lib"/libGL.so \
        "$root/usr/lib"/libEGL.so \
        "$root/usr/lib"/libGLESv2.so

    # 5) 可执行文件：只留运行期可能被调用的几个小工具
    #    box64 不留 —— Amphora 用 Box64.wcp 装到 ${bindir}/box64
    if [ -d "$root/usr/bin" ]; then
        find "$root/usr/bin" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) \
            ! -name 'fc-cache' \
            ! -name 'glib-compile-schemas' \
            ! -name 'gio-querymodules' \
            -delete 2>/dev/null || true
    fi

    # 6) 断言：构建期垃圾与 box64 不得残留
    local bad=0
    if [ -d "$root/usr/include" ]; then
        error "prune failed: usr/include still present"
        bad=1
    fi
    if [ -e "$root/usr/bin/box64" ]; then
        error "prune failed: usr/bin/box64 still present (must come from Box64.wcp)"
        bad=1
    fi
    if ls "$root/usr/lib"/libGLdispatch.so* >/dev/null 2>&1; then
        error "prune failed: glvnd libGLdispatch still present"
        bad=1
    fi
    if [ "$bad" -ne 0 ]; then
        exit 1
    fi

    after=$(du -sm "$root" 2>/dev/null | awk '{print $1}')
    log "裁剪: ${before}MB → ${after}MB (staging)"
    log "  保留 bin: $(find "$root/usr/bin" -type f 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')"
    log "  .so 文件: $(find "$root/usr/lib" -name '*.so*' -type f 2>/dev/null | wc -l)"
}

STAGE="${BUILD_DIR}/imagefs-runtime-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
log "复制 rootfs → staging（保留 $ROOTFS 供增量编译）..."
cp -a "$ROOTFS"/. "$STAGE"/
prune_runtime_rootfs "$STAGE"

# verify-wine-deps 在 CI 里对 $ROOTFS 跑；同步一份「已裁剪」标记供它检查裁剪断言。
# 实际 .so 仍在未裁剪的 ROOTFS 里（verify 的 required 列表照常过）。
# 裁剪断言改查 STAGE：通过环境变量传给 verify。
export IMAGEFS_RUNTIME_STAGE="$STAGE"

cd "$BUILD_DIR"

# ---- tar + xz ----
log "创建 tar+xz 归档..."
tar --owner=0 --group=0 -cJf "$OUTPUT_DIR/$IMAGEFS_NAME" -C "$STAGE" .

# ---- sha256 ----
log "计算 SHA-256..."
cd "$OUTPUT_DIR"
sha256sum "$IMAGEFS_NAME" | awk '{print $1"  imagefs.txz"}' > "${IMAGEFS_NAME}.sha256sum"

# ---- 分卷 (与官方一致: 4 × 50MB) ----
log "分卷 (${IMAGEFS_PART_SIZE} bytes/part)..."
split -b "$IMAGEFS_PART_SIZE" -d -a 2 "$IMAGEFS_NAME" "${IMAGEFS_NAME}."

# ---- 汇总 ----
log "产物:"
ls -la "$OUTPUT_DIR"/

# ---- ELF 签名验证 (纯信息性, 失败绝不影响构建) ----
(
set +e +o pipefail
section "ELF 签名验证 (Bionic libc)"

VERIFY_COUNT=0
PASS_COUNT=0
for so in $(find "$STAGE/usr/lib" -name "*.so*" -type f 2>/dev/null | head -30); do
    VERIFY_COUNT=$((VERIFY_COUNT + 1))
    NEEDED=$(readelf -d "$so" 2>/dev/null | grep NEEDED | head -3)
    if echo "$NEEDED" | grep -q "libc.so" && ! echo "$NEEDED" | grep -q "libc.so.6"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✅ $(basename $so): $NEEDED"
    else
        echo "  ⚠️  $(basename $so): $NEEDED"
    fi
done

echo ""
log "验证: $PASS_COUNT/$VERIFY_COUNT 个 .so 正确链接 Bionic libc"
) || true

log "打包完成: $OUTPUT_DIR/$IMAGEFS_NAME"
exit 0
