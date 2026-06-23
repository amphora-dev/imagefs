#!/bin/bash
# 修复 imagefs 中所有 PulseAudio 相关库的 SONAME 和 NEEDED 差异
set -euo pipefail

PREFIX=/tmp/imagefs-build/imagefs/usr
NDK=/tmp/imagefs-build/cache/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64
CC=$NDK/bin/aarch64-linux-android26-clang
STRIP=$NDK/bin/llvm-strip
LIBDIR=$PREFIX/lib
PADIR=$LIBDIR/pulseaudio
BINDIR=$PREFIX/bin

echo "============================================"
echo "  Fix 1: Rebuild libltdl.so (SONAME=libltdl.so)"
echo "============================================"

# 移除旧的符号链接和 .so.7 文件
rm -f "$LIBDIR/libltdl.so" "$LIBDIR/libltdl.so.7"

# 使用相同的 stub 源码重新编译，但 SONAME 改为 libltdl.so
cat > /tmp/libltdl_stub_fix.c << 'STUBSRC'
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
typedef void *lt_dlhandle; typedef void *lt_ptr; typedef void *lt_module;
typedef void *lt_user_data; typedef void *lt_dlloader; typedef void *lt_dladvise;
typedef struct { const char *name; lt_ptr address; } lt_dlsymlist;
const lt_dlsymlist lt_preloaded_symbols[] = { {0, 0} };
typedef lt_module (*lt_module_open_t)(const char *, lt_dladvise, lt_user_data);
typedef int (*lt_module_close_t)(lt_module, lt_user_data);
typedef void *(*lt_find_sym_t)(lt_module, const char *, lt_user_data);
typedef int (*lt_dlloader_exit_t)(lt_user_data);
typedef struct { const char *name; lt_module_open_t module_open; lt_module_close_t module_close;
    lt_find_sym_t find_sym; lt_dlloader_exit_t dlloader_exit; lt_user_data dlloader_data; int priority; } lt_dlvtable;
static char last_error[256] = {0};
int lt_dlinit(void) { return 0; }
int lt_dlexit(void) { return 0; }
lt_dlhandle lt_dlopen(const char *f) { void *h = dlopen(f, RTLD_NOW|RTLD_LOCAL); if(!h) strncpy(last_error, dlerror(), 255); return h; }
lt_dlhandle lt_dlopenext(const char *f) { void *h = dlopen(f, RTLD_NOW|RTLD_LOCAL); if(!h){char b[1024];snprintf(b,1024,"%s.so",f);h=dlopen(b,RTLD_NOW|RTLD_LOCAL);} if(!h) strncpy(last_error,dlerror(),255); return h; }
void *lt_dlsym(lt_dlhandle h, const char *s) { return dlsym(h, s); }
int lt_dlclose(lt_dlhandle h) { return dlclose(h); }
const char *lt_dlerror(void) { const char *e=dlerror(); if(e) return e; if(last_error[0]){const char *r=last_error;last_error[0]=0;return r;} return NULL; }
const char *lt_dlgetsearchpath(void) { return NULL; }
int lt_dlsetsearchpath(const char *s) { return 0; }
int lt_dladdsearchdir(const char *s) { return 0; }
int lt_dlinsertsearchdir(const char *b, const char *s) { return 0; }
int lt_dlforeachfile(const char *s, int (*f)(const char *, lt_ptr), lt_ptr d) { return 0; }
int lt_dladderror(const char *s) { return 0; }
int lt_dlseterror(int e) { return 0; }
static lt_dlvtable loaders[16]; static int nloaders=0;
int lt_dlloader_add(const lt_dlvtable *v) { if(nloaders<16&&v){loaders[nloaders++]=*v;return 0;} return -1; }
const lt_dlvtable *lt_dlloader_find(const char *n) { for(int i=0;i<nloaders;i++) if(loaders[i].name&&!strcmp(loaders[i].name,n)) return &loaders[i]; return NULL; }
lt_dlvtable *lt_dlloader_remove(const char *n) { return NULL; }
lt_dlloader lt_dlloader_next(const lt_dlloader l) { return NULL; }
const lt_dlvtable *lt_dlloader_get(lt_dlloader l) { return NULL; }
int lt_dladvise_init(lt_dladvise *a) { *a=NULL; return 0; }
int lt_dladvise_destroy(lt_dladvise *a) { *a=NULL; return 0; }
int lt_dladvise_ext(lt_dladvise *a) { return 0; }
int lt_dladvise_global(lt_dladvise *a) { return 0; }
int lt_dladvise_local(lt_dladvise *a) { return 0; }
int lt_dladvise_resident(lt_dladvise *a) { return 0; }
int lt_dladvise_preload(lt_dladvise *a) { return 0; }
STUBSRC

