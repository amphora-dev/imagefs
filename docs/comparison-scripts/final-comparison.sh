#!/bin/bash
# 最终全面对比: 原始 vs 我们的构建
set -euo pipefail

OURS=/tmp/imagefs-build/imagefs/usr
ORIG=/tmp/imagefs-build/original-libs
ORIG_MODS=/tmp/imagefs-build/original-pulseaudio/modules/arm64
OUR_MODS=$OURS/lib/pulseaudio/modules

echo "================================================================"
echo "  FINAL COMPARISON: Original winlator bionic vs Our Build"
echo "================================================================"

echo ""
echo "============================================"
echo "  1. Core Library SONAME Comparison"
echo "============================================"
printf "%-30s %-20s %-20s %s\n" "Library" "Original SONAME" "Our SONAME" "Status"
printf "%-30s %-20s %-20s %s\n" "-------" "--------------" "----------" "------"

for lib in libltdl.so libsndfile.so libpulse.so; do
    O=$(readelf -d "$ORIG/$lib" 2>/dev/null | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/' || echo "none")
    U=$(readelf -d "$OURS/lib/$lib" 2>/dev/null | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/' || echo "none")
    [ "$O" = "$U" ] && S="✅" || S="⚠️"
    printf "%-30s %-20s %-20s %s\n" "$lib" "$O" "$U" "$S"
done

for lib in libpulsecommon-13.0.so libpulsecore-13.0.so; do
    O=$(readelf -d "$ORIG/$lib" 2>/dev/null | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/' || echo "none")
    U=$(readelf -d "$OURS/lib/pulseaudio/$lib" 2>/dev/null | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/' || echo "none")
    [ "$O" = "$U" ] && S="✅" || S="⚠️"
    printf "%-30s %-20s %-20s %s\n" "$lib" "$O" "$U" "$S"
done

echo ""
echo "============================================"
echo "  2. NEEDED Comparison"
echo "============================================"

declare -A LIB_PATHS=(
    [libltdl.so]="$OURS/lib/libltdl.so"
    [libsndfile.so]="$OURS/lib/libsndfile.so"
    [libpulse.so]="$OURS/lib/libpulse.so"
    [libpulsecommon-13.0.so]="$OURS/lib/pulseaudio/libpulsecommon-13.0.so"
    [libpulsecore-13.0.so]="$OURS/lib/pulseaudio/libpulsecore-13.0.so"
    [libpulseaudio.so]="$OURS/lib/libpulseaudio.so"
)

for lib in libltdl.so libsndfile.so libpulse.so libpulsecommon-13.0.so libpulsecore-13.0.so; do
    echo ""
    echo "--- $lib ---"
    if [ "$lib" = "libpulseaudio.so" ] || [ "$lib" = "libpulsecommon-13.0.so" ] || [ "$lib" = "libpulsecore-13.0.so" ]; then
        O_PATH="$ORIG/$lib"
        U_PATH="${LIB_PATHS[$lib]}"
    elif [ "$lib" = "libpulsecommon-13.0.so" ] || [ "$lib" = "libpulsecore-13.0.so" ]; then
        O_PATH="$ORIG/$lib"
        U_PATH="${LIB_PATHS[$lib]}"
    else
        O_PATH="$ORIG/$lib"
        U_PATH="${LIB_PATHS[$lib]}"
    fi
    
    O_NEEDED=$(readelf -d "$O_PATH" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\].*/\1/' | sort | tr '\n' ' ')
    U_NEEDED=$(readelf -d "$U_PATH" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\].*/\1/' | sort | tr '\n' ' ')
    
    echo "  Orig: $O_NEEDED"
    echo "  Ours: $U_NEEDED"
    [ "$O_NEEDED" = "$U_NEEDED" ] && echo "  Status: ✅ Match" || echo "  Status: ⚠️ Differs"
done

echo ""
echo "--- libpulseaudio.so (daemon) ---"
O_NEEDED=$(readelf -d "$ORIG/libpulseaudio.so" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\].*/\1/' | sort | tr '\n' ' ')
U_NEEDED=$(readelf -d "$OURS/lib/libpulseaudio.so" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\].*/\1/' | sort | tr '\n' ' ')
echo "  Orig: $O_NEEDED"
echo "  Ours: $U_NEEDED"
[ "$O_NEEDED" = "$U_NEEDED" ] && echo "  Status: ✅ Match" || echo "  Status: ⚠️ Differs"

echo ""
echo "============================================"
echo "  3. Size Comparison"
echo "============================================"
printf "%-30s %-12s %-12s %-12s %s\n" "Library" "Original" "Ours" "Ratio" "Status"
printf "%-30s %-12s %-12s %-12s %s\n" "-------" "--------" "----" "-----" "------"

for lib in libltdl.so libsndfile.so libpulse.so libpulsecommon-13.0.so libpulsecore-13.0.so libpulseaudio.so; do
    if [ "$lib" = "libpulsecommon-13.0.so" ] || [ "$lib" = "libpulsecore-13.0.so" ]; then
        O_SIZE=$(stat -c%s "$ORIG/$lib" 2>/dev/null || echo 0)
        U_SIZE=$(stat -c%s "$OURS/lib/pulseaudio/$lib" 2>/dev/null || echo 0)
    elif [ "$lib" = "libpulseaudio.so" ]; then
        O_SIZE=$(stat -c%s "$ORIG/$lib" 2>/dev/null || echo 0)
        U_SIZE=$(stat -c%s "$OURS/lib/$lib" 2>/dev/null || echo 0)
    else
        O_SIZE=$(stat -c%s "$ORIG/$lib" 2>/dev/null || echo 0)
        U_SIZE=$(stat -c%s "$OURS/lib/$lib" 2>/dev/null || echo 0)
    fi
    
    RATIO=$(echo "scale=2; $U_SIZE / $O_SIZE" | bc 2>/dev/null || echo "?")
    
    # 状态判断: <1.5x ✅, <3x ⚠️, >=3x ❌
    if [ "$O_SIZE" -gt 0 ] 2>/dev/null; then
        THRESHOLD=$(echo "$U_SIZE < $O_SIZE * 3 / 2" | bc 2>/dev/null || echo 0)
        if [ "$THRESHOLD" = "1" ]; then S="✅"
        else
            THRESHOLD2=$(echo "$U_SIZE < $O_SIZE * 3" | bc 2>/dev/null || echo 0)
            [ "$THRESHOLD2" = "1" ] && S="⚠️" || S="❌"
        fi
    else
        S="—"
    fi
    
    printf "%-30s %-12s %-12s %-12s %s\n" "$lib" "${O_SIZE}" "${U_SIZE}" "${RATIO}x" "$S"
done

echo ""
echo "============================================"
echo "  4. Module Count Comparison"
echo "============================================"
O_MOD_COUNT=$(ls "$ORIG_MODS"/*.so 2>/dev/null | wc -l)
U_MOD_COUNT=$(ls "$OUR_MODS"/*.so 2>/dev/null | wc -l)
echo "  Original modules: $O_MOD_COUNT"
echo "  Our modules:      $U_MOD_COUNT"

# 对比模块列表
ls "$ORIG_MODS" 2>/dev/null | sort > /tmp/orig_mods_final.txt
ls "$OUR_MODS" 2>/dev/null | sort > /tmp/our_mods_final.txt
MISSING=$(comm -23 /tmp/orig_mods_final.txt /tmp/our_mods_final.txt | wc -l)
EXTRA=$(comm -13 /tmp/orig_mods_final.txt /tmp/our_mods_final.txt | wc -l)
echo "  Missing (in orig, not ours): $MISSING"
echo "  Extra (in ours, not orig):   $EXTRA"
if [ $MISSING -gt 0 ]; then
    echo "  Missing modules:"
    comm -23 /tmp/orig_mods_final.txt /tmp/our_mods_final.txt | sed 's/^/    - /'
fi
if [ $EXTRA -gt 0 ]; then
    echo "  Extra modules:"
    comm -13 /tmp/orig_mods_final.txt /tmp/our_mods_final.txt | sed 's/^/    - /'
fi

echo ""
echo "============================================"
echo "  5. Additional Components"
echo "============================================"
echo "  ALSA android_aserver plugin: $([ -f "$OURS/lib/asound_module_pcm_android_aserver.so" ] && echo '✅ present' || echo '❌ missing')"
echo "  ALSA config (alsa.conf):     $([ -f "/tmp/imagefs-build/imagefs/etc/alsa/alsa.conf" ] && echo '✅ present' || echo '❌ missing')"
echo "  ALSA config (aserver.conf):  $([ -f "/tmp/imagefs-build/imagefs/etc/alsa/conf.d/android_aserver.conf" ] && echo '✅ present' || echo '❌ missing')"
echo "  libsysvshm.so:               $([ -f "$OURS/lib/libsysvshm.so" ] && echo '✅ present' || echo '❌ missing')"
echo "  libpulseaudio.so (daemon):   $([ -f "$OURS/lib/libpulseaudio.so" ] && echo '✅ present' || echo '❌ missing')"

echo ""
echo "============================================"
echo "  6. ELF Verification"
echo "============================================"
# 验证所有 ELF 文件使用 Bionic linker
BAD=0
TOTAL=0
for f in $(find /tmp/imagefs-build/imagefs -type f -exec file {} \; 2>/dev/null | grep "ELF.*aarch64" | cut -d: -f1); do
    TOTAL=$((TOTAL+1))
    INTERP=$(readelf -l "$f" 2>/dev/null | grep "interpreter" | head -1 || true)
    if echo "$INTERP" | grep -qv "linker64" && [ -n "$INTERP" ]; then
        BAD=$((BAD+1))
    fi
done
echo "  Total ELF files: $TOTAL"
echo "  Using /system/bin/linker64: $((TOTAL-BAD))"
if [ $BAD -gt 0 ]; then
    echo "  Wrong interpreter: $BAD"
else
    echo "  ✅ All ELF files use Bionic linker"
fi
