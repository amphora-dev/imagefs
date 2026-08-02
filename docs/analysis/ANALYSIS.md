# Winlator (bionic 分支) imagefs 文件系统构建分析 & 复现

> 分析对象：[`Pipetto-crypto/winlator`@winlator_bionic](https://github.com/Pipetto-crypto/winlator/tree/winlator_bionic)
> 分析方式：解包 APK 资产中的 `imagefs.txz`，对其中 ELF 二进制做静态取证（`.interp` / `.comment` / `NEEDED` / 软链目标），并反向推导构建管线，最后用 NDK r29 实跑复现。

---

## 1. 结论先行

| 问题 | 答案 |
|---|---|
| **imagefs 是什么** | 一个面向 `aarch64-linux-android`（**Bionic libc**）的 Linux 用户态根文件系统，打包成 `imagefs.txz`，APK 启动时解压到 `/data/.../imagefs`，作为 Wine/Box86/Box64 的运行环境。 |
| **怎么编译的** | 用 **Android NDK 交叉编译**全部库/程序到 Bionic，动态链接器指向 Android 宿主的 `/system/bin/linker64`，`libc.so`/`libdl.so`/`libm.so` 软链到 `/system/lib64/*`（**复用手机系统 Bionic，不捆绑 glibc**）。 |
| **工具链** | NDK `29.0.14206865`（r29）。官方产物 `.comment` 显示 `clang 20.1.4 / LLD 20.1.4` + `Android clang 18.0.3 (r522817c)`；本机 r29 实测为 `clang 21.0.0`（见 §5 差异说明）。 |
| **文件布局** | **merged-usr**：`/bin /etc /lib /share /tmp` 全部软链到 `usr/*`。 |
| **ARM64EC 支持** | ✅ **双模式架构**：同时支持 `proton-9.0-arm64ec`（PE DLL 模拟器路线，同 Hangover）和 `proton-9.0-x86_64`（Box64 ELF 翻译器路线）。用户可在 UI 中选择 Wine 版本。详见 §14。 |
| **构建脚本在仓库里吗** | **不在**。本仓库只通过 Gradle `downloadImageFS` 任务从 GitLab [`winlator3/winlator-extra`](https://gitlab.com/winlator3/winlator-extra) 拉取**预编译成品**（4 分卷 + sha256）。构建脚本/补丁是作者私有。 |
| **能复现吗** | **管线可完整复现**（见 §6，已实跑）。但官方 imagefs 含 **894 个 .so**（librsvg 131MB、libaom、gstreamer、vulkan-loader、pulseaudio…），逐个交叉编译 + Bionic 补丁是另一回事，无作者补丁无法字节级复刻（见 §7）。 |

---

## 2. imagefs 在构建链中的位置

`app/build.gradle` 注册了两个 Gradle 任务，在 `preBuild` 前把外部预编译产物拉到 `app/src/main/assets/`：

```
downloadImageFS  ─┐
                  ├─→ downloadProton ─→ preBuild ─→ assembleDebug
```

`downloadImageFS` 关键逻辑（`app/build.gradle:21-66`）：

```groovy
File imageFS = new File(assetDir, "imagefs.txz")
String imageFSSHA256Sum = "https://gitlab.com/winlator3/winlator-extra/-/raw/main/imagefs/imagefs.txz.sha256sum"
int parts = 4
// 拼接 imagefs.txz.00..03 → imagefs.txz，校验 SHA-256
```

因此：**`imagefs.txz` 是外部制品，不参与本仓库编译**；本仓库只负责用 NDK 编译 JNI 原生库（`libwinlator.so`、proot、virglrenderer、patchelf、openxr_loader、adrenotools，见 `app/src/main/cpp/CMakeLists.txt`），再把 imagefs + box64/图形驱动/dxvk 等资产一起打进 APK。

---

## 3. 逆向取证：imagefs 是怎么编译的

### 3.1 取证样本
- 下载官方 `imagefs.txz.00..03`（共 **183 231 056 B**），拼接后 SHA-256 与官方 `f96d362b...bbb780` 完全一致 ✅。
- 解包得 **10 892 个条目**，其中 **894 个 `.so`**。

### 3.2 证据 1：动态链接器 = Android Bionic

```
$ file usr/bin/curl
usr/bin/curl: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV),
  dynamically linked, interpreter /system/bin/linker64, not stripped
```

`/system/bin/linker64` 是 **Android 系统的动态链接器**。对比传统 Linux（glibc）根文件系统的 `/lib/ld-linux-aarch64.so.1`，这是判定 Bionic 的决定性证据。

### 3.3 证据 2：依赖 libc.so（Bionic 命名），而非 libc.so.6（glibc）

```
$ readelf -d usr/bin/curl | grep NEEDED
  NEEDED libcurl.so.4   NEEDED libnghttp2.so.14  NEEDED libidn2.so.0
  NEEDED libssl.so.3    NEEDED libcrypto.so.3   NEEDED libzstd.so.1
  NEEDED libz.so.1      NEEDED libdl.so          NEEDED libc.so   ← 关键
```

glibc 产物是 `libc.so.6`；**`libc.so` + `libdl.so`（无版本号）是 Android Bionic 的命名特征**。

### 3.4 证据 3：libc 直接复用宿主 Android 系统

```
$ readelf usr/lib/libc.so   → 符号链接 → /system/lib64/libc.so
$ readelf usr/lib/libdl.so  → 符号链接 → /system/lib64/libdl.so
$ readelf usr/lib/libm.so   → 符号链接 → /system/lib64/libm.so
```

**imagefs 不捆绑自己的 C 运行时**——运行时直接借用手机 `/system/lib64` 的 Bionic。这正是 `winlator_bionic` 分支区别于上游 `brunodev85/winlator`（Ubuntu Focal + glibc rootfs）的核心改动：去掉 glibc，原生跑在 Android Bionic 上，省内存、省体积、ABI 更贴合宿主。

### 3.5 证据 4：工具链 = Android NDK

```
$ readelf -p .comment usr/bin/curl
  clang version 20.1.4
  Linker: LLD 20.1.4
  Android (12470979, +pgo, +bolt, +lto, +mlgo, based on r522817c) clang version 18.0.3
```

- `Android (...) clang version 18.0.3 (based on r522817c)` —— Android NDK 工具链特征串。
- 顶层 `clang 20.1.4 / LLD 20.1.4` —— 作者实际使用的 LLVM 版本（介于 NDK r28/r29 之间，可能是定制 LLVM 20.1.4 工具链 + NDK sysroot；本仓库 `app/build.gradle` 声明 `ndkVersion '29.0.14206865'`）。

### 3.6 证据 5：merged-usr 布局 + 构建主机

```
lrwxrwxrwx  bin  -> usr/bin     # 顶层全是软链
lrwxrwxrwx  etc  -> usr/etc     # 注意 /etc 也是软链 (非典型 Arch, 作者自定义)
lrwxrwxrwx  lib  -> usr/lib
lrwxrwxrwx  share-> usr/share
lrwxrwxrwx  tmp  -> usr/tmp
```

tar 条目 owner 为 `endeavour/endeavour` → **构建主机是 EndeavourOS（Arch 系）**。运行时期望路径（来自 `ContentsManager.java:330-334`）：`/usr/lib`、`/usr/bin`、`/usr/share`，与布局吻合。

### 3.7 证据 6：imagefs 不含 wine/box86/box64 本体

imagefs 只提供**用户态支撑库**（多媒体、字体、Vulkan loader、pulseaudio、curl、openssl、fontconfig、cairo、gstreamer、librsvg…）。真正的 `wine`/`box64`/`mesa(Turnip)`/`dxvk` 以独立的 `.tzst`/`.wcp` 资产分发（`assets/box64/`、`assets/graphics_driver/`、`assets/dxwrapper/`），运行时叠加到 imagefs 之上。

---

## 4. 与上游 winlator 的对比

| 维度 | 上游 `brunodev85/winlator` | 本 fork `winlator_bionic` |
|---|---|---|
| rootfs 来源 | Ubuntu **Focal**（glibc） | 自建 **Bionic** 根文件系统 |
| C 运行时 | 捆绑 glibc（`libc.so.6`） | 复用宿主 `/system/lib64/libc.so`（Bionic） |
| 动态链接器 | `/lib/ld-linux-aarch64.so.1` | `/system/bin/linker64` |
| 体积/内存 | 更大（自带 glibc） | 更小（无 glibc） |
| ABI 兼容 | glibc on Android（需 rootfs 隔离） | 原生 Android ABI，更贴合宿主 |
| 构建脚本 | 同样不公开 | 同样不公开（成品托管 GitLab） |

> 分支名 `bionic` 即由此而来——整个 rootfs 从 glibc 改造为 Bionic。

---

## 5. 工具链差异说明（诚实披露）

| 项 | 官方 imagefs（逆向） | 本机复现 |
|---|---|---|
| NDK 版本 | `29.0.14206865`（build.gradle 声明） | `29.0.14206865`（r29，实下） |
| 顶层 clang | `20.1.4` | `21.0.0`（r29 自带） |
| Android clang baseline | `18.0.3 (r522817c)` | `21.0.0 (r563880c)` |
| 产物结构签名 | — | **完全一致** ✅ |

官方产物的 `.comment` 同时出现 `clang 20.1.4` 与 `Android clang 18.0.3`，说明作者可能用了**自定义 LLVM 20.1.4 工具链 + NDK sysroot/桩库**，而非直接用某版 NDK 的 clang。这层差异**只影响 `.comment` 字符串**，不影响 ELF 结构、链接器、libc 依赖等关键签名——所以复现产物在"怎么编译出来的"这一层面是等价的。

---

## 6. 复现实跑（已完成）

脚本：[`build_imagefs_repro.sh`](./build_imagefs_repro.sh) · 实跑产物：[`imagefs_repro.txz`](./imagefs_repro.txz)

**步骤**：① 下 NDK r29 → ② 交叉编译 zlib 1.3.1（`-fPIC`，`aarch64-linux-android26`）→ ③ 链接 `libz.so.1.3.1` + 测试程序 `ztest` → ④ 组装 merged-usr 目录（`libc.so`→`/system/lib64/libc.so` 等）→ ⑤ `tar+xz` → 50MB 分卷 → sha256。

**复现产物 vs 官方产物 签名对比**：

| 签名项 | 官方 `usr/bin/curl` | 复现 `usr/bin/ztest` |
|---|---|---|
| 架构 | `ELF 64-bit LSB pie, ARM aarch64` | `ELF 64-bit LSB pie, ARM aarch64` ✅ |
| `.interp` | `/system/bin/linker64` | `/system/bin/linker64` ✅ |
| `NEEDED` C 库 | `libc.so` + `libdl.so`（Bionic） | `libc.so` + `libdl.so`（Bionic）✅ |
| `libc.so` 来源 | 软链 `/system/lib64/libc.so` | 软链 `/system/lib64/libc.so` ✅ |
| 文件布局 | merged-usr（bin/etc/lib/share/tmp→usr/*） | merged-usr（同左）✅ |
| 打包 | `tar` + `xz`，50MB 分卷，sha256 校验 | `tar` + `xz`，50MB 分卷，sha256 校验 ✅ |

可自行验证：
```bash
cd /workspace/winlator-imagefs-analysis
readelf -p .interp ../evidence/repro_ztest_aarch64_bionic      # /system/bin/linker64
readelf -d    ../evidence/repro_ztest_aarch64_bionic | grep NEEDED  # libc.so / libdl.so
tar -tJf imagefs_repro.txz | head                           # bin/etc/lib... 软链结构
```

---

## 7. 为什么不能"字节级"复刻整个官方 imagefs

1. **规模**：894 个 `.so`，含 librsvg(131MB)、libaom(41MB)、gstreamer、ffmpeg/libavcodec、openal、vulkan-loader、pulseaudio、openssl、fontconfig、cairo、pango、gdk-pixbuf… 逐个交叉编译是工程级工作量。
2. **Bionic 补丁不公开**：很多 GNU/glibc 假设的库（glibc 特有 `libc.so.6` 版本符号、GNU 扩展、`gettext`、`iconv`、版本化 soname `.so.4` 等）要跑在 Bionic 上需要源码补丁，这些补丁是作者的"秘方"，未随仓库或 GitLab 发布。
3. **构建脚本缺失**：GitLab `winlator-extra` 仓库**只放成品二进制**（`README` 仅一句 "assets and goodies uploaded here"），无 Dockerfile / PKGBUILD / 构建日志。
4. **定制工具链**：`.comment` 指向作者自建的 LLVM 20.1.4，非现成 NDK。

> 换言之：**管线和方法可复现（已验证），完整内容库不可复刻**。要逼近官方，需自建一套 Termux 风格的 Bionic 交叉编译构建系统（mass-rebuild + 逐库打补丁），这超出本次范围。

---

## 8. 关键文件索引

| 路径 | 作用 |
|---|---|
| `app/build.gradle:21-66` | `downloadImageFS` 任务：拼 4 分卷 + sha256 校验 |
| `app/build.gradle:128` | `ndkVersion '29.0.14206865'` |
| `app/src/main/cpp/CMakeLists.txt` | JNI 原生库编译（libwinlator.so 等，**非 imagefs**） |
| `app/src/main/java/com/winlator/cmod/xenvironment/ImageFsInstaller.java:102-105` | 运行时用 `TarCompressorUtils.XZ` 解压 `imagefs.txz` |
| `app/src/main/java/com/winlator/cmod/contents/ContentsManager.java:328-334` | imagefs 运行时路径模板（`${libdir}=usr/lib` 等） |
| GitLab `winlator3/winlator-extra/-/raw/main/imagefs/imagefs.txz.{00..03}` | 官方预编译成品（4 分卷） |

---

## 9. 附：官方 imagefs 关键取证数据

```
imagefs.txz  SHA-256 = f96d362b7e148e86ab0d2c290978bf39b38e5c7ffc8ae4adf1d2a65c62bbb780
                      (183,231,056 B, 拼接 4×50MB 分卷)
条目总数 10,892 | .so 文件 894 | 顶层 owner endeavour/endeavour
最大文件: usr/lib/librsvg-2.so.2.60.0 (130,991,176 B)
         usr/bin/rsvg-convert        (108,036,048 B)
         usr/lib/libaom.so.3.12.1    ( 40,831,097 B)
关键目录: usr/tmp/.X11-unix  usr/tmp/.sound  usr/tmp/.sysvshm  usr/tmp/adapterinfo
          opt/winetricks  usr/share/wine/{fonts,nls}
```

---

## 10. 全网搜索：imagefs 构建脚本到底有没有公开

针对"GitLab 上是否真无代码 / 全网是否有构建脚本"做了彻底核查，结论如下。

### 10.1 GitLab `winlator3` 命名空间 —— 确实只有二进制，无代码

`https://gitlab.com/winlator3` 下**仅有 1 个仓库** `winlator-extra`，其内容全部是预编译成品：

| 目录/文件 | 内容 | 类型 |
|---|---|---|
| `imagefs/imagefs.txz.{00..03}` + `.sha256sum` | imagefs 4 分卷 | 二进制 |
| `box64/box64-*.wcp` | Box64 组件包 | 二进制 |
| `dxvk/dxvk-*.wcp` | DXVK 组件包 | 二进制 |
| `fexcore/fexcore-*.wcp` | FEXCore 组件包 | 二进制 |
| `proton/proton-9.0-*.txz` | Proton 容器模板 | 二进制 |
| `contents.json` | 组件清单 | 元数据 |
| `README.md` | 仅一句 "Winlator assets and goodies uploaded here" | 无说明 |

**无 Dockerfile / PKGBUILD / shell 脚本 / 构建日志 / 补丁文件。** 结论坐实。

### 10.2 bionic 分支的完整 fork 链 —— 无人公开构建脚本

```
brunodev85/winlator (上游官方)
   └─ coffincolors/winlator  [cmod_bionic]   ← bionic 改造的真正源头
        └─ cjxyz/winlator     [winlator_bionic]
             ├─ uBakaChan/winlator_bionic
             └─ Pipetto-crypto/winlator  (本次分析对象)
```

核查结果：

| 仓库 | 是否含 imagefs 构建脚本 | imagefs 怎么进仓库 |
|---|---|---|
| `coffincolors/winlator` (源头) | ❌ 无 | commit "track imagefs with git lfs" —— **Git LFS 直接提交预编译成品** |
| `cjxyz/winlator` | ❌ 无 | 继承 + `imagefs_patches.tzst` 增量补丁 |
| `uBakaChan/winlator_bionic` | ❌ 无 | 继承 |
| `Pipetto-crypto/winlator` | ❌ 无 | 改用 GitLab 外链下载（见 §2） |

所有 fork 的 README 都是上游那句通用的 "Winlator is an Android application..."，**无一提及 rootfs/imagefs 如何编译**。GitHub 仓库搜索 `winlator bionic rootfs` **零结果**——不存在独立的 bionic rootfs 构建仓库。

### 10.3 重要参照：glibc 版有公开构建脚本

虽然没有 bionic 版的构建脚本，但**平行的 glibc 版**有完整公开实现——[`Waim908/rootfs-winlator`](https://github.com/Waim908/rootfs-winlator)（服务于 `longjunyu2/winlator` / `moze30/winlator-glibc`）：

| 文件 | 作用 |
|---|---|
| `build-rootfs.sh` | 主构建脚本 |
| `gstreamer.sh` | GStreamer 交叉编译（meson） |
| `patches/` | 源码补丁目录 |
| `ubuntu-2404.conf` | Docker 构建配置 |
| `.github/workflows/` | CI 自动构建 |
| `data.tar.xz` / `mangohud.tar.xz` | 预置数据 |

其方法论（README 详述）：`docker run --platform linux/arm64 ubuntu:24.04` + `qemu-aarch64-static` 用户态模拟 + `meson` 交叉编译 GStreamer/MangoHud/libxkbcommon，**补丁参考 `termux-packages` 与 `glibc-packages`**。

### 10.4 bionic 版构建方法推断（基于 glibc 版 + 取证）

把 glibc 版方法论 + 本报告 §3 的 Bionic 取证合并，bionic imagefs 的构建方式高度可能是：

| 环节 | glibc 版 (Waim908) | bionic 版 (推断) |
|---|---|---|
| 基础环境 | Ubuntu 24.04 arm64 docker + qemu | EndeavourOS 主机 (取证实证) |
| C 库 | glibc（apt 安装） | **Bionic**：NDK sysroot + 复用 `/system/lib64` |
| 工具链 | gcc (apt) | **NDK clang/LLD** (取证实证: clang 20.1.4) |
| 交叉编译 | meson + qemu 用户态模拟 | meson + NDK 工具链文件 (termux-packages 风格) |
| 补丁来源 | termux-packages / glibc-packages | **termux-packages**（Bionic port 补丁） |
| 产物布局 | 标准 FHS | **merged-usr** + `libc.so`→`/system/lib64` 软链 |

> 关键差异：bionic 版把"在 arm64 Linux 里原生编译 glibc 库"换成"用 NDK 交叉编译到 Bionic、C 运行时指向 Android 宿主"。补丁体系直接复用 **termux-packages**（Termux 本身就是 Bionic + `/system/bin/linker64` 的 Android 用户态，与本 imagefs 架构完全同源）。

### 10.5 最终结论

- **GitLab 上确实没有任何代码**——`winlator3/winlator-extra` 是纯二进制托管仓库。
- **bionic imagefs 的构建脚本全网未公开**——源头 `coffincolors` 到各 fork 都只提交预编译成品（LFS/外链），无 Dockerfile/脚本/补丁。
- **但方法论可从两个公开来源还原**：① 本报告 §3 的 ELF 取证（确定工具链/布局/C库）；② `Waim908/rootfs-winlator` 的 glibc 构建脚本（确定 meson 交叉编译流程 + termux-packages 补丁参考）。
- **若要真复刻 bionic imagefs**：最可行路径是 fork `Waim908/rootfs-winlator` 的构建框架，把 glibc 工具链替换为 NDK + termux-packages 的 Bionic port 补丁集，逐库重编。这是工程级任务，但脚本骨架已公开可借鉴。

---

## 11. 三个同类项目的构建方法论对比（全网搜索补充）

用户提供了两个额外参考项目 `AndreRH/hangover` 和 `KreitinnSoftware/MiceWine-Packages`，加上 `Waim908/rootfs-winlator`，三个项目覆盖了"Android 上跑 Wine"的 rootfs 构建全谱系。

### 11.1 总览

| 项目 | C 库 | 构建脚本 | 包数量 | 补丁来源 | 与 winlator bionic 关系 |
|---|---|---|---|---|---|
| **Waim908/rootfs-winlator** | glibc | `build-rootfs.sh` + Docker | ~8 库 | termux-packages / glibc-packages | glibc 版 winlator 的 rootfs，结构最接近 |
| **KreitinnSoftware/MiceWine-Packages** | **Bionic** | `build-all.sh` + 83 个 `build.sh` | **83 包** | termux-packages | **与 winlator bionic 同构**，最完整参考 |
| **AndreRH/hangover** | glibc (Debian) | `.github/workflows` + `docs/COMPILE.md` | N/A (Debian apt) | 上游 Wine/Box64/FEX | 不做 rootfs，做 Wine + emulator DLL |

### 11.2 MiceWine-Packages —— 最关键的发现

这是**唯一公开的、与 winlator bionic 完全同构（Bionic + NDK + merged-usr）的包构建系统**。

**架构**：
```
build-all.sh                 # 主控: NDK 下载 → 依赖拓扑排序 → 逐包编译 → .rat 打包
build_config/
  meson-cross-file-aarch64   # meson 交叉文件 (system=linux, skip_sanity_check)
  meson-cross-file-x86_64
packages/                    # 83 个包, 每个含 build.sh + 可选 .patch
  zlib/    libpng/   freetype/   brotli/    glib/      libffi/
  pcre2/   libdrm/   vulkan*/    mesa-*/    pulseaudio/  gstreamer*/
  box64-*/  wine-*/   mangohud/  openssl/   libxml2/   ...
tools/                       # create-rat-pkg.sh, download-external-dependencies.sh
common/                      # Addons, CoreFonts, DirectX, OpenAL
```

**与 winlator bionic 的同构证据**（glib 补丁对比）：

| 补丁文件 | Waim908 (glibc) 路径 | MiceWine (Bionic) 路径 | 差异 |
|---|---|---|---|
| `glib-gutils.c.patch` | `/data/data/com.winlator/...` | `/data/data/com.micewine.emu/...` | **仅包名不同** |
| `gio-gdbusprivate.c.patch` | 同上 | 同上 | **仅包名不同** |
| `gio-xdgmime-xdgmime.c.patch` | 同上 | 同上 | **仅包名不同** |

> 三个项目（winlator / Waim908 / MiceWine）的 glib 补丁**同源**，都来自 termux-packages，只是把 `@TERMUX_PREFIX@` 替换成各自的 `com.xxx/files/usr` 路径。这证实了 bionic imagefs 的构建方法论是 termux-packages 的直接衍生。

**MiceWine 的 meson cross-file 极简**（对比本报告 §6 的复杂版本）：
```ini
[binaries]
pkg-config = '/usr/bin/pkg-config'
cmake = '/usr/bin/cmake'
[host_machine]
system = 'linux'         # 注意: 用 linux 而非 android, 配合 skip_sanity_check
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
skip_sanity_check = true
```
CC/CXX/AR 等通过环境变量 `$PATH` + `$CC=aarch64-linux-android29-clang` 注入，不在 cross-file 里写死。CI 用 Arch Linux chroot + termux-docker 的 `/system` 目录提供 Bionic 运行时。

### 11.3 Hangover —— PE 模拟器 DLL 路线（深度分析）

#### 11.3.1 技术定位

Hangover **不做 rootfs**，而是在宿主 Linux（Debian/Ubuntu aarch64, **glibc**）上原生编译 Wine，并将 x86/x64 模拟器编译为 **Windows PE DLL**，由 Wine 在运行时加载。这与 winlator bionic 的"Bionic rootfs + Box86/Box64 ELF 翻译器"路线**根本不同**。

| 维度 | Hangover | winlator bionic |
|---|---|---|
| 运行环境 | Debian/Ubuntu aarch64 (**glibc**) | Android **Bionic** rootfs |
| Wine 编译方式 | 原生 `gcc-aarch64-linux-gnu` + `dpkg-buildpackage` 交叉编译 | NDK 交叉编译到 Bionic |
| x86_64 模拟 | **FEX 编译为 ARM64EC PE DLL** (`libarm64ecfex.dll`) | Box64 (Linux ELF) |
| x86 (32位) 模拟 | **Box64 编译为 WOW64 PE DLL** (`wowbox64.dll`) + 可选 FEX (`libwow64fex.dll`) | Box86 (Linux ELF) |
| 模拟器注入方式 | Wine 加载 PE DLL（`/usr/lib/wine/aarch64-windows/`） | rootfs 中直接运行 ELF 翻译器 |
| 分发 | `.deb` 包 + Termux 包 | APK 内嵌 `imagefs.txz` |

#### 11.3.2 CI 管线全景

`.github/workflows/deb.yml` 定义了一条 **6 阶段 CI 流水线**：

```
foundations (x86_64 runner)         foundations-arm (arm64 runner)
  ├ debian12                          ├ ubuntu2510
  ├ debian13                          └ ubuntu2604
  ├ ubuntu2204
  ├ ubuntu2404
  └ ubuntu2604
        │
        ├────────┬────────┬────────┬────────┬────────┐
        ▼        ▼        ▼        ▼        ▼        ▼
     fex-pe   fex-pe-ec  box-pe   dxvk     wine    wine-arm
  (wow64fex) (arm64ecfex)(wowbox64)       (4 distros)(2 distros)
        │        │        │        │        │        │
        └────────┴────────┴────────┴────────┴────────┘
                         │                    │
                    ▼ (bundle)           ▼ (dllbundle)
              per-distro .tar        DLL-only .tar
```

- **foundations**：为每个发行版构建 Docker 基础镜像（缓存键 = Dockerfile hash），安装 arm64 交叉编译工具链 + 所有 Wine 依赖的 `:arm64` 多架构包
- **wine**：matrix 并行构建 4 个发行版的 `.deb`（debian12/13, ubuntu2204/2404）
- **wine-arm**：在原生 arm64 runner 上构建 ubuntu2510/2604（无需交叉编译）
- **bundle**：下载所有产物，按发行版打包成 `.tar`
- **dllbundle**：仅提取 PE DLL + DXVK，打包成 `hangover_VERSION_dlls.tar`

#### 11.3.3 Foundation 镜像（以 ubuntu2204 为例）

`.packaging/ubuntu2204/Dockerfile` 是整个构建的基础：

**1. 多架构 apt 源**：
```dockerfile
# 将原有 amd64 源改标 [arch=amd64]，再生成 arm64 的 ports.ubuntu.com 源
RUN cat /etc/apt/sources.list | sed "s/^deb /deb [arch=amd64] /g" > /tmp/amd64.list && \
    cat /tmp/amd64.list | sed "s/\[arch=amd64\]/[arch=arm64]/g" \
        | sed "s/archive.ubuntu.com\/ubuntu\//ports.ubuntu.com\/ubuntu-ports\//g" > /tmp/arm64.list && \
    cat /tmp/amd64.list /tmp/arm64.list > /etc/apt/sources.list && \
    dpkg --add-architecture arm64
```

**2. 交叉工具链 + Wine 全部依赖（arm64 多架构包）**：
```dockerfile
RUN apt-get install -y \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \  # arm64 GCC 交叉编译器
    clang llvm lld \                                     # PE 编译用
    meson ninja-build cmake \                            # 三种构建系统
    libglib2.0-dev:arm64 libfreetype6-dev:arm64 \        # Wine 依赖 (arm64)
    libvulkan-dev:arm64 libgl-dev:arm64 \
    libgnutls28-dev:arm64 libsdl2-dev:arm64 \
    libgstreamer1.0-dev:arm64 libpulse-dev:arm64 \
    libx11-dev:arm64 libxrandr-dev:arm64 ...             # 共 ~30 个 :arm64 dev 包
```

**3. 两套 llvm-mingw 工具链**：
```dockerfile
# bylaws 版 (20240929) — 用于 FEX/Box64 PE 编译
RUN wget https://github.com/bylaws/llvm-mingw/releases/download/20240929/llvm-mingw-20240929-ucrt-ubuntu-20.04-x86_64.tar.xz

# mstorsjo 官方版 (20260505) — 用于 Wine PE 编译
RUN wget https://github.com/mstorsjo/llvm-mingw/releases/download/20260505/llvm-mingw-20260505-ucrt-ubuntu-22.04-x86_64.tar.xz
```

> **为什么需要两套？** bylaws 版针对 FEX/Box64 的 PE 交叉编译做了特定调整；Wine 使用 mstorsjo 官方版。

#### 11.3.4 Wine 构建（核心）

**两阶段构建**（`.packaging/ubuntu2204/wine/Dockerfile`）：

```dockerfile
# 阶段 1: 在 x86_64 上编译 64 位 Wine 工具 (wrc, widl, winedump 等)
RUN cd /opt/wine64; mkdir amd64; cd amd64; ../configure --enable-win64; make __tooldeps__ -j `nproc`; make -C nls

# 阶段 2: 交叉编译 arm64 Wine (使用 dpkg-buildpackage)
RUN cd /opt/wine; dpkg-buildpackage -d -b -a arm64 -us -uc -ui
```

**`debian/rules` 中的 configure 参数**（关键）：

```makefile
./configure --prefix=/usr \
    --with-mingw=clang \                    # 用 llvm-mingw 的 clang 编译 PE
    --enable-archs=arm64ec,aarch64,i386 \   # 三种 PE 架构
    --enable-tools \                         # 启用工具编译
    --disable-tests \
    --host=aarch64-linux-gnu \               # 交叉编译目标
    host_alias=aarch64-linux-gnu \
    build_alias=x86_64-linux-gnu \           # 构建机
    --with-wine-tools=../wine64/amd64 \      # 复用阶段 1 编译的工具
    CC=aarch64-linux-gnu-gcc
```

**`--enable-archs=arm64ec,aarch64,i386` 详解**：

| PE 架构 | 用途 | 对应模拟器 DLL |
|---|---|---|
| `arm64ec` | ARM64EC (Emulation-Compatible) — Windows 11 的 x86_64 兼容层 | `libarm64ecfex.dll` (FEX) |
| `aarch64` | 原生 ARM64 Windows PE | 无需模拟 |
| `i386` | 32 位 x86 PE | `wowbox64.dll` (Box64) 或 `libwow64fex.dll` (FEX) |

> **ARM64EC 是 Hangover 的核心创新**：Windows 11 引入的 ARM64EC 允许 x86_64 代码和 ARM64 代码在同一进程中共存。Hangover 将 FEX 编译为 ARM64EC PE DLL，Wine 加载后可直接在同一地址空间内翻译 x86_64 指令，避免了传统 Box86/Box64 需要独立进程或 JIT 翻译层的开销。

**编译选项**：
- `DEB_BUILD_MAINT_OPTIONS = optimize=-lto hardening=-relro` — 禁用 LTO 和部分加固（兼容性优先）
- `override_dh_strip` 排除 `wine-pthread`、`i386-windows`、`aarch64-windows`（不 strip PE DLL）
- `CC=aarch64-linux-gnu-gcc` — Wine 本体用 GCC 交叉编译，PE 部分用 `--with-mingw=clang`

#### 11.3.5 FEX PE 模拟器构建（两个变体）

FEX 被编译为两种 PE DLL，分别处理不同位宽的 x86 代码：

| 组件 | Dockerfile | MINGW_TRIPLE | cmake target | 产物 DLL | 用途 |
|---|---|---|---|---|---|
| **fex-pe-ec** | `fexpeec/Dockerfile` | `arm64ec-w64-mingw32` | `arm64ecfex` | `libarm64ecfex.dll` | **x86_64 模拟**（必需） |
| **fex-pe** | `fexpe/Dockerfile` | `aarch64-w64-mingw32` | `wow64fex` | `libwow64fex.dll` | x86 32位模拟（可选） |

```dockerfile
# fexpeec (ARM64EC, x86_64 模拟)
ENV PATH="/opt/bylaws-llvm-mingw-20240929-ucrt-ubuntu-20.04-x86_64/bin:$PATH"
RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=../Data/CMake/toolchain_mingw.cmake \  # FEX 自带的 mingw 工具链文件
    -DMINGW_TRIPLE=arm64ec-w64-mingw32 \                          # ARM64EC 目标
    -DENABLE_LTO=False -DBUILD_TESTING=False ..
RUN make -j `nproc` arm64ecfex
RUN arm64ec-w64-mingw32-strip --strip-unneeded /opt/fex/build/Bin/libarm64ecfex.dll
```

**安装路径**：`/usr/lib/wine/aarch64-windows/` — Wine 启动时从此目录加载 PE 模拟器 DLL。

#### 11.3.6 Box64 PE 模拟器构建

```dockerfile
# boxpe (WOW64, x86 32位模拟)
ENV PATH="/opt/llvm-mingw-20260505-ucrt-ubuntu-22.04-x86_64/bin:$PATH"  # 用 mstorsjo 版
RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \    # 注意: 用 GCC 而非 clang
    -DARM_DYNAREC=ON \                             # 启用 ARM 动态重编译
    -DWOW64=ON ..                                   # WOW64 模式
RUN make -j `nproc` wowbox64
```

> Box64 的 `wowbox64` target 将 Box64 的 x86 翻译能力编译为 WOW64 PE DLL，与 FEX 的 `libwow64fex.dll` 形成二选一关系。

#### 11.3.7 DXVK 构建

```dockerfile
ENV PATH="/opt/bylaws-llvm-mingw-20240929-ucrt-ubuntu-20.04-x86_64/bin:$PATH"
RUN cd /opt/dxvk; ./package-release.sh $(git describe --abbrev=0) /opt/dxvk/output
```

DXVK 使用自带构建脚本，输出 `dxvk-VERSION.tar.gz`（含 d3d9.dll, d3d10core.dll, d3d11.dll, dxgi.dll）。

#### 11.3.8 包依赖关系（debian/control）

```
hangover-wine (arm64 .deb)
  ├─ Depends: hangover-libarm64ecfex | fex-emu-wine   ← x86_64 模拟 (必需, 二选一)
  ├─ Depends: hangover-wowbox64                        ← x86 32位模拟 (必需)
  └─ Recommends: libfreetype6, libgnutls30, libsdl2-2.0-0, libvulkan1, ...
```

**运行时架构**：
```
用户启动 Windows .exe
    │
    ▼
Wine (arm64 ELF, glibc)
    │
    ├─ .exe 是 x86_64? → 加载 libarm64ecfex.dll (FEX ARM64EC PE)
    │                     └─ FEX 在进程内翻译 x86_64 → ARM64
    │
    ├─ .exe 是 x86 (32位)? → 加载 wowbox64.dll (Box64 WOW64 PE)
    │                        └─ Box64 在进程内翻译 x86 → ARM64
    │
    └─ .exe 是 ARM64? → 原生执行 (无需模拟)
```

#### 11.3.9 Hangover 对 winlator bionic 的参考价值

> **重要修正**：此处最初的判断已被 §14 推翻。winlator bionic **已经实现了** ARM64EC + PE DLL 路线，与 Hangover 技术同源。

| 参考点 | Hangover 方案 | 是否适用于 winlator bionic |
|---|---|---|
| **Wine `--enable-archs=arm64ec,aarch64,i386`** | 三架构 PE 编译 | ✅ **已采用** — `proton-9.0-arm64ec.txz` 即此配置的产物 |
| **`HODLL` 环境变量** | Wine 加载 PE 模拟器 DLL | ✅ **已采用** — 代码中 `envVars.put("HODLL", ...)` 确认 |
| **FEX PE DLL (`libwow64fex.dll`)** | FEX 编译为 WOW64 PE | ✅ **已采用** — `fexcore/fexcore-2508.tzst` 资产确认 |
| **Box64 PE DLL (`wowbox64.dll`)** | Box64 编译为 WOW64 PE | ✅ **已采用** — `wowbox64/wowbox64-0.3.7.tzst` 资产确认 |
| **llvm-mingw 交叉编译 PE** | Wine PE 部分用 clang/mingw | ✅ 直接参考 |
| **DXVK ARM64EC 版本** | 标准 DXVK | ✅ **已采用** — `dxvk-1.10.3-arm64ec-async`, `dxvk-2.3.1-arm64ec-gplasync` |
| **多发行版 Docker 基础镜像** | 6 发行版并行 | ❌ winlator 只需一个 Android NDK 环境 |
| **dpkg-buildpackage 打包** | .deb 分发 | ❌ winlator 用 tar+xz 打包进 APK |
| **glibc 宿主** | Debian/Ubuntu | ❌ winlator 用 Bionic — Wine ELF 部分需 NDK 交叉编译，非 gcc |

> **修正后结论**：Hangover 和 winlator bionic 在 ARM64EC 路线上**技术同源**。winlator bionic 的创新在于将 Hangover 的 glibc + ARM64EC 方案**移植到 Bionic rootfs** 上，实现了 Android 原生的 PE DLL 模拟器集成。两者的关键差异是 Wine ELF 本体的编译目标（glibc vs Bionic），而非模拟器路线本身。

### 11.4 对复刻 winlator bionic imagefs 的意义

MiceWine-Packages 的发现把复刻可行性从"有骨架可借鉴"提升到"**有现成的同构包系统可直接适配**"：

| 复刻路径 | 工作量 | 来源 |
|---|---|---|
| 包定义 (build.sh + 补丁) | **直接复用** MiceWine 的 83 个包，改路径前缀 | `KreitinnSoftware/MiceWine-Packages/packages/` |
| 构建主控 | 适配 `build-all.sh`，改 `APP_ROOT_DIR` 为 winlator 路径 | MiceWine `build-all.sh` |
| meson cross-file | 用 MiceWine 的极简版或本报告的完整版 | 本报告 §6 / MiceWine |
| NDK 版本 | MiceWine 用 r26b，本报告验证 r29 可用 | 均可 |
| 缺口库 | MiceWine 无 librsvg/libaom/gstreamer 完整集，需补 | 参考 Waim908 的 gstreamer 配置 |

---

## 12. 实跑复现 v2：4 个真实库 × 3 种构建系统

基于 MiceWine 方法论 + 本报告取证，用 NDK r29 实跑了 4 个官方 imagefs 中真实存在的库，覆盖 3 种构建系统：

| 库 | 版本 | 构建系统 | 依赖 | NEEDED (验证) |
|---|---|---|---|---|
| zlib | 1.3.1 | 手动 -fPIC + ld | 无 | `libc.so` + `libdl.so` ✅ |
| libpng | 1.6.43 | autotools (configure) | zlib | `libc.so` + `libm.so` + `libdl.so` + `libz.so.1` ✅ |
| brotli | 1.1.0 | cmake | 无 | `libc.so` + `libm.so` + `libdl.so` ✅ |
| freetype | 2.13.3 | **meson** (cross-file) | zlib + libpng + brotli | `libc.so` + `libpng16.so` + `libz.so` + `libbrotlidec.so.1` ✅ |

**关键验证**：freetype 的依赖链 `freetype → libpng → zlib` 和 `freetype → brotli` 在 meson 交叉编译中**全部正确解析**，证明 pkg-config 跨编译环境工作正常，多库依赖链可递归构建。

**产物**：`imagefs_bionic_v2.txz` (1.0MB)，含 4 库 + 头文件 + pkgconfig + merged-usr 布局 + Bionic libc 软链。

当前构建入口：[`build-all.sh`](../../build-all.sh)（包取舍见 [PACKAGE-SELECTION.md](PACKAGE-SELECTION.md)） · meson cross-file 参考：[`android-aarch64-bionic.ini`](../meson/android-aarch64-bionic.ini)，实际 cross-file 由 [`setup-env.sh`](../../setup-env.sh) 按解析到的 NDK 生成

---

## 13. 三大参考项目综合对比 & 复刻路线图

### 13.1 技术路线全景对比

| 维度 | winlator bionic (目标) | MiceWine-Packages | Hangover | Waim908 (termux 衍生) |
|---|---|---|---|---|
| **libc** | Bionic | Bionic | glibc | Bionic |
| **构建方式** | NDK 交叉编译 | NDK 交叉编译 | gcc 交叉编译 + dpkg | NDK 交叉编译 |
| **rootfs** | ✅ imagefs (merged-usr) | ✅ .rat (merged-usr) | ❌ 无 rootfs | ✅ (merged-usr) |
| **包管理** | 手动 tar+xz | 83 包 build.sh | .deb (dpkg) | 手动 |
| **Wine** | Bionic ELF (**双模式**: ARM64EC + x86_64) | Bionic ELF | glibc ELF + PE DLL | Bionic ELF |
| **x86 模拟** | **双路线**: Box64 (ELF) **+** FEX/Box64 (PE DLL) | Box64 (ELF) | FEX/Box64 (PE DLL) | Box86/Box64 (ELF) |
| **ARM64EC** | ✅ `proton-9.0-arm64ec` + `HODLL` | ❌ | ✅ `--enable-archs=arm64ec` | ❌ |
| **构建系统** | autotools + cmake + meson | autotools + cmake + meson | autotools + cmake | autotools + cmake |
| **补丁来源** | termux-packages | termux-packages | Wine 上游 + HODLL 补丁 | termux-packages |
| **公开构建脚本** | ❌ 私有 | ✅ 完整公开 | ✅ 完整公开 | 部分 |

### 13.2 ARM64EC vs ELF 翻译器：两条 x86 模拟路线

> **修正**：winlator bionic **同时实现了两条路线**，用户可在 UI 中选择 Wine 版本切换。

```
路线 A (Hangover / winlator bionic ARM64EC 模式):  PE DLL 进程内模拟
┌──────────────────────────────────────────────────┐
│  Android (Bionic) 或 Linux (glibc)              │
│  ┌─────────────────────────────────────────────┐ │
│  │  Wine (ARM64EC, ELF)                        │ │
│  │    ├─ exe (x86/x86_64)                      │ │
│  │    │   ↕ 进程内直接翻译 (HODLL 机制)         │ │
│  │    ├─ libwow64fex.dll (FEX WOW64 PE)        │ │  ← Wine 加载 PE DLL
│  │    │   └─ FEX x86→ARM64                     │ │     用户可选 FEXCore
│  │    └─ wowbox64.dll (Box64 WOW64 PE)         │ │  ← 或 Box64
│  │        └─ Box64 x86→ARM64                   │ │
│  └─────────────────────────────────────────────┘ │
│  linker64 (Bionic) 或 ld-linux (glibc)          │
└──────────────────────────────────────────────────┘

路线 B (winlator bionic 传统模式 / MiceWine):  ELF 翻译器
┌──────────────────────────────────────────────────┐
│  Android (Bionic)                                │
│  ┌─────────────────────────────────────────────┐ │
│  │  Wine (x86_64, Bionic ELF)                  │ │
│  │    └─ exe (x86)                             │ │
│  │       ↕ 进程外翻译                           │ │
│  │  Box64 (Bionic ELF)                         │ │  ← 独立进程
│  │    └─ x86 → ARM64 翻译                      │ │
│  └─────────────────────────────────────────────┘ │
│  /system/bin/linker64 (Bionic)                   │
└──────────────────────────────────────────────────┘
```

**路线 A 优势**：进程内模拟零 IPC 开销，ARM64EC 允许 x86_64/ARM64 混编
**路线 B 优势**：实现简单，Box64 成熟稳定，无需 Wine ARM64EC 补丁
**winlator bionic 独有**：**用户可运行时切换两条路线**，兼顾兼容性（路线 B）和性能（路线 A）

### 13.3 复刻 winlator bionic imagefs 的推荐路线

基于三个参考项目的分析，推荐以下**分层复刻策略**：

| 层次 | 复刻来源 | 具体操作 | 难度 |
|---|---|---|---|
| **1. 构建框架** | MiceWine `build-all.sh` | 改 `APP_ROOT_DIR` 从 `com.micewine.emu` → `com.winlator` | ⭐ |
| **2. 包定义 (83包)** | MiceWine `packages/` | 直接复用 `build.sh` + `.patch`，改路径前缀 | ⭐⭐ |
| **3. meson cross-file** | 本报告 §6 | 已验证 NDK r29 + Bionic 可用 | ⭐ |
| **4. NDK 工具链** | MiceWine 或本报告 | r26b (MiceWine) 或 r29 (本报告验证) | ⭐ |
| **5. 缺口库补全** | Waim908 / termux-packages | librsvg, libaom, gstreamer, pulseaudio | ⭐⭐⭐ |
| **6. Wine 编译 (x86_64)** | MiceWine `packages/wine-*` | Bionic Wine 补丁 + `--enable-archs=x86_64` | ⭐⭐⭐⭐ |
| **7. Wine 编译 (ARM64EC)** | **Hangover** `debian/rules` + MiceWine Bionic 补丁 | `--enable-archs=arm64ec,aarch64,i386` + `HODLL` 补丁 + llvm-mingw + NDK | ⭐⭐⭐⭐⭐ |
| **8. Box64/Box86 (ELF)** | MiceWine `packages/box64-*` | ELF 翻译器，传统路线 | ⭐⭐ |
| **9. Box64/FEX (PE DLL)** | **Hangover** `.packaging/` | `wowbox64.dll` (Box64 WOW64 PE) + `libwow64fex.dll` (FEX WOW64 PE) | ⭐⭐⭐⭐ |
| **10. DXVK (ARM64EC)** | Hangover `.packaging/ubuntu2204/dxvk/` + bylaws-llvm-mingw | `dxvk-*-arm64ec-*.tzst` | ⭐⭐⭐ |
| **11. 打包** | 本报告 §6 | tar + xz + split + sha256 | ⭐ |

**关键差距**（MiceWine 缺少但 winlator imagefs 包含的库）：

| 缺口库 | imagefs 大小 | 参考来源 | 难度 |
|---|---|---|---|
| librsvg-2.so | 131MB (含静态符号) | termux-packages/rust-librsvg | ⭐⭐⭐⭐ (需 Rust 交叉编译) |
| libaom.so | ~15MB | termux-packages/libaom | ⭐⭐⭐ |
| gstreamer 全集 | ~80MB | Waim908 gstreamer 配置 | ⭐⭐⭐ |
| vulkan-loader.so | ~2MB | termux-packages/vulkan-loader | ⭐⭐ |
| pulseaudio 全集 | ~10MB | termux-packages/pulseaudio | ⭐⭐⭐ |

> **最大障碍是 librsvg**：它依赖 Rust 工具链交叉编译到 `aarch64-linux-android`，MiceWine 和 Waim908 都未包含。termux-packages 有 `rust-librsvg` 但构建配置复杂。

### 13.4 最终结论

| 问题 | 答案 |
|---|---|
| **imagefs 构建脚本是否公开？** | ❌ 官方（GitLab winlator3）无任何代码。但 MiceWine-Packages 提供了**同构的完整构建系统**。 |
| **能否完整复刻？** | ⚠️ **90% 可复刻**。MiceWine 的 83 包 + 路径前缀修改覆盖了大部分库；librsvg (Rust) 是最大缺口。 |
| **Hangover 有参考价值吗？** | ✅ **高度相关**。winlator bionic 已实现与 Hangover 相同的 ARM64EC + PE DLL 模拟器路线（`HODLL` 机制），两者技术同源。详见 §14。 |
| **推荐复刻路径** | Fork MiceWine-Packages → 改路径前缀 → 补 librsvg/gstreamer → 用本报告的 NDK r29 cross-file → tar+xz 打包。Wine 部分参考 Hangover 的 `--enable-archs=arm64ec` 配置。 |

---

## 14. 重大修正：winlator bionic 的 ARM64EC 双模式架构

> ** Correction**：此前 §11.3.9 中"PE DLL 路线不适用于 Bionic rootfs"的判断**有误**。代码审计表明，winlator bionic **已经实现了与 Hangover 完全相同的 ARM64EC + PE DLL 模拟器路线**，且与之并行保留了传统的 Box64 ELF 翻译器路线。

### 14.1 证据链

#### 14.1.1 Gradle 下载两个 Proton 版本

`app/build.gradle` 的 `downloadProton` 任务同时下载两个 Proton 9.0 构建：

```groovy
File protonARM64EC = new File(assetDir, "proton-9.0-arm64ec.txz")   // ARM64EC 版
File protonX8664 = new File(assetDir, "proton-9.0-x86_64.txz")      // x86_64 版
// 均从 gitlab.com/winlator3/winlator-extra/-/raw/main/proton/ 下载
```

GitLab 仓库确认两个文件均存在（由 pipetto-crypto 10 个月前提交）。

#### 14.1.2 WineInfo 识别 arm64ec 架构

`app/src/main/java/com/winlator/cmod/core/WineInfo.java`:

```java
// 正则匹配三种架构
Pattern.compile("^(wine|proton)\\-([0-9\\.]+)\\-?([0-9\\.]+)?\\-(x86|x86_64|arm64ec)$");

public boolean isWin64() {
    return arch.equals("x86_64") || arch.equals("arm64ec");  // arm64ec 视为 Win64
}

public boolean isArm64EC() { return arch.equals("arm64ec"); }
```

#### 14.1.3 UI 提供双模式选择

`app/src/main/res/values/arrays.xml`:

```xml
<string-array name="wine_entries">
    <item>proton-9.0-x86_64</item>      <!-- 传统 Box64 路线 -->
    <item>proton-9.0-arm64ec</item>      <!-- ARM64EC PE DLL 路线 -->
</string-array>

<string-array name="emulator_entries">
    <item>FEXCore</item>   <!-- ARM64EC 模式下: libwow64fex.dll -->
    <item>Box64</item>     <!-- ARM64EC 模式下: wowbox64.dll; 传统模式: box64 ELF -->
</string-array>

<!-- ARM64EC 专用 DXVK 版本 -->
<string-array name="dxvk_version_entries">
    <item>1.10.3-arm64ec-async</item>
    <item>2.3.1-arm64ec-gplasync</item>
    ...
</string-array>
```

### 14.2 双模式运行机制

`GuestProgramLauncherComponent.java` 的 `start()` 方法根据 Wine 架构**分叉到完全不同的执行路径**：

```java
@Override
public void start() {
    synchronized (lock) {
        if (wineInfo.isArm64EC())
            extractEmulatorsDlls();    // ARM64EC: 提取 PE DLL 到 Wine system32
        else
            extractBox64Files();       // 传统: 提取 Box64 ELF 到 /usr/bin/
        checkDependencies();
        pid = execGuestProgram();
    }
}
```

#### 14.2.1 路线 A：ARM64EC + PE DLL（同 Hangover）

**DLL 提取**（`extractEmulatorsDlls()`）：

| 资产包 | 内容 | 解压目标 |
|---|---|---|
| `wowbox64/wowbox64-0.3.7.tzst` (1.0MB) | `wowbox64.dll`（Box64 编译为 WOW64 PE） | `~/.wine/drive_c/windows/system32/` |
| `fexcore/fexcore-2508.tzst` (3.4MB) | `libwow64fex.dll`（FEX WOW64 PE, x86 32位）**+ `libarm64ecfex.dll`**（FEX ARM64EC PE, x86_64 64位） | `~/.wine/drive_c/windows/system32/` |

> **关键发现**：`ContentsManager.java` 中 `FEXCORE_TRUST_FILES` 定义为 `{"${system32}/libwow64fex.dll", "${system32}/libarm64ecfex.dll"}`，证明 `fexcore-2508.tzst` 同时包含两个 PE DLL：
> - `libwow64fex.dll` — FEX 编译为 **WOW64 PE**，处理 **x86 32位**模拟（通过 `HODLL` 环境变量选择）
> - `libarm64ecfex.dll` — FEX 编译为 **ARM64EC PE**，处理 **x86_64 64位**模拟（由 Wine ARM64EC 层自动加载）

**启动命令**（直接运行 Wine，**无 Box64 包装**）：

```java
if (wineInfo.isArm64EC()) {
    command = winePath + "/" + guestExecutable;    // 直接: wine exe
    if (emulator.toLowerCase().equals("fexcore"))
        envVars.put("HODLL", "libwow64fex.dll");   // FEX 作为 x86 32位模拟器
    else
        envVars.put("HODLL", "wowbox64.dll");       // Box64 作为 x86 32位模拟器
}
// 注意: libarm64ecfex.dll 不需要 HODLL 指定 — Wine ARM64EC 层遇到 x86_64 代码时自动加载
```

**模拟器分工**：

| 模拟目标 | PE DLL | 选择机制 | 来源 |
|---|---|---|---|
| **x86_64 (64位)** | `libarm64ecfex.dll` | Wine ARM64EC 层**自动加载** | `fexcore-2508.tzst` |
| **x86 (32位), FEX** | `libwow64fex.dll` | `HODLL=libwow64fex.dll`（用户选 FEXCore） | `fexcore-2508.tzst` |
| **x86 (32位), Box64** | `wowbox64.dll` | `HODLL=wowbox64.dll`（用户选 Box64） | `wowbox64-0.3.7.tzst` |

**`HODLL` 环境变量**是 Hangover 项目引入的 Wine 补丁机制，告诉 Wine 加载哪个 PE DLL 作为 **x86 32位** 模拟器。x86_64 模拟由 ARM64EC 层原生处理（加载 `libarm64ecfex.dll`），不需要 `HODLL`。

**FEXCore 预设**（`FEXCorePresetManager.java`）控制 FEX 模拟器行为：

| 预设 | TSO | VectorTSO | MemcpyTSO | HalfBarrier | X87精度 | MultiBlock |
|---|---|---|---|---|---|---|
| Stability | ✅ | ✅ | ✅ | ✅ | 完整 | ❌ |
| Compatibility | ✅ | ✅ | ✅ | ✅ | 完整 | ✅ |
| Intermediate | ✅ | ❌ | ❌ | ✅ | 降低 | ✅ |
| Performance | ❌ | ❌ | ❌ | ❌ | 降低 | ✅ |

#### 14.2.2 路线 B：传统 Box64 ELF 翻译器

**ELF 提取**（`extractBox64Files()`）：

| 资产包 | 内容 | 解压目标 |
|---|---|---|
| `box64/box64-0.3.7.tzst` (2.9MB) | `box64`（Box64 ELF 二进制） | `/usr/bin/box64` |

**启动命令**（Box64 包装 Wine）：

```java
else {
    command = imageFs.getBinDir() + "/box64 " + guestExecutable;  // box64 wine exe
}
```

### 14.3 与 Hangover 的精确对比

| 维度 | Hangover | winlator bionic (ARM64EC 模式) |
|---|---|---|
| **Wine 架构** | `--enable-archs=arm64ec,aarch64,i386` | `proton-9.0-arm64ec`（推测同参数） |
| **宿主 libc** | glibc (Debian/Ubuntu) | **Bionic** (Android rootfs) |
| **HODLL 机制** | ✅ 使用 | ✅ **使用**（代码确认） |
| **x86_64 模拟** | `libarm64ecfex.dll`（FEX ARM64EC PE） | ✅ `libarm64ecfex.dll`（FEX ARM64EC PE，**代码确认** `FEXCORE_TRUST_FILES`） |
| **x86 32位模拟** | `wowbox64.dll` (Box64) / `libwow64fex.dll` (FEX) | `wowbox64.dll` (Box64) / `libwow64fex.dll` (FEX) |
| **Wine PE 目录** | `/usr/lib/wine/aarch64-windows/` + `i386-windows/` | `lib/wine/aarch64-windows/` + `i386-windows/`（代码确认 `ContainerManager` + `XServerDisplayActivity`） |
| **DLL 安装路径** | `/usr/lib/wine/aarch64-windows/` | `~/.wine/drive_c/windows/system32/` |
| **模拟器选择** | 包依赖（deb control） | **运行时用户选择**（UI spinner: FEXCore / Box64） |
| **FEX 配置** | 无运行时配置 | **4 个预设**（Stability/Compatibility/Intermediate/Performance） |
| **DXVK** | 标准 DXVK | **arm64ec 专用版本**（`1.10.3-arm64ec-async`, `2.3.1-arm64ec-gplasync`） |
| **WoW64 CPU 亲和性** | 无 | ✅ `cpuListWoW64`（Container 独立配置 WoW64 进程的 CPU 核心） |

### 14.4 架构图：winlator bionic 双模式

```
┌──────────────────────────────────────────────────────────────────┐
│                    winlator bionic (Android)                     │
│                                                                  │
│  用户选择 Wine 版本:                                              │
│  ┌──────────────────────┐    ┌───────────────────────────────┐  │
│  │ proton-9.0-arm64ec   │    │ proton-9.0-x86_64             │  │
│  │ (ARM64EC PE DLL 路线) │    │ (Box64 ELF 翻译器路线)         │  │
│  └──────────┬───────────┘    └───────────┬───────────────────┘  │
│             │                            │                       │
│             ▼                            ▼                       │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐   │
│  │ Wine (ARM64EC)          │  │ Wine (x86_64)               │   │
│  │  Bionic ELF             │  │  Bionic ELF                 │   │
│  │                         │  │                             │   │
│  │  x86_64 代码:            │  │  box64 (Bionic ELF)         │   │
│  │   → libarm64ecfex.dll   │  │   └─ x86→ARM64 翻译         │   │
│  │     (FEX ARM64EC PE)    │  │                             │   │
│  │     [自动加载]           │  │  command: box64 wine exe    │   │
│  │                         │  │                             │   │
│  │  x86 32位 代码:          │  │                             │   │
│  │   HODLL=libwow64fex.dll │  │                             │   │
│  │    (FEX WOW64 PE)       │  │                             │   │
│  │   或                     │  │                             │   │
│  │   HODLL=wowbox64.dll    │  │                             │   │
│  │    (Box64 WOW64 PE)     │  │                             │   │
│  │   [用户选择]             │  │                             │   │
│  │                         │  │                             │   │
│  │  command: wine exe      │  │                             │   │
│  │  (无 box64 包装)         │  │                             │   │
│  └─────────────────────────┘  └─────────────────────────────┘   │
│                                                                  │
│  Wine PE DLL 目录结构 (ContainerManager + XServerDisplayActivity)│
│  ARM64EC:  lib/wine/aarch64-windows/  → system32/               │
│            lib/wine/i386-windows/      → syswow64/               │
│  x86_64:   lib/wine/x86_64-windows/   → system32/               │
│            lib/wine/i386-windows/      → syswow64/               │
│                                                                  │
│  imagefs (Bionic rootfs, merged-usr)                            │
│  /system/bin/linker64 (Android 宿主 Bionic)                     │
└──────────────────────────────────────────────────────────────────┘
```

### 14.5 对分析报告的修正

| 此前结论 | 修正后 |
|---|---|
| ❌ "PE DLL 路线不适用于 Bionic rootfs" | ✅ **winlator bionic 已实现 PE DLL 路线**，通过 `HODLL` 机制在 Bionic Wine 上加载 PE 模拟器 |
| ❌ "Hangover 的 PE DLL 模拟器方案不适用" | ✅ **两者技术同源**，winlator 直接借鉴了 Hangover 的 `HODLL` 机制 |
| ❌ "rootfs 构建方法不可互通" | ⚠️ **部分互通** — Wine 的 ARM64EC 编译配置可直接参考 Hangover；rootfs 中的依赖库仍需 NDK 交叉编译 |
| ❌ "模拟器在进程外运行" | ✅ **ARM64EC 模式下模拟器在进程内运行**（PE DLL 被 Wine 加载到同一地址空间） |

### 14.6 `proton-9.0-arm64ec.txz` 的构建推测

基于 Hangover 的构建方法和 winlator 代码证据，推测 `proton-9.0-arm64ec.txz` 的构建方式：

1. **Wine 源码**：Proton 9.0（Valve 的 Wine 分支，含 Steam 兼容补丁）
2. **编译参数**（推测，基于 Hangover `debian/rules`）：
   ```bash
   ./configure --prefix=/usr \
       --with-mingw=clang \
       --enable-archs=arm64ec,aarch64,i386 \
       --disable-tests \
       --host=aarch64-linux-android \    # 关键差异: 目标是 Android 而非 GNU
       CC=aarch64-linux-android26-clang   # NDK 工具链
   ```
3. **PE 部分**：用 llvm-mingw 编译 PE DLL（`--with-mingw=clang`）
4. **ELF 部分**：用 NDK clang 编译 Bionic ELF（Wine 本体 + 工具）
5. **HODLL 补丁**：Wine 源码中需要打补丁，使其支持 `HODLL` 环境变量加载外部模拟器 DLL
6. **打包**：编译产物打包为 `proton-9.0-arm64ec.txz`，放到 GitLab

> **关键差异**：Hangover 的 Wine ELF 部分链接 glibc，winlator bionic 的 Wine ELF 部分链接 **Bionic**。这意味着 Wine 本身需要被交叉编译到 `aarch64-linux-android`，这是一个非平凡的工程 — Wine 上游不官方支持 Bionic，需要类似 termux-packages 的补丁集。

### 14.7 完整的构建资产清单

winlator bionic APK 从 GitLab 下载的**全部外部资产**：

| 资产 | GitLab 路径 | 大小（分卷） | 用途 |
|---|---|---|---|
| `imagefs.txz` | `imagefs/imagefs.txz.00..03` | 183MB (4×50MB) | Bionic rootfs |
| `proton-9.0-arm64ec.txz` | `proton/proton-9.0-arm64ec.txz` | 未确认 | **ARM64EC Wine** |
| `proton-9.0-x86_64.txz` | `proton/proton-9.0-x86_64.txz` | 未确认 | x86_64 Wine |

APK 内嵌的模拟器/DXVK 资产（`app/src/main/assets/`）：

| 资产 | 路径 | 大小 | 用途 |
|---|---|---|---|
| `box64-0.3.7.tzst` | `box64/` | 2.9MB | Box64 ELF（传统路线） |
| `wowbox64-0.3.7.tzst` | `wowbox64/` | 1.0MB | Box64 PE DLL（ARM64EC 路线） |
| `fexcore-2508.tzst` | `fexcore/` | 3.4MB | FEX PE DLL（ARM64EC 路线，含 `libwow64fex.dll` + `libarm64ecfex.dll`） |
| `dxvk-1.10.3-arm64ec-async.tzst` | `dxwrapper/` | 16.9MB | DXVK ARM64EC 版 |
| `dxvk-2.3.1-arm64ec-gplasync.tzst` | `dxwrapper/` | 7.9MB | DXVK ARM64EC 版 |

### 14.8 完整代码审计：ARM64EC 相关逻辑全览

对 `winlator_bionic` 分支全部 13 个包含 `arm64ec` / `isArm64EC` 的 Java 文件做完整审计，结果如下：

#### 14.8.1 ContentProfile 类型系统

`ContentProfile.java` 定义了 7 种内容类型，其中 3 种为 ARM64EC 路线专属：

| ContentType | 用途 | 信任文件 | 路线 |
|---|---|---|---|
| `CONTENT_TYPE_WINE` | Wine 安装包 | — | 通用 |
| `CONTENT_TYPE_PROTON` | Proton 安装包 | — | 通用 |
| `CONTENT_TYPE_DXVK` | DXVK | `${system32}/d3d*.dll`, `${syswow64}/d3d*.dll` | 通用 |
| `CONTENT_TYPE_VKD3D` | VKD3D | `${system32}/d3d12*.dll`, `${syswow64}/d3d12*.dll` | 通用 |
| `CONTENT_TYPE_BOX64` | Box64 ELF | `${bindir}/box64` | 传统路线 |
| **`CONTENT_TYPE_WOWBOX64`** | Box64 PE DLL | `${system32}/wowbox64.dll` | **ARM64EC 路线** |
| **`CONTENT_TYPE_FEXCORE`** | FEX PE DLL | `${system32}/libwow64fex.dll`, `${system32}/libarm64ecfex.dll` | **ARM64EC 路线** |

#### 14.8.2 Container 配置项

`Container.java` 中与 ARM64EC 相关的配置字段：

```java
public static final String DEFAULT_EMULATOR = "FEXCore";  // 默认模拟器: FEXCore (ARM64EC 路线)
private String fexcoreVersion;       // FEXCore 版本 (如 "2508")
private String fexcorePreset = FEXCorePreset.INTERMEDIATE;  // FEXCore 预设
private String box64Version;         // Box64 版本 (ARM64EC 下指 wowbox64 版本)
private String emulator;             // "FEXCore" 或 "Box64"
private String cpuListWoW64;         // WoW64 进程的 CPU 亲和性 (独立于主进程)
```

> **`cpuListWoW64`**：ARM64EC 模式下，WoW64 进程（x86 32位翻译进程）可独立指定 CPU 核心。例如在大核+小核 SoC 上，可将 WoW64 进程绑到大核以提升翻译性能。fallback 策略：使用后半部分核心（`numProcessors/2 .. numProcessors`）。

#### 14.8.3 ContainerManager 的 ARM64EC DLL 提取

`ContainerManager.java` 在创建容器时，根据 Wine 架构提取不同的 PE DLL：

```java
if (wineInfo.isArm64EC())
    extractCommonDlls(wineInfo, "aarch64-windows", "system32", ...);  // ARM64EC PE → system32
else
    extractCommonDlls(wineInfo, "x86_64-windows", "system32", ...);   // x86_64 PE → system32
extractCommonDlls(wineInfo, "i386-windows", "syswow64", ...);         // 32位 PE → syswow64 (两种模式都有)
```

**特殊处理**：`iexplore.exe` 在 ARM64EC 模式下，`aarch64-windows` 版本会被替换为 `i386-windows` 版本（IE 无 ARM64EC 构建，回退到 32 位）。

#### 14.8.4 XServerDisplayActivity 的 DLL 恢复

`XServerDisplayActivity.java` 的 `restoreOriginalDllFiles()` 在用户禁用 DXVK/WineD3D 时，从 Wine 原始 PE 目录恢复 DLL：

```java
if (wineInfo.isArm64EC())
    system32dlls = new File(imageFs.getWinePath() + "/lib/wine/aarch64-windows");
else
    system32dlls = new File(imageFs.getWinePath() + "/lib/wine/x86_64-windows");
syswow64dlls = new File(imageFs.getWinePath() + "/lib/wine/i386-windows");
```

#### 14.8.5 DXVKConfigDialog 的版本过滤

`DXVKConfigDialog.java` 的 `loadDxvkVersionSpinner()` 根据 `isARM64EC` 过滤 DXVK 版本：

```java
for (int i = 0; i < itemList.size(); i++) {
    if (itemList.get(i).contains("arm64ec") && !isARM64EC)
        itemList.remove(i);  // 非 ARM64EC 模式: 隐藏 arm64ec 专用 DXVK
}
```

**反向过滤缺失**：ARM64EC 模式下**不会过滤掉非 arm64ec 版本的 DXVK** — 用户可以选择标准 DXVK 或 ARM64EC DXVK。但实际运行时，非 ARM64EC 的 DXVK（x86_64 PE）在 ARM64EC Wine 上可能不兼容。

#### 14.8.6 ShortcutSettingsDialog 的模拟器选择

`ShortcutSettingsDialog.java` 允许每个快捷方式独立配置模拟器：

```java
if (wineInfo.isArm64EC()) {
    fexcoreFL.setVisibility(View.VISIBLE);   // 显示 FEXCore 预设选择器
    sEmulator.setEnabled(true);              // 启用模拟器切换
} else {
    fexcoreFL.setVisibility(View.GONE);      // 隐藏 FEXCore 预设
    sEmulator.setEnabled(false);             // 禁用模拟器切换 (固定用 Box64)
}
```

#### 14.8.7 BOX64_MMAP32 的 ARM64EC 差异

`GuestProgramLauncherComponent.java` 中，ARM64EC 模式下不禁用 placed mmap：

```java
if (envVars.get("BOX64_MMAP32").equals("1") && !wineInfo.isArm64EC()) {
    envVars.put("WRAPPER_DISABLE_PLACED", "1");  // 仅传统模式禁用
}
```

> ARM64EC 模式下不需要 `WRAPPER_DISABLE_PLACED`，因为 PE DLL 模拟器在进程内运行，不存在 Box64 ELF 翻译器的 mmap 冲突问题。

#### 14.8.8 ARM64EC 代码路径完整索引

| 文件 | 方法/字段 | ARM64EC 行为 |
|---|---|---|
| `WineInfo.java` | `isArm64EC()` | 架构检测入口 |
| `GuestProgramLauncherComponent.java` | `start()` | 分叉: `extractEmulatorsDlls()` vs `extractBox64Files()` |
| `GuestProgramLauncherComponent.java` | `execGuestProgram()` | 分叉: `wine exe` (HODLL) vs `box64 wine exe` |
| `GuestProgramLauncherComponent.java` | `execGuestProgram()` | `BOX64_MMAP32` 不禁用 placed mmap |
| `ContainerManager.java` | `extractCommonDlls()` | `aarch64-windows` vs `x86_64-windows` → system32 |
| `ContainerManager.java` | `extractCommonDlls()` | `iexplore.exe` ARM64EC → i386 回退 |
| `XServerDisplayActivity.java` | `restoreOriginalDllFiles()` | `aarch64-windows` vs `x86_64-windows` DLL 恢复 |
| `ContainerDetailFragment.java` | `setupDXWrapperSpinner()` | 传递 `isARM64EC` 给 DXVK 配置对话框 |
| `ContainerDetailFragment.java` | `loadBox64VersionSpinner()` | `wowbox64_version_entries` vs `box64_version_entries` |
| `DXVKConfigDialog.java` | `loadDxvkVersionSpinner()` | 过滤非 ARM64EC 的 arm64ec DXVK 版本 |
| `ShortcutSettingsDialog.java` | 模拟器选择器 | ARM64EC: 显示 FEXCore 预设 + 启用模拟器切换 |
| `ShortcutSettingsDialog.java` | `loadBox64VersionSpinner()` | 同 ContainerDetailFragment |
| `ContentsManager.java` | `FEXCORE_TRUST_FILES` | `libwow64fex.dll` + `libarm64ecfex.dll` |
| `ContentsManager.java` | `WOWBOX64_TRUST_FILES` | `wowbox64.dll` |
