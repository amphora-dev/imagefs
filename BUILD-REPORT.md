# winlator bionic imagefs 构建报告

## 概述

完整复现 winlator bionic fork 的 imagefs 根文件系统构建。使用 Android NDK r29 (clang 21.0.0) 交叉编译，目标架构 `aarch64-linux-android26`，所有二进制链接 Bionic libc (`/system/bin/linker64`)。

**最终产物**: `imagefs.txz` (18MB, xz 压缩)
**SHA-256**: `af66e28b61577a0cd8433155ee2123d910f02f7870b8938994d27d81281372e3`

> **2026-07-29 追加**: 按实际消费者做了双向审计（见下方「依赖对齐」与「反向审计」），
> `ALL_PACKAGES` 从 42 变为 **43**：补 8 个、删 7 个。本节表格仍是首轮 42 包的记录。
>
> **CI 全绿**（43/43，约 16 分钟级）：
>
> | | 首轮 42 包 | 现在 43 包 | 官方 imagefs |
> |---|---|---|---|
> | 压缩产物 | 18 MB (xz) | **27.5 MB** (xz) | 199.8 MB (zstd) |
> | 解压后 | — | 187 MB | 877 MB |
> | `.so` / 软链 | 211 ELF | 218 / 30 | 667 |
> | 可执行文件 | 34 | 50 | 351 |
>
> 补齐 Wine 与图形栈的真实依赖（gnutls 链、GStreamer、FFmpeg、zstd、
> libandroid-shmem）后体积从 18 MB 增到 27.5 MB，仍是官方的约 1/7；解压后约 1/4.7。
> `ci/verify/wine-deps.sh` 的 30 项必需依赖与 9 项可选依赖全部 OK。
>
> **2026-07-30（Amphora 资产通道拍板 + 清理）**：`wrapper` + adrenotools hooks **不焊进
> imagefs**，走独立更新通道；Amphora 运行时 hooks 只认 APK `nativeLibraryDir`，
> `wrapper.tzst` 单独 ARCHIVE。据此本仓**删除 `build-native-libs.sh`** 与 CI 的
> native-libs 阶段——它编的 `libadrenotools` + 4 hook / proot / virglrenderer 都不是
> imagefs 内容，也不是 Amphora 的来源（hooks 由 Amphora 自己的 adrenotools submodule
> 随 APK 编出；proot 已按 RFC D2 砍掉；virglrenderer 走 adrenotools/Vulkan 替代），
> 留着只会变成 hook 的第四个版本来源。本仓产物现在**只有 `imagefs.txz`**。
> 详见 Amphora `docs/04-ASSET-MANIFEST.md` §0.6。

## 反向审计：删掉的 10 个包 (2026-07-29)

前一轮只问「Wine 需要什么」，没问「我们编的东西有没有人要」。把全部消费者的需求
汇总后比对——Wine unix 侧 31 个 `.so` 的 NEEDED + dlopen、`libvulkan_wrapper.so`、
`libvulkan_freedreno.so`、`libGL.so.1`、box64、以及 Amphora 代码里显式引用的库名
——以下 10 个零消费者：

| 删掉 | 依据 |
|---|---|
| `libxrandr` `libxcomposite` `libxinerama` `libxxf86vm` | Wine unix 侧引用次数实测 **0**；proton-wine configure 本身就是 `--without-xcomposite/xfixes/xinerama/xrandr/xrender/xshape/xxf86vm`；图形栈三个库的 NEEDED 里也没有。`libxrandr` 还需先关掉 `vulkan-loader` 的 `BUILD_WSI_XLIB_XRANDR_SUPPORT`（上游默认 ON 且对 `xrandr.pc` 做 REQUIRED 检查）|
| `harfbuzz` | 我们的 `freetype.sh` 编译时 `-Dharfbuzz=disabled`，Wine 与图形栈零引用 |
| `libxml2` | fontconfig 2.15 的 meson 默认 expat 后端；Wine 与图形栈零引用 |
| `curl` | Wine 走自己的 wininet/winhttp；图形栈不引用 `libcurl` |

注意 `libxcb-randr` 等由 `libxcb` 包提供，与 `libxrandr` 无关，别一起删。

**五个曾被误判可省的**：

`libxshmfence` 与 `libexpat` 实际是 `libvulkan_freedreno.so` 的 NEEDED。

`libxfixes` 与 `libxrender` 运行期确实无人 NEEDED，但删掉后 `libxcursor` 与 `libxi`
双双 configure 失败：前者要 `(xrender >= 0.8.2 xfixes x11 fixesproto)`，后者要
`(xfixes >= 5)`，都是**构建期** pkg-config 依赖。而 `libxcursor`/`libxi` 是 Wine
dlopen 的，必须保留，所以这两个也得留。

