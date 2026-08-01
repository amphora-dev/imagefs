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
ci/{setup,gate,publish,verify,box64,wrapper}/   # CI 脚本（见 ci/README.md）
packages/{compress,text,android,x11,…}/ # 配方按类别分目录 + depends.conf
docs/{analysis,meson,evidence}/
lib/pkg.sh                              # DEPENDS / topo / stamp
lib/ndk.sh                              # NDK 发现（图构建与 L1 leaf 共用）
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

分层（L0 脚本 / L1 leaf Box64+wrapper / L2 graph imagefs）、固定 Release tag、pin 约定见 **[`ci/README.md`](ci/README.md)**。不要把 `depends.conf` 拆成每包一个 GHA job。

| Workflow | 触发 | 产物 |
|----------|------|------|
| [`build-imagefs.yml`](.github/workflows/build-imagefs.yml) | 改 packages/lib/vendor/root `*.sh`；或手动 | `amphora` → pin `rootfs` |
| [`build-box64.yml`](.github/workflows/build-box64.yml) | 改 `ci/box64` / patches；或手动 | `box64` → pin `box64` |
| [`build-wrapper.yml`](.github/workflows/build-wrapper.yml) | 改 `ci/wrapper` / X11 staging / patches；或手动 | `wrapper` → pin `turnip` |

```text
https://github.com/amphora-dev/imagefs/releases/download/amphora/imagefs.txz
https://github.com/amphora-dev/imagefs/releases/download/box64/Box64-<ver>-<sha>.wcp
https://github.com/amphora-dev/imagefs/releases/download/wrapper/wrapper-<mesa_sha>.tzst
```

```bash
export ANDROID_NDK_HOME=/path/to/ndk
bash ci/box64/build-wcp.sh
# Pipetto vulkan wrapper (uses staging X11/drm as sysroot; not in imagefs.txz)
bash ci/wrapper/build-tzst.sh
```

## 构建产物

- `imagefs.txz` — 运行时 rootfs（已裁剪 headers / 静态库 / man / glvnd / 多余 bin）；**不含** box64 / wrapper
- `Box64-*.wcp` — 独立模拟器包（xz tar + `profile.json`），由 Amphora `ContentsManager` 装到 `${bindir}/box64`
- `wrapper-*.tzst` — Pipetto `libvulkan_wrapper.so` + adrenotools/ICD（zstd tar），pin 为 manifest `turnip`
- 音频：ALSA + android_aserver（无 pulseaudio）

## 包列表

基础库、X11/Vulkan 垫片、openssl/gnutls、alsa、sdl2、gstreamer、android-*。见 `build-all.sh` 的 `ALL_PACKAGES`、[`packages/depends.conf`](packages/depends.conf) 与 [`packages/README.md`](packages/README.md)。

取舍依据（为什么是这些包、为什么不是那些）见 [`docs/analysis/PACKAGE-SELECTION.md`](docs/analysis/PACKAGE-SELECTION.md)；可执行版本是 [`ci/verify/wine-deps.sh`](ci/verify/wine-deps.sh)。

写/改配方前先读 [`docs/analysis/ELF-PITFALLS.md`](docs/analysis/ELF-PITFALLS.md)：patchelf、符号版本、soname 软链这三类问题 `readelf` 都看不出来，只有真机 `dlopen` 会炸。配方风格与做法对照见 [`docs/analysis/MICEWINE-COMPARISON.md`](docs/analysis/MICEWINE-COMPARISON.md)（参照实现 [`KreitinnSoftware/MiceWine-Packages`](https://github.com/KreitinnSoftware/MiceWine-Packages)）。

## 关键设计

- **Bionic libc**: 链接 `libc.so`，interpreter = `/system/bin/linker64`
- **merged-usr**: `/bin` `/etc` `/lib` → `usr/*`
- **ALSA android_aserver**: ALSA → Android 音频服务器