$CC -fPIC -O2 -shared -o "$LIBDIR/libltdl.so" /tmp/libltdl_stub_fix.c \
    -I"$PREFIX/include" -Wl,-soname,libltdl.so -Wl,-rpath,/usr/lib -ldl
$STRIP "$LIBDIR/libltdl.so"
echo "  ✅ libltdl.so rebuilt: SONAME=$(readelf -d "$LIBDIR/libltdl.so" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')"

echo ""
echo "============================================"
echo "  Fix 2: libsndfile.so SONAME → libsndfile.so"
echo "============================================"

# 找到真实文件并修改 SONAME
SNDFILE_REAL=$(readlink -f "$LIBDIR/libsndfile.so" 2>/dev/null || echo "$LIBDIR/libsndfile.so")
if [ -f "$SNDFILE_REAL" ]; then
    patchelf --set-soname libsndfile.so "$SNDFILE_REAL"
    # 如果真实文件不是 libsndfile.so，则复制过去
    if [ "$SNDFILE_REAL" != "$LIBDIR/libsndfile.so" ]; then
        cp -f "$SNDFILE_REAL" "$LIBDIR/libsndfile.so"
        rm -f "$LIBDIR/libsndfile.so.1" "$LIBDIR/libsndfile.so.1.0.37" "$SNDFILE_REAL"
    fi
    $STRIP "$LIBDIR/libsndfile.so" 2>/dev/null || true
    echo "  ✅ libsndfile.so: SONAME=$(readelf -d "$LIBDIR/libsndfile.so" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')"
else
    echo "  ⚠️ libsndfile.so not found!"
fi

echo ""
echo "============================================"
echo "  Fix 3: Fix NEEDED entries (libltdl.so.7→libltdl.so, libsndfile.so.1→libsndfile.so)"
echo "============================================"

# 需要修复 NEEDED 的所有 ELF 文件
FIX_FILES=(
    "$LIBDIR/libpulse.so"
    "$LIBDIR/libpulse-simple.so"
    "$LIBDIR/libpulse-mainloop-glib.so"
    "$PADIR/libpulsecommon-13.0.so"
    "$PADIR/libpulsecore-13.0.so"
    "$BINDIR/pulseaudio"
)

for f in "${FIX_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "  ⚠️ $f not found, skipping"
        continue
    fi
    
    # 替换 libltdl.so.7 → libltdl.so
    if readelf -d "$f" 2>/dev/null | grep -q 'libltdl.so.7'; then
        patchelf --replace-needed libltdl.so.7 libltdl.so "$f"
        echo "  ✅ $f: libltdl.so.7 → libltdl.so"
    fi
    
    # 替换 libsndfile.so.1 → libsndfile.so
    if readelf -d "$f" 2>/dev/null | grep -q 'libsndfile.so.1'; then
        patchelf --replace-needed libsndfile.so.1 libsndfile.so "$f"
        echo "  ✅ $f: libsndfile.so.1 → libsndfile.so"
    fi
done

