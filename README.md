# imagefs

winlator bionic fork 的 imagefs 根文件系统完整构建系统。目标架构 `aarch64-linux-android26`，所有二进制链接 Bionic libc。

仓库：[`amphora-dev/imagefs`](https://github.com/amphora-dev/imagefs)

## 快速开始

```bash
# 可选：指向本机 NDK（CI 用 GitHub runner 自带的）
export ANDROID_NDK_HOME=/path/to/ndk

./build-all.sh              # 编译全部包并打包 imagefs.txz
JOBS=8 ./build-all.sh       # 指定并发
./build-all.sh zlib glib    # 构建指定包及其传递依赖
bash ci/pkg-selftest.sh     # 不编包，只测 DEPENDS / topo / stamp
```

依赖：cmake / meson / autotools / patchelf / ccache / NDK。CI 在 `ubuntu-latest` 上直接装这些工具运行，不再包一层 Docker。

`android-sysvshm` / `alsa-android-aserver` 源码在 [`vendor/winlator-bionic/`](vendor/winlator-bionic/)。

## Buildroot-lite 布局

借鉴 Buildroot 的核心思想，保持 bash 轻量实现：

| 目录 | 作用 |
|------|------|
| `$BUILD_DIR/host` | host 工具（不进 imagefs.txz） |
| `$BUILD_DIR/staging` | 交叉编译 sysroot（headers + libs，增量编译） |
| `$BUILD_DIR/target` | 运行时 rootfs（裁剪后打包） |

- 依赖：[`packages/depends.conf`](packages/depends.conf) + [`lib/pkg.sh`](lib/pkg.sh) 做传递展开与拓扑排序
- 增量：content stamp = 配方脚本 + depends 行 + 依赖 stamp + toolchain fingerprint（改依赖会失效下游）
- 包脚本仍写 `$PREFIX`（=`staging/usr`），无需逐包大改

## CI / Release

GitHub Actions（[`.github/workflows/build-imagefs.yml`](.github/workflows/build-imagefs.yml)）：

| 触发 | 行为 |
|------|------|
| `main` push | 完整构建，覆盖固定标签 Release **`amphora`**；成功后 bump [`amphora-dev/content_manifest`](https://github.com/amphora-dev/content_manifest) |
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

基础库、X11/Vulkan 垫片、openssl/gnutls、alsa、sdl2、gstreamer、android-spawn/sysv-semaphore/sysvshm。见 `build-all.sh` 的 `ALL_PACKAGES` 与 `packages/depends.conf`。

## 关键设计

- **Bionic libc**: 链接 `libc.so`，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin` `/etc` `/lib` → `usr/*`
- **ALSA android_aserver**: ALSA → Android 音频服务器

详见 [BUILD-REPORT.md](BUILD-REPORT.md)
