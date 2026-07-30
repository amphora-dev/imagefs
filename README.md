# imagefs

winlator bionic fork 的 imagefs 根文件系统完整构建系统。使用 Android NDK r29 (clang 21.0.0) 交叉编译，目标架构 `aarch64-linux-android26`，所有二进制链接 Bionic libc。

仓库：[`amphora-dev/imagefs`](https://github.com/amphora-dev/imagefs)  
（由 [`cnb.cool/atowerlight/winlator-imagefs`](https://cnb.cool/atowerlight/winlator-imagefs) 迁入）

## 快速开始

```bash
# 1. 设置环境变量（指向 winlator 项目根目录）
export WINLATOR_DIR=/path/to/winlator

# 2. 运行完整构建
./build-all.sh

# 3. 打包
./package-imagefs.sh
```

CI 环境见 [`ci/Dockerfile`](ci/Dockerfile)；本地也可：

```bash
docker build -f ci/Dockerfile -t imagefs-ci .
docker run --rm -it -v "$PWD:/workspace" -e WINLATOR_DIR=/path/to/winlator imagefs-ci ./build-all.sh
```

## CI / Release

GitHub Actions（[`.github/workflows/build-imagefs.yml`](.github/workflows/build-imagefs.yml)）：

| 触发 | 行为 |
|------|------|
| `main` push | 完整构建，覆盖固定标签 Release **`amphora`** |
| Pull Request | 仅构建验证 |
| tag push | 按 tag 名创建 Release |

固定下载地址（amphora 侧认这个）：

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz.sha256sum
```

## 构建产物

- `imagefs.txz` — 完整根文件系统 (xz 压缩)
- ELF 全部使用 `/system/bin/linker64` (Bionic)
- 包涵盖图形 / 音频 / TLS / 媒体支撑库；Wine 依赖 soname 由 `ci/verify-wine-deps.sh` 断言
- **Box64 不进 imagefs**：Amphora 用独立 `Box64.wcp`；打包阶段会裁掉 headers / 静态库 / man / glvnd / 绝大多数 bin


## 包列表

| Tier | 包 | 说明 |
|------|-----|------|
| 1-3 | zlib, libffi, libexpat, libpng, brotli, pcre2, freetype, libiconv, libxml2, fontconfig, harfbuzz, glib | 基础库 |
| 4 | xorgproto, libxcb, libx11, libxext, ..., libdrm, vulkan, libglvnd | 图形/显示 |
| 5 | alsa-lib, libsndfile, libltdl(stub), pulseaudio 13.0, alsa-android-aserver | 音频 |
| 6 | openssl, curl | 网络/加密 |
| 7 | sdl2 | 多媒体 |
| 8 | android-spawn, android-sysv-semaphore, android-sysvshm | Bionic 兼容（Box64.wcp 仍 NEEDED spawn/semaphore） |
| — | ~~box64~~ | **不构建、不打包**；Amphora 用独立 `Box64.wcp` |


## 打包裁剪（`package-imagefs.sh`）

imagefs 是**运行时** rootfs，不是 sysroot。打包前在 staging 副本上删除：

| 去掉 | 保留 |
|------|------|
| `usr/include`、pkgconfig、cmake、`*.a`/`*.la` | Wine / wrapper / Turnip 的 NEEDED `.so` |
| man / doc / locale / vulkan registry 等 | `share/{X11,alsa,fontconfig,glib-2.0,gstreamer*,pulseaudio,vulkan/icd.d}` |
| glvnd（`libGLdispatch` / `libGLX` / …） | Mesa `libGL.so.1` 来自 runtime `extra_libs.tzst` |
| 几乎全部 `usr/bin`（含 box64） | 仅 `fc-cache`、`glib-compile-schemas`、`gio-querymodules` |

完整 `$ROOTFS` 仍保留 headers，供 CI 增量重编。


## 关键设计

- **Bionic libc**: 所有库链接 `libc.so` (无 `.6` 后缀)，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin`, `/etc`, `/lib` 等为 `usr/*` 的符号链接
- **PulseAudio 13.0**: 匹配 winlator bionic 实际版本 (非 17.0)
- **libltdl stub**: Bionic 无 `argz.h`/`error_t`，用 dlopen/dlsym 包装替代
- **ALSA android_aserver**: winlator bionic 的原生音频路径 (ALSA → Android 音频服务器)

详见 [BUILD-REPORT.md](BUILD-REPORT.md)
