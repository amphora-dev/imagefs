# 与 MiceWine-Packages 的对照

对照对象：[`KreitinnSoftware/MiceWine-Packages`](https://github.com/KreitinnSoftware/MiceWine-Packages)
（另参考 `AndreRH/hangover`）。两个项目都把上游库交叉编译到 Bionic，所以它们的版本选择、
Bionic 补丁技巧和链接 flag 值得借鉴——但目标不同，不能照搬。

> 这份文档只保留仍然成立的对照结论。早期那份「29/42 包失败」的根因分析已随
> libx11/pulseaudio/libglvnd 三条线全部收敛而删除：libx11 现在通过 `depends.conf`
> 拿到 `android-sysvshm`，pulseaudio 栈与 libglvnd 已整包移除（依据见
> [PACKAGE-SELECTION.md](PACKAGE-SELECTION.md)）。

## 目标差异

| | 本项目 (imagefs) | MiceWine-Packages |
|---|---|---|
| 运行环境 | winlator imagefs rootfs，`/usr` | Android 真机 `/data/data/com.micewine.emu/files/usr` |
| 运行方式 | box64 模拟 Linux，跑 x86 Windows 程序 | Android 上原生运行 |
| C 运行时 | Bionic（`/system/bin/linker64`） | Bionic |
| X11 / audio 语义 | **Linux 语义**（unix socket `/usr/tmp/.X11-unix`） | **Android 语义**（AAudio、ANativeWindow） |
| 目标 | 复刻官方 bionic imagefs 的 ABI | 自有运行时 |

因此 MiceWine 的 `__ANDROID__` EGL/AAudio patch 与硬编码 `/data/data/...` 路径对我们是
有害的：我们要的恰恰是被那些 patch 关掉的 Linux 分支。

## 我们采纳的做法

- **libX11 需要 System V 共享内存**：`_XAllocTemp` / MIT-SHM 路径要
  `shmget/shmat/shmdt/shmctl`，Bionic 不提供。MiceWine 链 Termux 的 `android-shmem`；
  我们用 `android-sysvshm`，并在 `packages/depends.conf` 里声明依赖保证拓扑序在 X11 之前。
- **`XTHREADLIB=-lpthread` → `-pthread`**：Bionic 的 pthread 内建于 libc（`libx11.sh` 的 sed）。
- **libXcursor SONAME 去版本号**：Android linker 忽略版本号，但 NEEDED 写的是文件名。
- **`libxshmfence --disable-futex`**：Bionic 没有 `<linux/futex.h>`，两边一致。
- **配方尽量朴素**：MiceWine 的包多数只有 `PKG_VER` / `SRC_URL` / `CONFIGURE_ARGS` /
  `DEPENDENCIES` 四行。我们的 libpng 曾经额外做了一步 `patchelf --set-soname`，结果
  在设备上把 `.dynstr` 映射搞错、连累 freetype 加载失败、Wine 整个没字体（详见
  [ELF-PITFALLS.md](ELF-PITFALLS.md) §1）。**开始给某个包加"额外处理"之前，先看
  MiceWine 有没有这么做**——它没做而我们做了，通常是我们在自找麻烦。

## 我们刻意不同的地方

- **libdrm**：MiceWine 启用 `freedreno-kgsl`，我们全禁驱动——Turnip 由 runtimeAssets 提供，
  imagefs 只需要 libdrm 的通用部分。
- **Vulkan-Loader**：两边都走 X11 WSI，但我们额外关掉 `BUILD_WSI_XLIB_XRANDR_SUPPORT`
  以免拖入 `libxrandr`。
- **`--target-os` / `CMAKE_SYSTEM_NAME`**：MiceWine 有几处用 `Linux` 骗过 Android 分支，
  我们只在 `sdl2.sh` 这么做（并配 `-U__ANDROID__`），其余保持 Android 真值。
