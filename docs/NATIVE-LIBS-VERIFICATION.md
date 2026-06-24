# Winlator Bionic 原生库编译验证报告

## 源码仓库

**Pipetto-crypto/winlator** (winlator_bionic 分支)

- URL: https://github.com/Pipetto-crypto/winlator/tree/winlator_bionic
- 子模块: Pipetto-crypto/libadrenotools + Pipetto-crypto/liblinkernsbypass + KhronosGroup/OpenXR-SDK
- applicationId: `com.winlator.cmod`
- versionName: `7.1.4x-cmod`
- NDK: `29.0.14206865` (r29, Clang 21)

## 构建配置

| 项目 | 值 | 说明 |
|------|------|------|
| NDK | android-ndk-r29 | 与 build.gradle 一致 |
| ABI | arm64-v8a | |
| Platform | android-26 | minSdkVersion |
| STL | c++_shared | 匹配 wrapper.tzst (链接 libc++_shared.so) |
| Build Type | Release | -O2 |
| Linker Flags | -Wl,--as-needed | 避免 NDK r29 自动添加的不必要 NEEDED |
| C Flags | -Wno-error=implicit-function-declaration | Clang 21 兼容 |
| 修补 | adrenotools CMakeLists.txt 添加 `log` 链接 | NDK r29 需要 |

## 编译产物与 wrapper.tzst 对比

### Adrenotools + Hook 库 (wrapper.tzst)

| 库 | 编译大小 | wrapper.tzst | NEEDED 匹配 |
|----|---------|-------------|-------------|
| libadrenotools.so | 44K | 47K | ✅ |
| libhook_impl.so | 38K | 41K | ✅ |
| libmain_hook.so | 3.8K | 7.4K | ✅ |
| libfile_redirect_hook.so | 3.6K | 6.4K | ✅ |
| libgsl_alloc_hook.so | 3.9K | 7.5K | ✅ |

**全部 5 个库 NEEDED 完美匹配** ✅

编译版略小是因为 NDK r29 (Clang 21) 比 wrapper.tzst 构建时使用的编译器更新，优化更好。

### libwinlator.so (新)

| 项目 | 值 |
|------|------|
| 大小 | 115K |
| SONAME | libwinlator.so |
| NEEDED | liblog.so, libandroid.so, libjnigraphics.so, libopenxr_loader.so, libaaudio.so, libEGL.so, libGLESv2.so, libGLESv3.so, libadrenotools.so, libdl.so, libm.so, libc.so |

包含 OpenXR、AAudio、ALSA Client、Vulkan、EGL 渲染器、Shader 等模块。

### libopenxr_loader.so (新)

| 项目 | 值 |
|------|------|
| 大小 | 379K |
| 来源 | KhronosGroup/OpenXR-SDK |

### libpatchelf.so (新)

| 项目 | 值 |
|------|------|
| 大小 | 285K |
| 用途 | 运行时修改 ELF SONAME |

### adrenoutils_extra.so

| 项目 | 编译版 | adrenotools-v819.tzst |
|------|--------|----------------------|
| 大小 | 4.4K | 6.3K |
| NEEDED | liblog.so, libdl.so, libc.so | libdl.so, libc.so |

源码从 `adrenotools-v819.tzst` 中提取，提供 `get_override_device_uuid` 和 `get_driver_uuid` 钩子函数。

## wrapper.tzst 资源分析

`wrapper.tzst` 包含 6 个 .so + 1 个 ICD JSON：

| 文件 | 大小 | 说明 | 可编译 |
|------|------|------|--------|
| libadrenotools.so | 47K | Adreno 驱动加载器 | ✅ 已编译 |
| libhook_impl.so | 41K | Hook 实现 | ✅ 已编译 |
| libmain_hook.so | 7.4K | 主 Hook | ✅ 已编译 |
| libfile_redirect_hook.so | 6.4K | 文件重定向 Hook | ✅ 已编译 |
| libgsl_alloc_hook.so | 7.5K | GSL 内存分配 Hook | ✅ 已编译 |
| libvulkan_wrapper.so | 19M | Mesa Vulkan ICD 包装器 | ❌ 无源码 |
| wrapper_icd.aarch64.json | - | Vulkan ICD 配置 | N/A |

### libvulkan_wrapper.so 分析

