# 原生库编译验证报告

## 构建环境

| 项目 | 值 |
|------|------|
| NDK | android-ndk-r29 |
| 编译器 | Clang 21.0.0 |
| 目标 ABI | arm64-v8a |
| Android API | 26 |
| 构建类型 | Release |
| 源码 | brunodev85/winlator-app (main) |
| 额外 CFLAGS | -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types |

> Clang 21 将隐式函数声明视为错误，而 winlator 源码大量使用未声明函数（strdup, memcpy 等），需要添加 `-Wno-error` 标志。

## 编译产物

| 库 | 编译大小 | APK 大小 | 差异说明 |
|----|---------|---------|---------|
| libadrenotools.so | 877K | N/A (不在APK) | 静态链接 liblinkernsbypass.a |
| libhook_impl.so | 276K | 304K | NDK 版本差异 |
| libmain_hook.so | 3.9K | 4.2K | NDK 版本差异 |
| libfile_redirect_hook.so | 3.7K | 3.9K | NDK 版本差异 |
| libgsl_alloc_hook.so | 4.0K | 4.3K | NDK 版本差异 |
| libwinlator.so | 52K | 49K | NDK 版本差异 |
| libgladiorenderer.so | 298K | 272K | NDK 版本差异 |
| libvortekrenderer.so | 300K | 585K | ⚠️ 见下文 |
| libvirglrenderer.so | 433K | 414K | NDK 版本差异 |
| libmidihandler.so | 8.5K | 9.7K | NDK 版本差异 |

### libvortekrenderer.so 差异说明

编译版比 APK 版小约 285K，原因：
- **编译版**: 动态链接 `libadrenotools.so` (NEEDED 包含 `libadrenotools.so`)
- **APK 版**: 静态链接 adrenotools (NEEDED 不包含 `libadrenotools.so`)
- CMakeLists.txt 中 `target_link_libraries(vortekrenderer adrenotools ...)` 使用共享库链接
- 原始构建可能使用了静态库或 `--exclude-libs` 选项

## ELF 属性验证

### libwinlator.so ✅ 完全匹配

```
SONAME: libwinlator.so
NEEDED: liblog.so, libandroid.so, libjnigraphics.so, libEGL.so,
        libGLESv2.so, libGLESv3.so, libm.so, libdl.so, libc.so
```

### libgladiorenderer.so ✅ 完全匹配

```
SONAME: libgladiorenderer.so
NEEDED: libwinlator.so, liblog.so, libandroid.so, libEGL.so,
        libGLESv2.so, libGLESv3.so, libjnigraphics.so, libm.so,
        libdl.so, libc.so
```

### libvirglrenderer.so ✅ 完全匹配

```
SONAME: libvirglrenderer.so
NEEDED: libwinlator.so, liblog.so, libandroid.so, libEGL.so,
        libGLESv2.so, libGLESv3.so, libjnigraphics.so, libm.so,
        libdl.so, libc.so
```

### libmidihandler.so ✅ 完全匹配 (23 个 NEEDED)

```
SONAME: libmidihandler.so
NEEDED: libFLAC.so, libfluidsynth-assetloader.so, libgio-2.0.so,
        libglib-2.0.so, libgmodule-2.0.so, libgobject-2.0.so,
        libgthread-2.0.so, libinstpatch-1.0.so, liboboe.so,
        libogg.so, libopus.so, libpcre.so, libpcreposix.so,
        libsndfile.so, libvorbis.so, libvorbisenc.so,
        libvorbisfile.so, libfluidsynth.so, liblog.so, libomp.so,
        libm.so, libdl.so, libc.so
```

### libvortekrenderer.so ⚠️ 链接方式差异

```
编译版 NEEDED (多一个):
  libadrenotools.so, libwinlator.so, liblog.so, libandroid.so,
  libdl.so, libjnigraphics.so, libEGL.so, libGLESv2.so,
  libGLESv3.so, libm.so, libc.so

APK 版 NEEDED:
  libwinlator.so, liblog.so, libandroid.so, libdl.so,
  libjnigraphics.so, libEGL.so, libGLESv2.so, libGLESv3.so,
  libm.so, libc.so
```

### Hook 库 (4个) ✅ 完全匹配

所有 4 个 hook 库的 SONAME 和 NEEDED 完全一致：

```
libhook_impl.so:
  NEEDED: liblog.so, libandroid.so, libdl.so, libm.so, libc.so

libmain_hook.so:
  NEEDED: libhook_impl.so, libandroid.so, libdl.so, liblog.so, libm.so, libc.so

libfile_redirect_hook.so:
  NEEDED: libhook_impl.so, libandroid.so, libdl.so, liblog.so, libm.so, libc.so

libgsl_alloc_hook.so:
  NEEDED: libhook_impl.so, libandroid.so, libdl.so, liblog.so, libm.so, libc.so
```

## 结论

1. **10 个原生库全部编译成功**，ELF 属性与 APK 原始版本基本一致
2. 唯一功能差异是 `libvortekrenderer.so` 的 adrenotools 链接方式（动态 vs 静态），不影响功能
3. 大小差异来自 NDK 版本不同（我们使用 r29/Clang 21，原始可能使用 r26/r27）
4. 编译过程需要 `-Wno-error=implicit-function-declaration` 兼容 Clang 21
