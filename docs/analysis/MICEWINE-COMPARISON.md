# 与 MiceWine-Packages 完整对比 + CI 失败根因

> 数据来源:CNB 构建 `cnb-7rg-1jrshou3u`(commit `ce5d8b8`)完整日志 + clone
> `github.com/KreitinnSoftware/MiceWine-Packages` 与 `github.com/AndreRH/hangover` 对照。

## 0. 关键定位:两个项目目标不同

| | 本项目 (winlator-imagefs) | MiceWine-Packages |
|---|---|---|
| 运行环境 | winlator imagefs rootfs,`/usr` | Android 真机 `/data/data/com.micewine.emu/files/usr` |
| 运行方式 | box64/proot **模拟 Linux**,跑 x86 Windows 程序 | Android 上**原生**运行 |
| C 运行时 | Bionic(`/system/bin/linker64`) | Bionic |
| X11/audio 语义 | **Linux 语义**(unix socket `/usr/tmp/.X11-unix`) | **Android 语义**(AAudio、ANativeWindow) |
| 目标 | 字节级复刻官方 bionic imagefs | 自有运行时 |

**结论:MiceWine 的版本号、Bionic 补丁技巧、依赖关系、链接 flag 可借鉴;
但它的 `__ANDROID__` EGL/AAudio patch、硬编码 `/data/data/...` 路径不能照搬。**

## 1. CI 失败现状(29/42 成功,13 失败)

| 组 | 失败包 | 根因 |
|---|---|---|
| **A 根因** | **libx11** | `make install` 失败(src 编译成功但 x11.pc 未装上)。真实错误被诊断逻辑 `head -60`(全是 warning)截断。**疑似缺 System V 共享内存符号** |
| A 连锁 | libxext libxfixes libxrender libxrandr libxcomposite libxcursor libxi libxinerama libxxf86vm | libx11 没装上 → "No package 'x11' found" |
| B 连锁 | vulkan-loader | 走 X11 WSI,X11 没装 → pkg_check_modules 失败 |
| B 连锁 | libglvnd | install 时 libEGL.so FileNotFoundError |
| **C 独立** | **pulseaudio** | `backtrace`/`backtrace_symbols` 未声明。Bionic API26 有 execinfo.h 头但函数被 `__INTRODUCED_IN(33)` 守卫,configure 误判 `HAVE_EXECINFO_H=1` |

## 2. libx11 根因(组 A)— 最关键

**MiceWine 的 libX11 配方:**
```sh
PKG_VER=1.8.9
CONFIGURE_ARGS="--host=$TRIPLE host_alias=$TRIPLE --enable-malloc0returnsnull"
LDFLAGS="-L$PREFIX/lib -landroid-shmem"        # ← 链接 shmem 实现
DEPENDENCIES="xorgproto libxcb xtrans xorg-utils-macros android-shmem"
```
patch:
- `fix-pthread.patch`:`XTHREADLIB=-lpthread` → `-pthread`(Bionic pthread 内建于 libc)
- `src-CrGlCur.c.patch`:`libXcursor.so.1` → `libXcursor.so`(去版本号 SONAME)
- `src-XlibInt.c.patch`:`FIONREAD` 宏 → 字面值 `0x541B`

**我们的 libx11.sh:**
- 版本 1.8.10,无任何 patch,**未链接共享内存库**
- libX11 的 `_XAllocTemp`/MIT-SHM 路径需要 `shmget/shmat/shmdt/shmctl`,Bionic 不提供 → 链接期缺符号

**我们已有等价物!** `android-sysvshm` 包生成 `libsysvshm.so`(提供 shmget/shmat/shmdt/shmctl,ashmem 实现),
但:① 构建顺序在第 41 位(X11 之后);② libx11 没有 `-lsysvshm`。

→ **修复:把 android-sysvshm 提前到 X11 之前,libx11 LDFLAGS 加 `-lsysvshm`,
   并加 pthread/SONAME patch。**

## 3. pulseaudio 根因(组 C)

**MiceWine:** PA **v17.0 + meson**,`-Dx11/alsa/openssl/glib=disabled`,
patch `#undef HAVE_EXECINFO_H`,Android 专属(AAudio sink、禁用 drop_root/caps)。

**我们:** PA **13.0 + autotools**(刻意匹配官方 imagefs 版本),`--enable-alsa --enable-glib --enable-openssl`。
不能换版本/构建系统(会偏离复刻目标),只需修 backtrace:
→ configure 前 `export ac_cv_header_execinfo_h=no`(或 sed `#undef HAVE_EXECINFO_H`)。

## 4. 逐包版本差异

| 包 | 我们 | MiceWine | 备注 |
|---|---|---|---|
| libX11 | 1.8.10 | 1.8.9 | 版本接近,差异在 patch+链接 |
| libXext | (release) | 1.3.6 | MiceWine 加 host_alias |
| libXfixes | — | 6.0.1 | |
| libXrender | — | 0.9.11 | |
| libXrandr | — | 1.5.4 | |
| xtrans | 1.5.2 | 1.5.0 | MiceWine 有 3 个 socket patch |
| libxcb | 1.17.0 | 1.17.0 | 一致 |
| libxshmfence | 1.3.2 `--disable-futex` | 1.3.2 `--disable-futex` | **一致**(我们已对) |
| libdrm | 2.4.124 全禁驱动 | 2.4.124 启用 freedreno-kgsl | 我们更保守 |
| Vulkan-Loader | 1.4.313 `BUILD_WSI_XLIB=ON` | 1.4.304 `CMAKE_SYSTEM_NAME=Linux` | 都走 X11,依赖 X11 |
| libglvnd | 1.7.0 `egl=true` | 1.7.0 `egl=false` | 见下 |
| pulseaudio | 13.0 autotools | v17.0 meson | 见 §3 |
| libsndfile | 1.2.2 shared+patchelf | 1.2.2 static | 我们要 SONAME 匹配 |

## 5. libglvnd 差异(组 B)

- MiceWine:`-Degl=false -Dgles1=false -Dgles2=false`(只留 GLX dispatch?实际配合 mesa-wrapper)
- 我们:`-Degl=true -Dgles1=true -Dgles2=true -Dglx=disabled`
- 失败:install 时 `libEGL.so` 不存在 → 可能是 X11 没装导致 EGL target 没生成
- 待 X11 修好后复查;egl-not-android.diff(`#elif 0` 屏蔽 ANDROID 分支)我们也需要,
  因为我们要 **Linux 风格 EGL**(用 X11 EGLNativeWindowType)而非 ANativeWindow

## 6. 改造计划

### P0 — 先修诊断(拿到真实错误)
- `build-all.sh`:失败时打印 stderr **末尾** + grep `error:`/`undefined`/`No package`,
  不再只打印开头 60 行 warning。

### P1 — 修组 A 根因(libx11 + 共享内存)
1. `android-sysvshm` 提前到 X11 之前(改 build-all.sh 拓扑序)
2. `libx11.sh` 加 `-lsysvshm`、pthread patch、libXcursor SONAME patch
3. 各 X11 子库 configure 加 `host_alias=$TRIPLE`

### P2 — 修组 C(pulseaudio backtrace)
- configure 前 `export ac_cv_header_execinfo_h=no`

### P3 — 复查组 B(X11 修好后)
- vulkan-loader / libglvnd 重新评估,可能自动连锁修复

### P4 — push 一轮验证
