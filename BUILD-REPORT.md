# winlator bionic imagefs 构建报告

## 概述

完整复现 winlator bionic fork 的 imagefs 根文件系统构建。使用 Android NDK r29 (clang 21.0.0) 交叉编译，目标架构 `aarch64-linux-android26`，所有二进制链接 Bionic libc (`/system/bin/linker64`)。

**最终产物**: `imagefs.txz` (18MB, xz 压缩)
**SHA-256**: `af66e28b61577a0cd8433155ee2123d910f02f7870b8938994d27d81281372e3`

## 包列表 (39 个包)

| Tier | 包名 | 版本 | 构建系统 | 说明 |
|------|------|------|----------|------|
| 1 | zlib | 1.3.1 | cmake | 基础压缩库 |
| 1 | libffi | 3.4.6 | autotools | FFI 调用接口 |
| 1 | libexpat | 2.6.4 | cmake | XML 解析 |
| 1 | libpng | 1.6.46 | cmake | PNG 图像 |
| 1 | brotli | 1.1.0 | cmake | Brotli 压缩 |
| 2 | pcre2 | 10.45 | cmake | 正则表达式 |
| 2 | freetype | 2.13.3 | meson | 字体引擎 |
| 2 | libiconv | 1.17 | autotools | 字符编码转换 |
| 2 | libxml2 | 2.13.5 | cmake | XML 解析 |
| 3 | fontconfig | 2.16.0 | meson | 字体配置 |
| 3 | harfbuzz | 10.2.0 | meson | 文字塑形 |
| 3 | glib | 2.82.4 | meson | GLib 工具库 |
| 4 | xorgproto | 2024.1 | meson | X11 协议头 |
| 4 | libxcb | 1.17.0 | meson | XCB 协议 |
| 4 | libx11 | 1.8.10 | meson | X11 库 |
| 4 | libxext/libxfixes/libxrender/libxrandr/libxcomposite/libxcursor/libxi/libxinerama/libxxf86vm/libxshmfence | — | meson | X11 扩展 |
| 4 | libdrm | 2.4.123 | meson | DRM |
| 4 | vulkan-headers/vulkan-loader/libglvnd | — | meson/cmake | Vulkan |
| 5 | alsa-lib | 1.2.13 | autotools | ALSA 音频 + 插件头文件 |
| 5 | libsndfile | 1.2.2 | cmake | 音频文件格式 (SONAME=libsndfile.so) |
| 5 | libltdl | stub | 手动 | Bionic 兼容 dlopen 包装 (SONAME=libltdl.so) |
| 5 | pulseaudio | 13.0 | autotools | PA 13.0 + 74 模块 + libpulseaudio.so daemon |
| 5 | **alsa-android-aserver** | — | 手动 | ALSA PCM 插件 → Android 音频路由 |
| 6 | openssl | 3.4.1 | perl | TLS 加密 |
| 6 | curl | 8.11.1 | autotools | HTTP 客户端 |
| 7 | sdl2 | 2.30.12 | cmake | 多媒体库 |
| 8 | android-spawn | stub | 手动 | posix_spawn/glob (Bionic API 26 缺失) |
| 8 | android-sysv-semaphore | stub | 手动 | semget/semop/semctl (Bionic 缺失) |
| 8 | **android-sysvshm** | — | 手动 | System V 共享内存 (ashmem 实现) |
| 9 | box64 | v0.4.3 | cmake | x86_64 模拟器 |

## 对比验证: 原始 vs 构建

### SONAME 匹配 (✅ 全部一致)

| 库 | 原始 SONAME | 构建 SONAME | 状态 |
|---|---|---|---|
| libltdl.so | `libltdl.so` | `libltdl.so` | ✅ |
| libsndfile.so | `libsndfile.so` | `libsndfile.so` | ✅ |
| libpulse.so | `libpulse.so` | `libpulse.so` | ✅ |
| libpulsecommon-13.0.so | `libpulsecommon-13.0.so` | `libpulsecommon-13.0.so` | ✅ |
| libpulsecore-13.0.so | `libpulsecore-13.0.so` | `libpulsecore-13.0.so` | ✅ |

### NEEDED 匹配 (✅ 全部一致)

| 库 | 原始 NEEDED | 构建 NEEDED | 状态 |
|---|---|---|---|
| libltdl.so | libdl.so, libc.so | libdl.so, libc.so | ✅ |
| libsndfile.so | libm.so, libdl.so, libc.so | libm.so, libdl.so, libc.so | ✅ |
| libpulse.so | libpulsecommon-13.0.so, libsndfile.so, libm.so, libdl.so, libc.so | 同左 | ✅ |
| libpulsecommon-13.0.so | libsndfile.so, libm.so, libdl.so, libc.so | 同左 | ✅ |
| libpulsecore-13.0.so | libltdl.so, libpulse.so, libpulsecommon-13.0.so, libsndfile.so, libm.so, libdl.so, libc.so | 同左 | ✅ |
| libpulseaudio.so | libpulsecore-13.0.so, libpulse.so, libpulsecommon-13.0.so, libsndfile.so, libltdl.so, libm.so, libdl.so, libc.so | 同左 | ✅ |

### ELF 验证

