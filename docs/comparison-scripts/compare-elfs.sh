#!/bin/bash
OURS=/tmp/imagefs-build/imagefs/usr/lib
ORIG=/tmp/imagefs-build/original-libs

echo "============================================"
echo "  ELF COMPARISON: Original vs Our Build"
echo "============================================"

for lib in libltdl.so libsndfile.so libpulse.so libpulsecommon-13.0.so libpulsecore-13.0.so; do
    echo ""
    echo "============================================"
    echo "  $lib"
    echo "============================================"
    
    # Find our version
    OUR_FILE=""
    for f in "$OURS/$lib" "$OURS/${lib}.7" "$OURS/${lib}.1" "$OURS/${lib}.1.0.37"; do
        if [ -f "$f" ]; then
            OUR_FILE="$f"
            break
        fi
    done
    
    ORIG_FILE="$ORIG/$lib"
    
    if [ -z "$OUR_FILE" ] || [ ! -f "$OUR_FILE" ]; then
        echo "  [!] Our build: NOT FOUND"
        continue
    fi
    
    echo "  Original: $ORIG_FILE ($(stat -c%s "$ORIG_FILE") bytes)"
    echo "  Ours:     $OUR_FILE ($(stat -c%s "$OUR_FILE") bytes)"
    
    # SONAME
    ORIG_SONAME=$(readelf -d "$ORIG_FILE" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')
    OUR_SONAME=$(readelf -d "$OUR_FILE" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')
    echo "  SONAME  orig: $ORIG_SONAME"
    echo "  SONAME  ours: $OUR_SONAME"
    
    # NEEDED
    echo "  NEEDED  orig: $(readelf -d "$ORIG_FILE" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
    echo "  NEEDED  ours: $(readelf -d "$OUR_FILE" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
    
    # File type
    ORIG_TYPE=$(file -b "$ORIG_FILE" 2>/dev/null)
    OUR_TYPE=$(file -b "$OUR_FILE" 2>/dev/null)
    echo "  TYPE    orig: $ORIG_TYPE"
    echo "  TYPE    ours: $OUR_TYPE"
done

# Also check pulseaudio daemon
echo ""
echo "============================================"
echo "  PulseAudio Daemon"
echo "============================================"
echo "  Original: $ORIG/libpulseaudio.so ($(stat -c%s "$ORIG/libpulseaudio.so") bytes)"
echo "  TYPE orig: $(file -b "$ORIG/libpulseaudio.so")"
echo "  SONAME orig: $(readelf -d "$ORIG/libpulseaudio.so" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')"
echo "  NEEDED orig: $(readelf -d "$ORIG/libpulseaudio.so" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"

if [ -f "$OURS/pulseaudio" ]; then
    echo "  Ours:     $OURS/pulseaudio ($(stat -c%s "$OURS/pulseaudio") bytes)"
    echo "  TYPE ours: $(file -b "$OURS/pulseaudio")"
    echo "  NEEDED ours: $(readelf -d "$OURS/pulseaudio" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
fi