> 这类错误犯了两次（连 `libglvnd` 是三次）：只核对运行期 NEEDED，漏了构建期
> pkg-config / 头文件依赖。删包前应同时检查 `grep -l <名字> packages/*.sh` 与
> 各包 configure/meson 的 `REQUIRED` 依赖。

`libglvnd` 一度被判为「`extra_libs.tzst` 会覆盖它」而删除，这个理由是错的：extra_libs
给的是带版本号的 `libGL.so.1.5.0`，与 libglvnd 的无后缀 `libGL.so` 文件名不同，不构成
覆盖。不过官方 imagefs 里确实只有 `libGL.so` + `libGL.so.1`，**没有** libglvnd 的
`libGLdispatch`/`libGLX`/`libOpenGL`/`libGLESv1_CM`，所以那几个实体库运行期没有消费者。
留它的真实理由是**构建期**：它 `-Dheaders=true` 提供桌面 `GL/gl.h`，而 `sdl2.sh` 开了
`-DSDL_OPENGL=ON`。要真去掉，得先关掉 SDL2 的桌面 GL（Wine 的 opengl32 自己
dlopen `libGL.so.1`，不经过 SDL）。运行期 `libEGL`/`libGLESv2` 也不需要 imagefs 里的
软链，因为 `LD_LIBRARY_PATH` 本身就带 `/system/lib64`。

`openssl` 保留：`GuestProgramLauncherComponent` 的 `LD_PRELOAD` 候选链里有 imagefs
的 `libcrypto.so.3`（前两个候选是 `/system/lib64` 与 `/system_ext/lib64`）。

**仍待处理**：Amphora 是 ALSA-only（manifest 已移除 `audio_plugin`），Wine 只需要
`libpulse` 客户端库（`winepulse.so` 的 NEEDED），而 pulseaudio daemon
（`libpulseaudio.so` + 74 个模块）和只为 daemon 存在的 `libsndfile` 都用不上。拆开
要改 `pulseaudio.sh` 的 configure，收益是构建时间（它是本仓最难编的包）与体积，
风险是可能引入新的构建失败，故本轮未动。

## 反向审计发现的两个缺口

比「多余」更要紧的方向。imagefs 的消费者不只有 Wine：图形栈的库由 runtimeAssets
提供（`wrapper.tzst` / `extra_libs.tzst`），但它们的 NEEDED 是从 imagefs/usr/lib
解析的。逐个 `readelf` 后发现两个库我们根本没编：

| 缺口 | 消费者 |
|---|---|
| `libzstd.so.1` | `libvulkan_freedreno.so`（Turnip）与 `libGL.so.1`（Mesa shader cache）|
| `libandroid-shmem.so` | `libGL.so.1`。**与 `libandroid-sysvshm.so` 不是同一个东西**：前者是 Termux 的 ASharedMemory 实现，后者是 winlator 的 socket server 实现，官方 imagefs 里两者并存 |

缺了不会报错，表现是 Vulkan/OpenGL 驱动加载失败即黑屏，所以
`ci/verify/wine-deps.sh` 现在把整个图形栈的 NEEDED 也纳入断言，并对已判定无消费者
的库做反向提示（重新出现时提醒复核）。

## Wine 依赖对齐 (2026-07-29)

依赖清单不再靠猜，而是从 Proton wcp 里 Wine unix 侧 31 个 `.so` 反推：
`readelf -dW` 取硬依赖 (NEEDED)，`strings` 取 `dlopen` 的软依赖。结果只有 22 项
NEEDED，逐个对应到消费者：

| 消费者 | 依赖 | 首轮 42 包 |
|---|---|---|
| `winex11.so` | `libX11.so` `libXext.so` | 有 |
| `winealsa.so` | `libasound.so` | 有 |
| `winepulse.so` | `libpulse.so` | 有 |
| 多个 | `libglib-2.0` `libgobject-2.0` `libgio-2.0` | 有 |
| `winegstreamer.so` | `libgst{reamer,base,app,audio,video,tag,gl}-1.0.so` | **缺** |
| `winedmo.so` | `libavutil.so.60` `libavcodec.so.62` `libavformat.so.62` | **缺（可选）** |

`dlopen` 软依赖里缺 `libgnutls.so`（3 处引用）与 `libgmp.so`。这条影响面最大：
Wine 的 `bcrypt`/`secur32` 运行期 dlopen gnutls，缺了就没有 TLS，游戏登录、更新
检查、任何 HTTPS 都会失败。