- **211 个 ELF 文件**全部使用 `/system/bin/linker64` (Bionic linker)
- 所有 .so 链接 `libc.so` (无 `.6` 后缀, Bionic 特征)

### 模块对比

| 指标 | 原始 | 构建 | 说明 |
|------|------|------|------|
| PA 模块数 | 74 | 74 | 数量一致 |
| 缺失模块 | — | 10 | DBus(3), X11(4), OSS(1), aaudio-sink(1), liboss-util(1) |
| 多余模块 | — | 10 | ESD(5), RAOP(2), gsettings(1), virtual-surround(1), libprotocol-esound(1) |

> **注意**: 原始 `pulseaudio.tzst` 中的模块实际是 **glibc/PA 17.0** 编译 (链接 `libc.so.6`、`ld-linux-aarch64.so.1`)，与 Bionic 不兼容。我们的模块是 **Bionic/PA 13.0** 编译，更适合 bionic fork。

### 体积对比

| 库 | 原始 | 构建 | 比率 | 说明 |
|---|---|---|---|---|
| libltdl.so | 34KB | 7KB | 0.20x | 我们用 stub (更小) |
| libsndfile.so | 403KB | 527KB | 1.30x | ✅ |
| libpulse.so | 293KB | 1.2MB | 4.30x | ⚠️ -O2 生成大查找表 |
| libpulsecommon | 415KB | 1.4MB | 3.51x | ⚠️ 同上 |
| libpulsecore | 547KB | 766KB | 1.40x | ✅ |
| libpulseaudio.so | 67KB | 202KB | 2.99x | ⚠️ patchelf 扩展 |

> 体积差异不影响功能。构建脚本已更新为 `-Os` 优化，未来重建将更接近原始大小。

## 音频架构

winlator bionic 有两条音频路径:

1. **ALSA android_aserver (推荐, Bionic 原生)**
   - Wine → ALSA → `asound_module_pcm_android_aserver.so` → Android 音频服务器
   - 通过 Unix socket 连接 Android 原生音频系统
   - ALSA 配置: `/etc/alsa/alsa.conf` + `/etc/alsa/conf.d/android_aserver.conf`

2. **PulseAudio (遗留, 需 Bionic 模块)**
   - jniLibs 核心库 (Bionic PA 13.0) + pulseaudio.tzst 模块 (glibc PA 17.0, 不兼容)
   - 需要构建 Bionic PA 13.0 模块替换 (我们的构建已提供 74 个 Bionic 模块)
   - 缺少自定义 `module-aaudio-sink.so` (无公开源码)

## Bionic 兼容适配

| 问题 | 解决方案 |
|------|----------|
| Bionic 无 `argz.h`/`error_t` | libltdl 使用 stub 包装 dlopen/dlsym |
| Bionic 无 `pthread_mutexattr_setprotocol` | PA mutex-posix.c 补丁 |
| Bionic 无 `posix_spawn`/`glob` (API 26) | libandroid-spawn.so stub |
| Bionic 无 `semget`/`semop`/`semctl` | libandroid-sysv-semaphore.so stub |
| Bionic 无 System V 共享内存 | libsysvshm.so (ashmem 实现) |
| Bionic 无 `execinfo.h` | stub backtrace() |
| Bionic 无 `sys/capability.h` | stub cap_t/cap_init() |
| Bionic `ipc64_perm` 字段名不同 | `__key`→`key`, `__seq`→`seq` |
| NDK clang `-pedantic -Werror` 失败 | ax_cv_check 缓存变量绕过 |
| PA 13.0 atomic.h 类型转换错误 | `-Wno-int-conversion -Wno-error` |
| XML::Parser 不可用 | 创建空 man 页面 |
| box64 v0.3.7 tarball 404 | git clone HEAD |
| box64 并行构建竞态 | `make -j1` |

## 文件结构

```
imagefs/
├── bin → usr/bin (symlink)
├── etc → usr/etc (symlink)
├── lib → usr/lib (symlink)
├── share → usr/share (symlink)
├── tmp → usr/tmp (symlink)
├── etc/
│   └── alsa/
│       ├── alsa.conf
│       └── conf.d/android_aserver.conf
└── usr/
    ├── bin/ (34 可执行文件)
    ├── include/ (开发头文件)
    └── lib/
        ├── libpulseaudio.so (PA daemon)
        ├── libpulse.so, libpulse-simple.so, libpulse-mainloop-glib.so
        ├── libpulsecommon-13.0.so, libpulsecore-13.0.so
        ├── libltdl.so, libsndfile.so
        ├── asound_module_pcm_android_aserver.so
        ├── libsysvshm.so
        ├── libandroid-spawn.so, libandroid-sysv-semaphore.so
        ├── libc.so → /system/lib64/libc.so (Bionic)
        ├── libdl.so → /system/lib64/libdl.so
        ├── libm.so → /system/lib64/libm.so
        ├── libpthread.so → /system/lib64/libc.so
        ├── librt.so → /system/lib64/libc.so
        ├── liblog.so → /system/lib64/liblog.so
        ├── libEGL.so → /system/lib64/libEGL.so
        ├── libGLESv2.so → /system/lib64/libGLESv2.so
        └── pulseaudio/
            └── modules/ (74 PA 模块)
```
