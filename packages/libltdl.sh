#!/usr/bin/env bash
# libltdl — Bionic 兼容 stub (pulseaudio 依赖)
# 真正的 libltdl (from libtool) 因 Bionic 缺少 argz.h/error_t 而无法构建
# 此 stub 包装 Bionic dlopen/dlsym, 提供所有 ltdl API 声明
# 包含 ltdl-bind-now.c 需要的内部类型 (lt_module, lt_dlvtable, etc.)
set -euo pipefail
source "$(dirname "$0")/../config.sh"

# 安装全面的 ltdl.h (包含所有 PA 需要的类型和常量)
cat > "$PREFIX/include/ltdl.h" << 'EOF'
#ifndef LTDL_H
#define LTDL_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define LT_SCOPE extern
#define LTDL_SET_PRELOADED_SYMBOLS()  ((void)0)
#define LT_ERROR_UNKNOWN 0
#define LT_ERROR_DLOPEN_NOT_SUPPORTED 1
#define LT_ERROR_INVALID_LOADER 2
#define LT_ERROR_INIT_LOADER 3
#define LT_ERROR_REMOVE_LOADER 4
#define LT_ERROR_FILE_NOT_FOUND 5
#define LT_ERROR_DEPLIB_NOT_FOUND 6
#define LT_ERROR_NO_SYMBOLS 7
#define LT_ERROR_CANNOT_OPEN 8
#define LT_ERROR_CANNOT_CLOSE 9
#define LT_ERROR_SYMBOL_NOT_FOUND 10
#define LT_DLLOADER_PREPEND 0
#define LT_DLLOADER_APPEND 1
typedef void *lt_dlhandle;
typedef void *lt_ptr;
typedef void *lt_module;
typedef void *lt_user_data;
typedef void *lt_dlloader;
typedef void *lt_dladvise;
typedef struct { const char *name; lt_ptr address; } lt_dlsymlist;
extern const lt_dlsymlist lt_preloaded_symbols[];
typedef lt_module (*lt_module_open_t)(const char *name, lt_dladvise advise, lt_user_data data);
typedef int (*lt_module_close_t)(lt_module module, lt_user_data data);
typedef void *(*lt_find_sym_t)(lt_module module, const char *symbol, lt_user_data data);
typedef int (*lt_dlloader_exit_t)(lt_user_data data);
typedef struct {
    const char *name; lt_module_open_t module_open; lt_module_close_t module_close;
    lt_find_sym_t find_sym; lt_dlloader_exit_t dlloader_exit;
    lt_user_data dlloader_data; int priority;
} lt_dlvtable;
typedef lt_dlvtable lt_dlloader_t;
LT_SCOPE int lt_dlinit(void);
LT_SCOPE int lt_dlexit(void);
LT_SCOPE lt_dlhandle lt_dlopen(const char *filename);
LT_SCOPE lt_dlhandle lt_dlopenext(const char *filename);
LT_SCOPE void *lt_dlsym(lt_dlhandle handle, const char *symbol);
LT_SCOPE int lt_dlclose(lt_dlhandle handle);
LT_SCOPE const char *lt_dlerror(void);
LT_SCOPE const char *lt_dlgetsearchpath(void);
LT_SCOPE int lt_dlsetsearchpath(const char *search_path);
LT_SCOPE int lt_dladdsearchdir(const char *search_dir);
LT_SCOPE int lt_dlinsertsearchdir(const char *before, const char *search_dir);
LT_SCOPE int lt_dlforeachfile(const char *search_path, int (*func)(const char *filename, lt_ptr data), lt_ptr data);
LT_SCOPE int lt_dladderror(const char *diagnostic);
LT_SCOPE int lt_dlseterror(int errorcode);
LT_SCOPE int lt_dlloader_add(const lt_dlvtable *vtable);
LT_SCOPE const lt_dlvtable *lt_dlloader_find(const char *name);
LT_SCOPE lt_dlvtable *lt_dlloader_remove(const char *name);
LT_SCOPE lt_dlloader lt_dlloader_next(const lt_dlloader loader);
LT_SCOPE const lt_dlvtable *lt_dlloader_get(lt_dlloader loader);
LT_SCOPE int lt_dladvise_init(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_destroy(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_ext(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_global(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_local(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_resident(lt_dladvise *advise);
LT_SCOPE int lt_dladvise_preload(lt_dladvise *advise);
#ifdef __cplusplus
}
#endif
#endif
EOF

# 编译 libltdl.so stub
cat > /tmp/libltdl_stub.c << 'STUBSRC'
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

$CC -fPIC -O2 -shared -o "$PREFIX/lib/libltdl.so" /tmp/libltdl_stub.c \
    -I"$PREFIX/include" -Wl,-soname,libltdl.so -Wl,-rpath,/usr/lib -ldl
$STRIP "$PREFIX/lib/libltdl.so"

log "  libltdl: stub (dlopen/dlsym wrapper + full ltdl API for PA 13.0)"