- **来源**: Mesa Vulkan 运行时 (定制版)
- **大小**: 19M
- **功能**: 通过 `adrenotools_open_libvulkan` 加载真实 Adreno 驱动，并提供 X11/XCB 兼容层
- **NEEDED**: libandroid-sysvshm.so, libadrenotools.so, libnativewindow.so, libm.so, libxcb.so, libX11-xcb.so, libxcb-dri3.so, libxcb-present.so, libxcb-sync.so, libxcb-randr.so, libxcb-shm.so, libdrm.so, libc++_shared.so, libdl.so, libc.so
- **关键符号**: `vk_icdGetInstanceProcAddr`, `adrenotools_open_libvulkan`, `vk_icdNegotiateLoaderICDInterfaceVersion`
- **源码路径线索**: `../src/vulkan/runtime/vk_device.c`, `../src/vulkan/runtime/vk_image.h` 等 Mesa 源码路径

## adrenotools 驱动包分析

### adrenotools-turnip25.1.0.tzst

| 文件 | 说明 |
|------|------|
| meta.json | `{"libraryName": "vulkan.ad07xx.so"}` |
| vulkan.ad07xx.so | Mesa Turnip Vulkan 驱动 (Adreno 7xx 系列) |

### adrenotools-v819.tzst

| 文件 | 大小 | 说明 |
|------|------|------|
| meta.json | 261B | Quest 2 提取的 Adreno 8191 驱动 |
| adrenoutils_extra.c | 1.2K | UUID 钩子源码 (可编译 ✅) |
| adrenoutils_extra.so | 6.3K | UUID 钩子编译版 |
| vulkan.ad8191.so | 5.3M | Adreno 8191 Vulkan 驱动 |
| notadreno_utils.so | 196K | 重命名的 libadreno_utils.so |
| notdmabufheap.so | 149K | 重命名的 DMA buffer heap 库 |
| notgsl.so | 2.3M | 重命名的 GSL 库 |
| notllvm-glnext.so | 2.3M | 重命名的 LLVM Vulkan shader 编译器 |
| notllvm-qgl.so | 22M | 重命名的 LLVM OpenGL shader 编译器 |

> "not" 前缀用于绕过 Android 库检测，由 adrenotools 在运行时通过自定义 linker namespace 加载。

## extra_libs.tzst 分析

| 文件 | 说明 | 来源 |
|------|------|------|
| libvkbasalt.so | vkBasalt 后处理层 | [DadSchoorse/vkBasalt](https://github.com/DadSchoorse/vkBasalt) |
| libglapi.so.0.0.0 | Mesa GL API 库 | Mesa |
| libvulkan_freedreno.so | Mesa Freedreno Vulkan 驱动 | Mesa |
| libbcn_layer.so | BCN 纹理层 | 定制 |
| libGL.so.1.5.0 | Mesa GL 库 | Mesa |
| freedreno_icd.aarch64.json | Vulkan ICD 配置 | |
| libbcn_layer.json | Vulkan 隐式层配置 | |
| vkBasalt.json | Vulkan 隐式层配置 | |

## 与 brunodev85/winlator-app 对比

| 特性 | Pipetto-crypto (bionic) | brunodev85 (main) |
|------|------------------------|-------------------|
| 版本 | 7.1.4x-cmod | 11.1 |
| OpenXR | ✅ (VR 支持) | ❌ |
| patchelf | ✅ (内置) | ❌ |
| proot | ✅ (内置) | ❌ |
| GladioRenderer | ❌ | ✅ |
| VortekRenderer | ❌ | ✅ |
| VirGLRenderer | ✅ | ✅ |
| MIDIHandler | ❌ | ✅ |
| AudioSystem | AAudio | Oboe |
| adrenotools | ✅ (Pipetto-crypto fork) | ✅ (原版) |
| wrapper.tzst | ✅ (含 vulkan_wrapper) | ❌ |
| extra_libs.tzst | ✅ | ❌ |
| adrenotools 驱动包 | ✅ (turnip + v819) | ❌ |
| NDK | r29 | r29 |
| applicationId | com.winlator.cmod | com.winlator |

## 结论

1. **从 Pipetto-crypto/winlator (winlator_bionic) 成功编译 9 个原生库**
2. **5 个 adrenotools 库与 wrapper.tzst 预编译版 NEEDED 完美匹配**
3. 使用 `c++_shared` STL + `--as-needed` 是匹配 wrapper.tzst 的关键
4. `libvulkan_wrapper.so` (19M) 是 Mesa Vulkan ICD 包装器，无源码，不可编译
5. `adrenoutils_extra.c` 可从源码编译，功能为 Adreno UUID 钩子
6. Pipetto-crypto 版本包含 OpenXR/VR 支持，是 brunodev85 版本不具备的特性
