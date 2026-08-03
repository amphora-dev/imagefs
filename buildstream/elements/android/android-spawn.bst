kind: manual

description: |
  API-26 compatibility stubs for posix_spawn and glob.

depends:
- filename: base/ubuntu.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build

config:
  configure-commands:
  - |
    cat > android_spawn_stub.c <<'EOF'
    #include <sys/types.h>
    #include <unistd.h>
    #include <stdlib.h>
    #include <string.h>
    #include <errno.h>

    typedef struct { int __allocated; int __used; void *__actions; int __pad[16]; } posix_spawn_file_actions_t;
    typedef struct { short __flags; int __pgrp; void *__sigmask; void *__sigdefault; int __pad[16]; } posix_spawnattr_t;

    int posix_spawn(pid_t *pid, const char *path,
                    const posix_spawn_file_actions_t *fa,
                    const posix_spawnattr_t *attrp,
                    char *const argv[], char *const envp[]) {
        (void)fa; (void)attrp;
        pid_t p = vfork();
        if (p == 0) { if (envp) execve(path, argv, envp); else execv(path, argv); _exit(127); }
        if (p < 0) return errno;
        if (pid) *pid = p;
        return 0;
    }

    int posix_spawnp(pid_t *pid, const char *file,
                     const posix_spawn_file_actions_t *fa,
                     const posix_spawnattr_t *attrp,
                     char *const argv[], char *const envp[]) {
        (void)fa; (void)attrp;
        pid_t p = vfork();
        if (p == 0) { if (envp) execvpe(file, argv, envp); else execvp(file, argv); _exit(127); }
        if (p < 0) return errno;
        if (pid) *pid = p;
        return 0;
    }

    typedef struct { size_t gl_pathc; char **gl_pathv; size_t gl_offs; } glob_t;
    int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *pglob) {
        (void)pattern; (void)flags; (void)errfunc;
        if (pglob) { pglob->gl_pathc = 0; pglob->gl_pathv = NULL; }
        return 3;
    }
    void globfree(glob_t *pglob) {
        if (pglob && pglob->gl_pathv) { free(pglob->gl_pathv); pglob->gl_pathv = NULL; pglob->gl_pathc = 0; }
    }
    EOF

  build-commands:
  - |
    "$CC" -fPIC -O2 -shared \
      -o libandroid-spawn.so android_spawn_stub.c \
      -Wl,-soname,libandroid-spawn.so \
      -Wl,-rpath,/usr/lib
    "$STRIP" libandroid-spawn.so

  install-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    includedir="%{install-root}%{prefix}/include"
    mkdir -p "$libdir" "$includedir"
    install -m 0755 libandroid-spawn.so "$libdir/"
    cat > "$includedir/spawn.h" <<'EOF'
    #ifndef _SPAWN_H
    #define _SPAWN_H
    #include <sys/types.h>
    typedef struct { int __allocated; int __used; void *__actions; int __pad[16]; } posix_spawn_file_actions_t;
    typedef struct { short __flags; int __pgrp; void *__sigmask; void *__sigdefault; int __pad[16]; } posix_spawnattr_t;
    int posix_spawn(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *, char *const[], char *const[]);
    int posix_spawnp(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *, char *const[], char *const[]);
    #endif
    EOF
    cat > "$includedir/glob.h" <<'EOF'
    #ifndef _GLOB_H
    #define _GLOB_H
    #include <stddef.h>
    #define GLOB_NOSPACE 1
    #define GLOB_ABORTED 2
    #define GLOB_NOMATCH 3
    #define GLOB_APPEND 0x1
    #define GLOB_DOOFFS 0x2
    #define GLOB_ERR 0x4
    #define GLOB_MARK 0x8
    #define GLOB_NOSORT 0x10
    #define GLOB_NOESCAPE 0x20
    typedef struct { size_t gl_pathc; char **gl_pathv; size_t gl_offs; } glob_t;
    int glob(const char *, int, int (*)(const char *, int), glob_t *);
    void globfree(glob_t *);
    #endif
    EOF

  strip-commands: []
