#!/usr/bin/env bash
# =============================================================================
# package-imagefs.sh — 裁剪运行时无关文件后打包 imagefs.txz
# =============================================================================
# 运行时 rootfs，不是 sysroot。在 staging 上删构建期产物；完整 $ROOTFS 留给增量编译。
# Box64 由 Amphora 的 Box64.wcp 安装，不进本包。
# glvnd 的 libGL* 不进包（Mesa libGL.so.1 来自 extra_libs；避免污染系统 GLES）。
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

section "打包 imagefs.txz"

OUTPUT_DIR="${OUTPUT_DIR:-/workspace/winlator-imagefs-build/output}"
mkdir -p "$OUTPUT_DIR"

prune_runtime_rootfs() {
    local root="$1"
    section "裁剪运行时无关文件"

    local before after
    before=$(du -sm "$root" 2>/dev/null | awk '{print $1}')

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

    find "$root/usr/lib" -type d -name include -prune -exec rm -rf {} + 2>/dev/null || true
    find "$root/usr/lib" \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true

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

    rm -f \
        "$root/usr/lib"/libGLdispatch.so* \
        "$root/usr/lib"/libGLESv1_CM.so* \
        "$root/usr/lib"/libGLX.so* \
        "$root/usr/lib"/libOpenGL.so* \
        "$root/usr/lib"/libGL.so \
        "$root/usr/lib"/libEGL.so \
        "$root/usr/lib"/libGLESv2.so

    # App 可能调用：fc-cache / glib-compile-schemas / gio-querymodules
    if [ -d "$root/usr/bin" ]; then
        find "$root/usr/bin" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) \
            ! -name 'fc-cache' \
            ! -name 'glib-compile-schemas' \
            ! -name 'gio-querymodules' \
            -delete 2>/dev/null || true
    fi

    local bad=0
    if [ -d "$root/usr/include" ]; then
        error "prune failed: usr/include still present"
        bad=1
    fi
    if [ -e "$root/usr/bin/box64" ]; then
        error "prune failed: usr/bin/box64 still present"
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
log "复制 rootfs → staging..."
cp -a "$ROOTFS"/. "$STAGE"/
prune_runtime_rootfs "$STAGE"
export IMAGEFS_RUNTIME_STAGE="$STAGE"

cd "$BUILD_DIR"

log "创建 tar+xz 归档..."
tar --owner=0 --group=0 -cJf "$OUTPUT_DIR/$IMAGEFS_NAME" -C "$STAGE" .

log "计算 SHA-256..."
cd "$OUTPUT_DIR"
sha256sum "$IMAGEFS_NAME" | awk '{print $1"  imagefs.txz"}' > "${IMAGEFS_NAME}.sha256sum"

log "分卷 (${IMAGEFS_PART_SIZE} bytes/part)..."
split -b "$IMAGEFS_PART_SIZE" -d -a 2 "$IMAGEFS_NAME" "${IMAGEFS_NAME}."

log "产物:"
ls -la "$OUTPUT_DIR"/

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
