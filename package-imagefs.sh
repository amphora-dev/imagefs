#!/usr/bin/env bash
# =============================================================================
# package-imagefs.sh — 打包 imagefs.txz (tar+xz + 分卷 + sha256)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/config.sh"

section "打包 imagefs.txz"

OUTPUT_DIR="${OUTPUT_DIR:-/workspace/winlator-imagefs-build/output}"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# ---- tar + xz ----
log "创建 tar+xz 归档..."
tar --owner=0 --group=0 -cJf "$OUTPUT_DIR/$IMAGEFS_NAME" -C "$ROOTFS" .

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

# ---- ELF 签名验证 ----
section "ELF 签名验证 (Bionic libc)"

VERIFY_COUNT=0
PASS_COUNT=0
for so in $(find "$ROOTFS/usr/lib" -name "*.so*" -type f 2>/dev/null | head -30); do
    VERIFY_COUNT=$((VERIFY_COUNT + 1))
    NEEDED=$(readelf -d "$so" 2>/dev/null | grep NEEDED | head -3)
    INTERP=$(readelf -l "$so" 2>/dev/null | grep interpreter | head -1)
    if echo "$NEEDED" | grep -q "libc.so" && ! echo "$NEEDED" | grep -q "libc.so.6"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✅ $(basename $so): $NEEDED"
    else
        echo "  ⚠️  $(basename $so): $NEEDED"
    fi
done

echo ""
log "验证: $PASS_COUNT/$VERIFY_COUNT 个 .so 正确链接 Bionic libc"

# ---- 与官方对比 ----
echo ""
echo "官方 imagefs 特征:"
echo "  - NEEDED libc.so (无 .6 后缀) = Bionic"
echo "  - .interp = /system/bin/linker64 = Android"
echo ""
echo "本构建产物特征:"
for bin in $(find "$ROOTFS/usr/bin" -type f -executable 2>/dev/null | head -5); do
    INTERP=$(readelf -l "$bin" 2>/dev/null | grep interpreter | awk '{print $NF}')
    if [ -n "$INTERP" ]; then
        echo "  $(basename $bin): .interp = $INTERP"
    fi
done
