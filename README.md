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

两条流水线，刻意解耦（Box64 更新更频繁，不必重下整份 rootfs）：

### imagefs rootfs — [`.github/workflows/build-imagefs.yml`](.github/workflows/build-imagefs.yml)

| 触发 | 行为 |
|------|------|
| `main` push | 完整构建，覆盖固定标签 Release **`amphora`**；只 bump `content_manifest.components.rootfs` |
| Pull Request | 仅构建验证 |
| tag push | 按 tag 名创建 Release |

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
```

### Box64 WCP — [`.github/workflows/build-box64.yml`](.github/workflows/build-box64.yml)

| 触发 | 行为 |
|------|------|
| 每日 schedule / `workflow_dispatch` | 编 Bionic `box64`，打 `Box64-<ver>-<sha>.wcp`，覆盖固定标签 Release **`box64`**；只 bump `content_manifest.components.box64` |
| `main` 上改 `ci/build-box64-wcp.sh` / `patches/box64/**` | 同上 |
| 上游 tip 已发布过 | schedule 自动跳过 |

```bash
# 本地
export ANDROID_NDK_HOME=/path/to/ndk
bash ci/build-box64-wcp.sh
# → artifacts/Box64-0.4.x-<shortsha>.wcp
```

```text
https://github.com/amphora-dev/imagefs/releases/download/box64/Box64-<ver>-<sha>.wcp
```

CMake 对齐 WinNative Bionic：`-DANDROID=1 -DBIONIC=1 -DARM_DYNAREC=1 -DBAD_SIGNAL=1 -DTERMUX=0`，NDK API **31**（Bionic 提供 inheritsched/mutex protocol；运行时仍只依赖 `libc`/`libm`/`libdl`，与 imagefs API 26 rootfs 共存）。可选应用 [`patches/box64/pipetto-controller-fix.patch`](patches/box64/pipetto-controller-fix.patch)。

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