新增包：`gmp` → `nettle` → `gnutls`（TLS 链，有依赖序），
`gstreamer` → `gst-plugins-base`（后者依赖前者），`ffmpeg`。

优先级 **gnutls > GStreamer > FFmpeg**，理由见下。

### GStreamer 是完整路径，FFmpeg 只是可选的 demux 后端

「是 NEEDED」不等于「不可缺」：unixlib 按需加载，某个 unixlib 的 NEEDED 缺失只让
那一个 Wine 模块用不了。两者的实际分工（`objdump -p` 查消费者 + 导出表）：

`winedmo.so` 的导出只有 8 个 `winedmo_demuxer_*`（check/create/destroy/read/seek/
stream_lang/stream_name/stream_type）——**只拆容器，不解码**。消费者是 MF 的三个
source：`mfsrcsnk.dll` / `mfmp4srcsnk.dll` / `mfasfsrcsnk.dll`（import 表直连）。

`winegstreamer.dll` 通过 COM CLSID 注册了一整套（所以不进 import 表）：

```
Generic Decodebin Byte Stream Handler   ← 容器解析
wg_h264_decoder / wg_wmv_decoder / wg_mp3_decoder / wg_wma_decoder
wg_mpeg_video_decoder / GStreamerAudioDecoder / aac_decoder
wg_h264_encoder
wg_mpeg1_splitter / wg_mpeg4_sink_factory
```

外加导出 `winegstreamer_create_video_decoder` 与
`winegstreamer_create_wm_sync_reader`（后者被 `wmvcore.dll` delay-load）。

也就是说 GStreamer 覆盖 demux + decode + encode + DirectShow + WMV，而 FFmpeg 只
顶替其中 demux 一环，且要显式打开：注册表 `HKCU\Software\Wine\MediaFoundation`
下 DWORD `DisableGstByteStreamHandler = 1`，把上面那个 byte stream handler 换掉。
存在理由是某些容器 GStreamer 的处理与 Windows 行为不完全一致。

**结论：只装 GStreamer 可以，只装 FFmpeg 不行**（没有解码器）。

### 已知差异：FFmpeg 的 SONAME 不带版本

我们的 `libavcodec.so.62` / `libavutil.so.60` / `libavformat.so.62` 是
`ensure_soname_link` 建的软链，指向的实体 SONAME 是不带版本的 `libavcodec.so`。
原因是 FFmpeg 的 configure 对 `--target-os=android` 固定用
`SHFLAGS='-Wl,-soname,$(SLIBNAME)'`，拿不到带版本的 soname；同理 cmake 在
`CMAKE_SYSTEM_NAME=Android` 下也不生成 `libFoo.so.N`。

这与官方 imagefs 不同（那边是标准 Linux 构建，`libavutil.so.59.39.100` 实体的
SONAME 就是 `libavutil.so.59`）。可接受的理由：`DT_NEEDED` 的解析走**文件名**，
软链已满足；SONAME 只参与 linker 内部的去重。改成完全一致需要 `--target-os=linux`
（会引入 glibc 假设）或用 patchelf 改 SONAME，两者风险都高于收益。

### 装 FFmpeg 就必须是 8.0

`winedmo.so` 的 NEEDED 写死 `libavcodec.so.62` / `libavutil.so.60` /
`libavformat.so.62`，对应 **FFmpeg 8.0**。官方 imagefs 装的是 FFmpeg 7.1
（`libavcodec.so.61` / `libavutil.so.59` / `libavformat.so.61`），soname 不匹配
—— **官方那份完整 imagefs 里 `winedmo.so` 本来就加载不了**，而镜像照常可用。这
正好是 winedmo 属于可选路径的旁证。

这类错配从文件列表上看不出来，所以 `ci/verify/wine-deps.sh` 分「必需 / 可选」两级
断言，并打印实测 SONAME，升级 FFmpeg 大版本时会直接失败而不是静默降级。

### 相比官方省掉了什么

官方 191MB / 10892 条目里，Wine 用不到的部分占绝大多数：
`usr/share/terminfo` 2942 条目、`doc` 1951、`locale` 1077、`man` 612、`i18n` 602，
`usr/lib/tcl8.6` 858 个 Tcl 脚本；`usr/bin` 的 351 个可执行文件里有 `aomenc`/
`aomdec`、`x264`/`x265`、`ffmpeg`/`ffprobe`、`tclsh8.6`、`sqlite3` 以及整套
coreutils。我们只装 Wine 实际链接或 dlopen 的库。

## 包列表 (首轮 42 个包)

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
| — | box64 | — | — | 不构建；Amphora `Box64.wcp` |

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
