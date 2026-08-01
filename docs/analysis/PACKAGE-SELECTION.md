# 包取舍依据

这份文档只回答一个问题：**`build-all.sh` 的 `ALL_PACKAGES` 为什么是现在这些包**。
构建流程见 [README](../../README.md)，CI 分层见 [ci/README.md](../../ci/README.md)，
逆向取证过程见 [ANALYSIS.md](ANALYSIS.md)。

结论的可执行版本是 [`ci/verify/wine-deps.sh`](../../ci/verify/wine-deps.sh)：那里逐条
断言 imagefs 必须提供哪些库、哪些库不该出现。下面写的是**为什么**，脚本写的是**是什么**；
两者不一致时以脚本为准。

## 判定方法

依赖清单不靠猜，双向审计：

- **正向**（Wine 要什么）：`readelf -dW <proton>/lib/wine/x86_64-unix/*.so` 取 NEEDED，
  `strings` 取 dlopen 的软依赖。
- **反向**（我们编的东西有没有人要）：把全部消费者的需求汇总后比对。消费者不只有 Wine，
  还有 runtimeAssets 提供的图形栈（`libvulkan_wrapper.so` / `libvulkan_freedreno.so` /
  `libGL.so.1`），它们的 NEEDED 同样是从 `imagefs/usr/lib` 解析的。

## 明确不构建的包

| 不构建 | 依据 |
|---|---|
| `libxrandr` `libxcomposite` `libxinerama` `libxxf86vm` | Wine unix 侧引用实测 0；proton-wine configure 本身就是 `--without-xcomposite/xinerama/xrandr/xxf86vm`；图形栈的 NEEDED 里也没有。删 `libxrandr` 需先关掉 `vulkan-loader` 的 `BUILD_WSI_XLIB_XRANDR_SUPPORT`（上游默认 ON 且对 `xrandr.pc` 做 REQUIRED 检查） |
| `harfbuzz` | `freetype.sh` 编译时 `-Dharfbuzz=disabled`，Wine 与图形栈零引用 |
| `libxml2` | fontconfig 的 meson 默认走 expat 后端；Wine 与图形栈零引用 |
| `curl` | Wine 走自己的 wininet/winhttp；图形栈不引用 `libcurl` |
| `ffmpeg` | 只顶替 GStreamer 的 demux 一环，且要注册表显式打开，见下 |
| pulseaudio 栈（`pulseaudio` `libsndfile` `libltdl`） | Amphora 是 ALSA-only。daemon + 74 个模块、以及只为 daemon 存在的 `libsndfile`/`libltdl` 全部无消费者。它同时是本仓最难编的包 |
| `libglvnd` | 运行期无消费者（官方 imagefs 里也只有 `libGL.so` + `libGL.so.1`，没有 `libGLdispatch`/`libGLX`/`libOpenGL`）。它唯一的作用是构建期提供桌面 `GL/gl.h`，而 `sdl2.sh` 已经关掉 `SDL_OPENGL`。`package-imagefs.sh` 会主动裁掉残留，`wine-deps.sh` 断言其缺席 |
| `box64` | 独立发版为 `Box64-*.wcp`，见 `ci/box64/` |

注意 `libxcb-randr` 等由 `libxcb` 包提供，与 `libxrandr` 无关，别一起删。

## 看着可省、其实删不得

- `libxshmfence` 与 `libexpat`：是 `libvulkan_freedreno.so` 的 NEEDED。
- `libxfixes` 与 `libxrender`：运行期确实无人 NEEDED，但删掉后 `libxcursor` 与 `libxi`
  双双 configure 失败（前者要 `xrender >= 0.8.2 xfixes x11 fixesproto`，后者要
  `xfixes >= 5`），都是**构建期** pkg-config 依赖。而 `libxcursor`/`libxi` 是 Wine
  dlopen 的，必须保留。
- `openssl`：`GuestProgramLauncherComponent` 的 `LD_PRELOAD` 候选链里有 imagefs 的
  `libcrypto.so.3`（前两个候选是 `/system/lib64` 与 `/system_ext/lib64`）。

> 这个坑踩过三次（`libxfixes`/`libxrender`、`libxshmfence`/`libexpat`、`libglvnd`）：
> 只核对运行期 NEEDED，漏了构建期 pkg-config / 头文件依赖。删包前同时查
> `rg -l <名字> packages/` 与各包 configure/meson 的 REQUIRED 依赖。

## 反向审计补上的两个缺口