echo ""
echo "============================================"
echo "  Fix 4: Add libsndfile.so NEEDED to libpulse.so and pulseaudio"
echo "============================================"

# libpulse.so 原始 NEEDED 包含 libsndfile.so, 我们的缺少
if ! readelf -d "$LIBDIR/libpulse.so" 2>/dev/null | grep -q 'libsndfile.so'; then
    patchelf --add-needed libsndfile.so "$LIBDIR/libpulse.so"
    echo "  ✅ libpulse.so: added libsndfile.so to NEEDED"
else
    echo "  ℹ️ libpulse.so: already has libsndfile.so"
fi

# pulseaudio 原始 NEEDED 包含 libsndfile.so
if ! readelf -d "$BINDIR/pulseaudio" 2>/dev/null | grep -q 'libsndfile.so'; then
    patchelf --add-needed libsndfile.so "$BINDIR/pulseaudio"
    echo "  ✅ pulseaudio: added libsndfile.so to NEEDED"
else
    echo "  ℹ️ pulseaudio: already has libsndfile.so"
fi

echo ""
echo "============================================"
echo "  Fix 5: Create libpulseaudio.so (daemon as shared library)"
echo "============================================"

# 原始 winlator bionic 将 pulseaudio daemon 重命名为 libpulseaudio.so
# 放在 jniLibs 中供 Android 加载
cp -f "$BINDIR/pulseaudio" "$LIBDIR/libpulseaudio.so"
echo "  ✅ libpulseaudio.so created ($(stat -c%s "$LIBDIR/libpulseaudio.so") bytes)"

echo ""
echo "============================================"
echo "  Fix 6: Reduce library sizes (strip .eh_frame, .eh_frame_hdr)"
echo "============================================"

# 原始库没有 .eh_frame 和 .eh_frame_hdr
# 使用 objcopy 移除这些段以减小体积
OBJCOPY=$NDK/bin/llvm-objcopy

for f in "$LIBDIR/libpulse.so" "$LIBDIR/libpulse-simple.so" "$LIBDIR/libpulse-mainloop-glib.so" \
         "$PADIR/libpulsecommon-13.0.so" "$PADIR/libpulsecore-13.0.so" "$LIBDIR/libpulseaudio.so"; do
    if [ ! -f "$f" ]; then continue; fi
    BEFORE=$(stat -c%s "$f")
    $OBJCOPY --remove-section .eh_frame --remove-section .eh_frame_hdr "$f" 2>/dev/null || true
    $STRIP "$f" 2>/dev/null || true
    AFTER=$(stat -c%s "$f")
    echo "  ✅ $(basename $f): ${BEFORE} → ${AFTER} bytes"
done

echo ""
echo "============================================"
echo "  Verification"
echo "============================================"
echo ""
for lib in libltdl.so libsndfile.so libpulse.so; do
    echo "--- $lib ---"
    echo "  SONAME: $(readelf -d "$LIBDIR/$lib" 2>/dev/null | grep SONAME | sed 's/.*\[/[/' | tr -d ' ')"
    echo "  NEEDED: $(readelf -d "$LIBDIR/$lib" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
    echo "  Size:   $(stat -c%s "$LIBDIR/$lib") bytes"
done
echo ""
for lib in libpulsecommon-13.0.so libpulsecore-13.0.so; do
    echo "--- $lib ---"
    echo "  NEEDED: $(readelf -d "$PADIR/$lib" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
    echo "  Size:   $(stat -c%s "$PADIR/$lib") bytes"
done
echo ""
echo "--- libpulseaudio.so ---"
echo "  NEEDED: $(readelf -d "$LIBDIR/libpulseaudio.so" 2>/dev/null | grep NEEDED | sed 's/.*\[/[/' | tr -d ' ' | tr '\n' ' ')"
echo "  Size:   $(stat -c%s "$LIBDIR/libpulseaudio.so") bytes"
echo "  Type:   $(file -b "$LIBDIR/libpulseaudio.so")"
