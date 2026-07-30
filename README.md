# imagefs

winlator bionic fork 的 imagefs 根文件系统完整构建系统。使用 Android NDK r29 (clang 21.0.0) 交叉编译，目标架构 `aarch64-linux-android26`，所有二进制链接 Bionic libc。

仓库：[`amphora-dev/imagefs`](https://github.com/amphora-dev/imagefs)

## 快速开始

```bash
./build-all.sh              # 编译全部包并打包 imagefs.txz
JOBS=8 ./build-all.sh       # 指定并发
./build-all.sh zlib glib    # 仅构建指定包
```

CI 环境见 [`ci/Dockerfile`](ci/Dockerfile)；本地也可：

```bash
docker build -f ci/Dockerfile -t imagefs-ci ci
docker run --rm -it -v "$PWD:/workspace" imagefs-ci ./build-all.sh
```

`android-sysvshm` / `alsa-android-aserver` 源码在 [`vendor/winlator-bionic/`](vendor/winlator-bionic/)（无需再 clone winlator）。

## CI / Release

GitHub Actions（[`.github/workflows/build-imagefs.yml`](.github/workflows/build-imagefs.yml)）：

| 触发 | 行为 |
|------|------|
| `main` push | 完整构建，覆盖固定标签 Release **`amphora`** |
| Pull Request | 仅构建验证 |
| tag push | 按 tag 名创建 Release |

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz.sha256sum
```

## 构建产物

- `imagefs.txz` — 运行时 rootfs（已裁剪 headers / 静态库 / man / glvnd / 多余 bin）
- Box64 不进本仓库（Amphora `Box64.wcp`）
- 音频：ALSA + android_aserver（无 pulseaudio）

## 包列表

基础库、X11/Vulkan 垫片、openssl/gnutls、alsa、sdl2、gstreamer、android-spawn/sysv-semaphore/sysvshm。详见 `build-all.sh` 的 `ALL_PACKAGES`。

## 关键设计

- **Bionic libc**: 链接 `libc.so`，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin` `/etc` `/lib` → `usr/*`
- **ALSA android_aserver**: ALSA → Android 音频服务器

详见 [BUILD-REPORT.md](BUILD-REPORT.md)
