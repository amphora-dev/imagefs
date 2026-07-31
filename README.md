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

两个独立 workflow，共享 **composite actions** + `ci/*.sh`（GitHub 的本地复用方式，不是合成一个 yaml）：

| Workflow | 触发 | 产物 |
|----------|------|------|
| [`build-imagefs.yml`](.github/workflows/build-imagefs.yml) | `main` push/PR（`paths-ignore` 文档与 box64 源）、`workflow_dispatch`、tag `v*`/`imagefs-*` | Release **`amphora`** → pin `rootfs` |
| [`build-box64.yml`](.github/workflows/build-box64.yml) | 改 box64 源 / `workflow_dispatch`（**无**每日 schedule） | Release **`box64`** → pin `box64` |

共享：

| 路径 | 作用 |
|------|------|
| [`.github/actions/setup-ndk-build`](.github/actions/setup-ndk-build) | apt 依赖 + 解析 NDK |
| [`.github/actions/bump-manifest`](.github/actions/bump-manifest) | bump `content_manifest` 某一 component |
| `ci/gate-*.sh` / `ci/build-box64-wcp.sh` / … | 门闩与构建逻辑 |

imagefs 发布仍看产物 SHA；内容不变则不刷新 Release / pin。

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
https://github.com/amphora-dev/imagefs/releases/download/box64/Box64-<ver>-<sha>.wcp
```

```bash
# 本地 Box64
export ANDROID_NDK_HOME=/path/to/ndk
bash ci/build-box64-wcp.sh
```

CMake 对齐 WinNative Bionic：`-DANDROID=1 -DBIONIC=1 -DARM_DYNAREC=1 -DBAD_SIGNAL=1 -DTERMUX=0`，NDK API **31**。可选 [`vendor/box64-patches/pipetto-controller-fix.patch`](vendor/box64-patches/pipetto-controller-fix.patch)。

## 构建产物

- `imagefs.txz` — 运行时 rootfs（已裁剪 headers / 静态库 / man / glvnd / 多余 bin）；**不含** box64
- `Box64-*.wcp` — 独立模拟器包（xz tar + `profile.json`），由 Amphora `ContentsManager` 装到 `${bindir}/box64`
- 音频：ALSA + android_aserver（无 pulseaudio）

## 包列表

基础库、X11/Vulkan 垫片、openssl/gnutls、alsa、sdl2、gstreamer、android-spawn/sysv-semaphore/sysvshm。见 `build-all.sh` 的 `ALL_PACKAGES` 与 `packages/depends.conf`。

## 关键设计

- **Bionic libc**: 链接 `libc.so`，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin` `/etc` `/lib` → `usr/*`
- **ALSA android_aserver**: ALSA → Android 音频服务器

详见 [BUILD-REPORT.md](BUILD-REPORT.md)