| 缺口 | 消费者 |
|---|---|
| `libzstd.so.1` | `libvulkan_freedreno.so`（Turnip）与 `libGL.so.1`（Mesa shader cache） |
| `libandroid-shmem.so` | `libGL.so.1`。**与 `libandroid-sysvshm.so` 不是同一个东西**：前者是 Termux 的 ASharedMemory 实现，后者是 winlator 的 socket server 实现，官方 imagefs 里两者并存 |

缺了不会报错，表现是 Vulkan/OpenGL 驱动加载失败即黑屏——所以 `wine-deps.sh` 把整个
图形栈的 NEEDED 也纳入断言。

## GStreamer 是完整路径，FFmpeg 只是可选的 demux 后端

「是 NEEDED」不等于「不可缺」：unixlib 按需加载，某个 unixlib 的 NEEDED 缺失只让那一个
Wine 模块用不了。

`winedmo.so` 的导出只有 8 个 `winedmo_demuxer_*`——**只拆容器，不解码**。消费者是 MF 的
三个 source（`mfsrcsnk.dll` / `mfmp4srcsnk.dll` / `mfasfsrcsnk.dll`）。

`winegstreamer.dll` 则通过 COM CLSID 注册了一整套（所以不进 import 表）：Generic
Decodebin Byte Stream Handler、`wg_h264/wmv/mp3/wma/mpeg_video` decoder、
`GStreamerAudioDecoder`、`aac_decoder`、`wg_h264_encoder`、`wg_mpeg1_splitter`、
`wg_mpeg4_sink_factory`，外加给 `wmvcore.dll` delay-load 的
`winegstreamer_create_wm_sync_reader`。

也就是说 GStreamer 覆盖 demux + decode + encode + DirectShow + WMV，FFmpeg 只顶替其中
demux 一环，还要注册表 `HKCU\Software\Wine\MediaFoundation` 下
`DisableGstByteStreamHandler = 1` 才生效。**只装 GStreamer 可以，只装 FFmpeg 不行。**

### 若将来重新引入 FFmpeg

`winedmo.so` 的 NEEDED 写死 `libavcodec.so.62` / `libavutil.so.60` /
`libavformat.so.62`，对应 **FFmpeg 8.0**；官方 imagefs 装的是 7.1，soname 不匹配——
官方那份完整 imagefs 里 `winedmo.so` 本来就加载不了，而镜像照常可用，这正是 winedmo
属于可选路径的旁证。

另外 FFmpeg 的 configure 对 `--target-os=android` 固定用
`SHFLAGS='-Wl,-soname,$(SLIBNAME)'`，拿不到带版本的 soname，只能靠
`ensure_soname_link` 补软链。`DT_NEEDED` 的解析走文件名，软链已够；要做到 SONAME 也
一致就得 `--target-os=linux`（引入 glibc 假设）或 patchelf 改 SONAME，风险都高于收益。

## Bionic 兼容适配

| 问题 | 解决方案 |
|---|---|
| Bionic 无 `posix_spawn`/`glob`（API 26） | `libandroid-spawn.so` stub |
| Bionic 无 `semget`/`semop`/`semctl` | `libandroid-sysv-semaphore.so` stub |
| Bionic 无 System V 共享内存 | `libandroid-sysvshm.so`（socket server 实现） |
| Bionic 无 `<linux/futex.h>` | `libxshmfence` 用 `--disable-futex` |
| Android linker 忽略 SONAME 版本号，但别人的 NEEDED 写的是带版本的文件名 | `config.sh` 的 `ensure_soname_link` 补软链 |
| cmake `CMAKE_SYSTEM_NAME=Android` 不生成 `libFoo.so.N` | 同上 |
| SDL2 cmake 在 `__ANDROID__` 下走 Android 分支 | `sdl2.sh` 用 `-U__ANDROID__` + `CMAKE_SYSTEM_NAME=Linux` |

## 相比官方省掉了什么

官方 191MB / 10892 条目里 Wine 用不到的占绝大多数：`usr/share/terminfo` 2942 条目、
`doc` 1951、`locale` 1077、`man` 612、`i18n` 602、`usr/lib/tcl8.6` 858 个 Tcl 脚本；
`usr/bin` 的 351 个可执行文件里有 `aomenc`/`aomdec`、`x264`/`x265`、`ffmpeg`/`ffprobe`、
`tclsh8.6`、`sqlite3` 以及整套 coreutils。我们只装 Wine 与图形栈实际链接或 dlopen 的库。
