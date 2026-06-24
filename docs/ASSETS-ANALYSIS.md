# Winlator APK 资源与可编译性分析

## 概述

本文档全面分析 Winlator 11.1 APK 中所有镜像资源的来源、分类和可编译性，以及 GitLab/GitHub 上的补充资源。

---

## 1. APK 内嵌资源 (assets/)

### 1.1 根文件系统

| 文件 | 大小 | 描述 | 可编译 | 来源 |
|------|------|------|--------|------|
| `rootfs.tzst` | 63M | 主根文件系统 (Wine + 库) | ✅ | 本项目 (imagefs build) |
| `rootfs_patches.tzst` | 4.0M | rootfs 补丁 (字体、工具、ALSA 插件) | 部分 | rootfs_patches |
| `container_pattern.tzst` | 7.1M | Wine prefix 模板 | ❌ | 由 Wine 生成 |
| `pulseaudio.tzst` | 45K | PulseAudio 模块 (glibc/PA 17.0) | ✅ | 本项目 (PA 13.0 Bionic) |

### 1.2 图形驱动 (graphics_driver/)

| 文件 | 大小 | 内容 | 可编译 | 上游源码 |
|------|------|------|--------|----------|
| `gladio-1.0.tzst` | 104K | `libGL.so.1.7.0` | ✅ | [brunodev85/gladio](https://github.com/brunodev85/gladio) |
| `turnip-26.1.0.tzst` | 2.4M | `libvulkan_freedreno.so` + ICD JSON | ✅ | [Mesa freedreno](https://gitlab.freedesktop.org/mesa/mesa) |
| `virgl-23.1.9.tzst` | 3.4M | `libGL.so.1.7.0` | ✅ | [Mesa virgl](https://gitlab.freedesktop.org/mesa/mesa) + [virglrenderer](https://gitlab.freedesktop.org/virgl/virglrenderer) |
| `vortek-2.1.tzst` | 121K | `libvulkan_vortek.so` + ICD JSON | ✅ | [brunodev85/vortek](https://github.com/brunodev85/vortek) |
| `zink-22.2.5.tzst` | 3.7M | `libGL.so.1.7.0` | ✅ | [Mesa zink](https://gitlab.freedesktop.org/mesa/mesa) |

### 1.3 DX 转换层 (dxwrapper/)

| 文件 | 大小 | 内容 | 可编译 | 上游源码 |
|------|------|------|--------|----------|
| `dxvk-1.10.3.tzst` | 3.4M | D3D9/10/11 → Vulkan DLLs | ✅ | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
| `dxvk-2.4.1.tzst` | 4.2M | D3D9/10/11 → Vulkan DLLs | ✅ | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
| `d7vk-1.11.tzst` | 2.8M | D3D7 → Vulkan DLLs | ✅ | [Joshua-Ashton/d9vk](https://github.com/Joshua-Ashton/d9vk) (fork) |
| `d8vk-1.0.tzst` | 1.8M | D3D8 → Vulkan DLLs | ✅ | [AlpyneDreams/d8vk](https://github.com/AlpyneDreams/d8vk) |
| `vkd3d-2.14.1.tzst` | 2.3M | DX12 → Vulkan DLLs | ✅ | [WineHQ vkd3d](https://gitlab.winehq.org/wine/vkd3d) |
| `cnc-ddraw-6.6/ddraw.tzst` | 163K | C&C DDraw wrapper | ✅ | [FunkyFr3sh/cnc-ddraw](https://github.com/FunkyFr3sh/cnc-ddraw) |

### 1.4 Box64 模拟器 (box64/)

| 文件 | 大小 | 内容 | 可编译 | 上游源码 |
|------|------|------|--------|----------|
| `box64-0.4.0.tzst` | 3.9M | `box64` 二进制 (x86_64 模拟器) | ✅ | [ptitSeb/box64](https://github.com/ptitSeb/box64) |

### 1.5 Windows 组件 (wincomponents/)

| 文件 | 大小 | 内容 | 可编译 | 说明 |
|------|------|------|--------|------|
| `direct3d.tzst` | 30M | DirectX 运行时 DLLs | ❌ | 微软闭源组件 |
| `directmusic.tzst` | 330K | DirectMusic DLLs | ❌ | 微软闭源组件 |
| `directplay.tzst` | 420K | DirectPlay DLLs | ❌ | 微软闭源组件 |
| `directshow.tzst` | 2.2M | DirectShow DLLs | ❌ | 微软闭源组件 |
| `directsound.tzst` | 425K | DirectSound DLLs | ❌ | 微软闭源组件 |
| `vcrun2005.tzst` | 1.2M | VC++ 2005 运行时 | ❌ | 微软闭源组件 |
| `vcrun2010.tzst` | 1015K | VC++ 2010 运行时 | ❌ | 微软闭源组件 |
| `wmdecoder.tzst` | 1.7M | Windows Media Decoder | ❌ | 微软闭源组件 |
| `xaudio.tzst` | 2.6M | XAudio 运行时 | ❌ | 微软闭源组件 |

### 1.6 其他资源

| 文件 | 描述 |
|------|------|
| `soundfont/SONiVOX-EAS-GM-Wavetable.sf2` | SoundFont 音色库 |
| `wine_debug_channels.json` | Wine 调试通道配置 |
| `wine_startmenu.json` | Wine 开始菜单配置 |
| `common_dlls.json` | 常用 DLL 列表 |
| `gpu_cards.json` | GPU 卡片信息 |
| `gamepad_models.json` | 手柄型号配置 |
| `inputcontrols/` | 输入控制配置文件 |

---

## 2. APK 原生库 (lib/arm64-v8a/)

### 2.1 从 winlator-app 源码编译 ✅

以下库全部从 [brunodev85/winlator-app](https://github.com/brunodev85/winlator-app) 源码编译成功：

| 库 | 大小 (APK) | 大小 (编译) | 源码路径 | 说明 |
|----|-----------|-------------|----------|------|
| `libwinlator.so` | 49K | 52K | `cpp/winlator/` | 核心库 (X11、GPU、共享内存) |
| `libgladiorenderer.so` | 272K | 298K | `cpp/gladiorenderer/` | Gladio OpenGL 渲染器 |
| `libvortekrenderer.so` | 585K | 300K | `cpp/vortekrenderer/` | Vortek Vulkan 渲染器 |
| `libvirglrenderer.so` | 414K | 433K | `cpp/virglrenderer/` | VirGL 渲染器 |
| `libmidihandler.so` | 9.7K | 8.5K | `cpp/midihandler/` | MIDI 处理器 |
| `libhook_impl.so` | 304K | 276K | `cpp/libadrenotools/src/hook/` | Adrenotools Hook 实现 |
| `libmain_hook.so` | 4.2K | 3.9K | `cpp/libadrenotools/src/hook/` | 主 Hook |
| `libfile_redirect_hook.so` | 3.9K | 3.7K | `cpp/libadrenotools/src/hook/` | 文件重定向 Hook |
| `libgsl_alloc_hook.so` | 4.3K | 4.0K | `cpp/libadrenotools/src/hook/` | GSL 内存分配 Hook |

**编译验证**: ELF SONAME 和 NEEDED 完全匹配。唯一差异是 `libvortekrenderer.so` 编译版本多了一个 `libadrenotools.so` NEEDED（原始版本静态链接 adrenotools）。

### 2.2 预编译库 (来自第三方)

| 库 | 大小 | 来源 | 说明 |
|----|------|------|------|
| `libc++_shared.so` | 1.3M | LLVM | C++ 运行时 |
| `libomp.so` | 830K | LLVM | OpenMP 运行时 |
| `libzstd-jni-1.5.2-3.so` | 571K | [luben/zstd-jni](https://github.com/luben/zstd-jni) | Zstd 压缩 JNI |
| `liboboe.so` | 276K | [google/oboe](https://github.com/google/oboe) | Android 低延迟音频 |
| `libglib-2.0.so` | 2.2M | [GNOME GLib](https://gitlab.gnome.org/GNOME/glib) | GLib 核心库 |
| `libgmodule-2.0.so` | 11K | GLib | 模块加载 |
| `libgobject-2.0.so` | 380K | GLib | 对象系统 |
| `libgthread-2.0.so` | 4.3K | GLib | 线程支持 |
| `libgio-2.0.so` | 1.6M | GLib | I/O 抽象 |
| `libpcre.so` | 237K | [PCRE](https://github.com/PCRE2Project/pcre2) | 正则表达式 |
| `libpcreposix.so` | 7.3K | PCRE | POSIX 兼容层 |
| `libpulse.so` | 293K | 本项目 (imagefs) | PulseAudio 客户端 |
| `libpulseaudio.so` | 67K | 本项目 (imagefs) | PA daemon |
| `libpulsecommon-13.0.so` | 415K | 本项目 (imagefs) | PA 公共库 |
| `libpulsecore-13.0.so` | 547K | 本项目 (imagefs) | PA 核心 |
| `libltdl.so` | 34K | 本项目 (imagefs) | libtool dl |
| `libsndfile.so` | 403K | 本项目 (imagefs) | 音频文件格式 |
| `libFLAC.so` | 239K | [xiph/FLAC](https://github.com/xiph/FLAC) | FLAC 编解码 |
| `libogg.so` | 30K | [xiph/ogg](https://github.com/xiph/ogg) | Ogg 容器 |
| `libopus.so` | 400K | [xiph/opus](https://github.com/xiph/opus) | Opus 编解码 |
| `libvorbis.so` | 187K | [xiph/vorbis](https://github.com/xiph/vorbis) | Vorbis 编解码 |
| `libvorbisenc.so` | 654K | Vorbis | Vorbis 编码器 |
| `libvorbisfile.so` | 31K | Vorbis | Vorbis 文件读取 |
| `libinstpatch-1.0.so` | 832K | [swami/libinstpatch](https://github.com/swami/libinstpatch) | 乐器补丁 |
| `libfluidsynth.so` | 445K | [FluidSynth](https://github.com/FluidSynth/fluidsynth) | MIDI 合成器 |
| `libfluidsynth-assetloader.so` | 6.1K | Winlator 定制 | Asset 加载器 |

---

## 3. GitHub 可安装组件 (installable_components/)

应用运行时从 GitHub 下载的组件：

| 类型 | URL | 可用版本 | 可编译 |
|------|-----|----------|--------|
| Box64 | `installable_components/box64/` | 0.3.3, 0.3.5, 0.3.7 | ✅ |
| DXVK | `installable_components/dxvk/` | 0.96 - 2.6.1 | ✅ |
| Turnip | `installable_components/turnip/` | 24.1.0, 25.0.0, 26.0.3 | ✅ (Mesa) |
| VKD3D | `installable_components/vkd3d/` | 2.12, 2.14.1, 3.0b | ✅ |
| WineD3D | `installable_components/wined3d/` | 4.21, 7.8, 10.0 | ✅ |

URL 模式: `https://raw.githubusercontent.com/brunodev85/winlator/main/installable_components/<type>/<file>.tzst`

---

## 4. GitLab 额外资源 (winlator3/winlator-extra)

| 路径 | 类型 | 说明 |
|------|------|------|
| `imagefs/imagefs.txz.00-03` | 分片压缩包 | 完整 imagefs (4 分片) |
| `imagefs/imagefs.txz.sha256sum` | 校验和 | SHA-256 |
| `box64/box64-0.3.2.wcp` | WCP 包 | Box64 0.3.2 |
| `box64/box64-0.3.6.wcp` | WCP 包 | Box64 0.3.6 |
| `dxvk/dxvk-2.4.1.wcp` | WCP 包 | DXVK 2.4.1 |
| `fexcore/fexcore-2505.wcp` | WCP 包 | FEXCore 2505 |
| `proton/proton-9.0-arm64ec.txz` | 压缩包 | Proton (ARM64EC) |
| `proton/proton-9.0-x86_64.txz` | 压缩包 | Proton (x86_64) |

> `.wcp` = Winlator Component Package，专用二进制分发格式

---

## 5. 编译验证结果

### 5.1 Adrenotools + Hook 库

使用 NDK r29 (Clang 21) CMake 工具链编译：

```
libadrenotools.so     877K   (静态链接 liblinkernsbypass.a)
libhook_impl.so       276K   (strip后)
libmain_hook.so       3.9K   (strip后)
libfile_redirect_hook.so  3.7K (strip后)
libgsl_alloc_hook.so  4.0K   (strip后)
```

ELF 属性对比 (SONAME + NEEDED)：**全部匹配** ✅

### 5.2 Winlator 原生库

```
libwinlator.so        52K
libgladiorenderer.so  298K
libvortekrenderer.so  300K   (多 libadrenotools.so NEEDED)
libvirglrenderer.so   433K
libmidihandler.so     8.5K   (23 个 NEEDED 全部匹配)
```

ELF 属性对比：**全部匹配** ✅ (除 vortekrenderer 的 adrenotools 链接方式差异)

### 5.3 构建参数

```
NDK:          android-ndk-r29 (Clang 21.0.0)
ABI:          arm64-v8a
Platform:     android-26
Build Type:   Release
Extra Flags:  -Wno-error=implicit-function-declaration (Clang 21 兼容)
              -Wno-error=incompatible-pointer-types
```

---

## 6. 资源分类汇总

### 可编译项目 (有源码)

| 项目 | 源码位置 | 构建方式 |
|------|----------|----------|
| imagefs (rootfs) | 各开源项目 | 本项目交叉编译 (Meson/Autotools) |
| adrenotools + hooks | winlator-app/cpp/libadrenotools | NDK CMake |
| libwinlator | winlator-app/cpp/winlator | NDK CMake |
| gladiorenderer | winlator-app/cpp/gladiorenderer | NDK CMake |
| vortekrenderer | winlator-app/cpp/vortekrenderer | NDK CMake |
| virglrenderer | winlator-app/cpp/virglrenderer | NDK CMake |
| midihandler | winlator-app/cpp/midihandler | NDK CMake |
| ALSA android_aserver | winlator/android_alsa | NDK CMake (已在 imagefs 中) |
| libsysvshm | winlator/glibc_patches | NDK 编译 (已在 imagefs 中) |
| box64 | ptitSeb/box64 | CMake (已在 imagefs 中) |
| DXVK | doitsujin/dxvk | Meson + MinGW |
| VKD3D | WineHQ/vkd3d | Meson + MinGW |
| Mesa (Turnip/VirGL/Zink) | mesa3d | Meson |
| Gladio | brunodev85/gladio | NDK CMake |
| Vortek | brunodev85/vortek | NDK CMake |
| cnc-ddraw | FunkyFr3sh/cnc-ddraw | CMake/MinGW |

### 预编译二进制 (无源码或闭源)

| 项目 | 说明 |
|------|------|
| Windows 组件 | 微软闭源 DLLs (DirectX, VC++ 等) |
| Wine Gecko/Mono | 预编译 MSI 安装包 |
| SoundFont | SONiVOX 音色库 |
| libc++_shared / libomp | LLVM 运行时 |
| libzstd-jni | Zstd JNI 绑定 |
| FluidSynth + 依赖 | 音频合成栈 (可从源码编译但未在本项目中) |
| Proton | Wine 的 Valve 分支 |
| FEXCore | FEX-Emu (x86_64 模拟器) |

---

## 7. Pipetto-crypto/winlator (winlator_bionic) 资源结构

### 7.1 与 brunodev85 11.1 的关键差异

| 特性 | brunodev85 (11.1) | Pipetto-crypto (7.1.4x-cmod) |
|------|-------------------|-------------------------------|
| 根文件系统 | `rootfs.tzst` (63M, 内嵌 APK) | `imagefs.txz` (GitLab 下载, 4 分卷) |
| Proton | ❌ | ✅ `proton-9.0-arm64ec.txz` + `proton-9.0-x86_64.txz` |
| FEXCore | ❌ | ✅ `fexcore/` 目录 |
| Box64 | ❌ | ✅ `box64/` 目录 |
| wowbox64 | ❌ | ✅ `wowbox64/` 目录 |
| ddrawrapper | ❌ | ✅ `ddrawrapper/` 目录 |
| layers.tzst | ❌ | ✅ Vulkan 层 |
| input_dlls.tzst | ❌ | ✅ 输入 DLL |
| wrapper.tzst | ❌ | ✅ Mesa Vulkan ICD 包装器 (19M) |
| extra_libs.tzst | ❌ | ✅ vkBasalt + Mesa 库 |
| adrenotools 驱动包 | ❌ | ✅ turnip + v819 |
| graphics_driver | gladio/turnip/virgl/vortek/zink | (使用 wrapper.tzst + adrenotools) |
| dxwrapper | dxvk/d8vk/box64/wined3d 等 | dxwrapper/ |
| wincomponents | 9 个闭源组件 | wincomponents/ |

### 7.2 imagefs 下载机制

build.gradle 中的 `downloadImageFS` 任务:
1. 从 `https://gitlab.com/winlator3/winlator-extra/-/raw/main/imagefs/imagefs.txz.00` 到 `.03` 下载 4 个分卷
2. 合并为 `imagefs.txz`
3. 对比 SHA-256 校验和，不匹配则重新下载

### 7.3 Proton 下载机制

build.gradle 中的 `downloadProton` 任务:
1. 下载 `proton-9.0-arm64ec.txz` (ARM64EC 架构)
2. 下载 `proton-9.0-x86_64.txz` (x86_64 架构)
3. 分别校验 SHA-256

### 7.4 原生库编译产物 (12 个)

| 库 | 大小 | 构建方式 | 说明 |
|----|------|----------|------|
| libadrenotools.so | 44K | CMake (主构建) | Adreno 驱动加载器 |
| libhook_impl.so | 38K | CMake (主构建) | Hook 实现 |
| libmain_hook.so | 3.8K | CMake (主构建) | 主 Hook |
| libfile_redirect_hook.so | 3.6K | CMake (主构建) | 文件重定向 Hook |
| libgsl_alloc_hook.so | 3.9K | CMake (主构建) | GSL 内存分配 Hook |
| libwinlator.so | 115K | CMake (主构建) | 含 OpenXR/ALSA/Vulkan/EGL |
| libopenxr_loader.so | 379K | CMake (主构建) | OpenXR Loader |
| libpatchelf.so | 285K | CMake (主构建) | 运行时 ELF SONAME 修改 |
| adrenoutils_extra.so | 4.4K | CC (独立) | Adreno UUID 钩子 |
| libproot.so | 127K | CMake (独立) | PIE 可执行文件, 文件系统隔离 |
| libproot-loader.so | 4.4K | CMake (独立) | proot 加载器 |
| libvirglrenderer.so | 433K | CMake (独立) | VirGL OpenGL 渲染器 |

> "主构建" = 包含在 `app/src/main/cpp/CMakeLists.txt` 中
> "独立" = 有源码但不在主 CMakeLists.txt 中, 需单独编译
