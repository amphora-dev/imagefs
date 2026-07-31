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
bash ci/verify/pkg-selftest.sh   # 不编包，只测 DEPENDS / topo / stamp
```

依赖：cmake / meson / autotools / patchelf / ccache / NDK。CI 在 `ubuntu-latest` 上直接装这些工具运行，不再包一层 Docker。

`android-sysvshm` / `alsa-android-aserver` 源码在 [`vendor/winlator-bionic/`](vendor/winlator-bionic/)。

## 目录结构

```text
ci/{setup,gate,publish,verify,box64}/   # CI 脚本（见 ci/README.md）
packages/{compress,text,android,x11,…}/ # 配方按类别分目录 + depends.conf
docs/{analysis,meson,scripts,evidence}/
lib/pkg.sh                              # DEPENDS / topo / stamp
```

## Buildroot-lite 布局

借鉴 Buildroot 的核心思想，保持 bash 轻量实现：

| 目录 | 作用 |
|------|------|
| `$BUILD_DIR/host` | host 工具（不进 imagefs.txz） |
| `$BUILD_DIR/staging` | 交叉编译 sysroot（headers + libs，增量编译） |
| `$BUILD_DIR/target` | 运行时 rootfs（裁剪后打包） |

- 依赖：[`packages/depends.conf`](packages/depends.conf) + [`lib/pkg.sh`](lib/pkg.sh) 做传递展开与拓扑排序（配方在 [`packages/`](packages/README.md) 各子目录）
- 增量：content stamp = 配方脚本 + depends 行 + 依赖 stamp + toolchain fingerprint（改依赖会失效下游）
- 包脚本仍写 `$PREFIX`（=`staging/usr`），无需逐包大改

## CI / Release

分层（L0 脚本 / L1 leaf Box64 / L2 graph imagefs）、固定 Release tag、pin 约定见 **[`ci/README.md`](ci/README.md)**。不要把 `depends.conf` 拆成每包一个 GHA job。

| Workflow | 触发 | 产物 |
|----------|------|------|
| [`build-imagefs.yml`](.github/workflows/build-imagefs.yml) | 改 packages/lib/vendor/root `*.sh`；或手动 | `amphora` → pin `rootfs` |
| [`build-box64.yml`](.github/workflows/build-box64.yml) | 改 `ci/box64` / patches；或手动 | `box64` → pin `box64` |

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
https://github.com/amphora-dev/imagefs/releases/download/box64/Box64-<ver>-<sha>.wcp
```

```bash
export ANDROID_NDK_HOME=/path/to/ndk
bash ci/box64/build-wcp.sh
```

## 构建产物

- `imagefs.txz` — 运行时 rootfs（已裁剪 headers / 静态库 / man / glvnd / 多余 bin）；**不含** box64
- `Box64-*.wcp` — 独立模拟器包（xz tar + `profile.json`），由 Amphora `ContentsManager` 装到 `${bindir}/box64`
- 音频：ALSA + android_aserver（无 pulseaudio）

## 包列表

基础库、X11/Vulkan 垫片、openssl/gnutls、alsa、sdl2、gstreamer、android-*。见 `build-all.sh` 的 `ALL_PACKAGES`、[`packages/depends.conf`](packages/depends.conf) 与 [`packages/README.md`](packages/README.md)。

## 关键设计

- **Bionic libc**: 链接 `libc.so`，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin` `/etc` `/lib` → `usr/*`
- **ALSA android_aserver**: ALSA → Android 音频服务器

详见 [BUILD-REPORT.md](BUILD-REPORT.md)
