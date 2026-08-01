# Bionic 上的 ELF 陷阱

交叉编译到 Bionic 时，`readelf` 看着完全正常、CI 全绿、只有真机 `dlopen` 才炸的那几类问题。
每条都写清楚**症状 → 根因 → 规则 → 断言在哪**，因为它们的共同特征是：
静态检查看不出来，复现要设备。

参照实现：[`KreitinnSoftware/MiceWine-Packages`](https://github.com/KreitinnSoftware/MiceWine-Packages)。
它同样把上游库交叉编译到 Bionic，配方极简（多数只有 `PKG_VER` / `SRC_URL` /
`CONFIGURE_ARGS` / `DEPENDENCIES` 四行）。**当我们的配方开始做"额外处理"时，先去看
MiceWine 有没有做**——它没做而我们做了，通常说明我们在给自己制造问题。目标差异见
[MICEWINE-COMPARISON.md](MICEWINE-COMPARISON.md)。

---

## 1. 不要事后 patchelf 改 SONAME（2026-08-01，真实事故）

**症状**：Wine 窗口全白。日志里是字体，不是图形：

```
[BOX64] Error initializing native libfreetype.so (last dlerror is dlopen failed:
  cannot find "libpng16.so.16" from verneed[0] in DT_NEEDED list for .../libfreetype.so)
Wine cannot find the FreeType font library.
```

把 libpng 强行先加载，报错就露馅了：

```
cannot find "_chunk_fn" from verneed[0] in DT_NEEDED list for .../libpng16.so.16.44.0
```

`_chunk_fn` 是个符号名，不是库名——说明运行期读到的字符串表整个错位了。

**根因**：`patchelf --set-soname` 把改写后的 `.dynstr` 放进新追加的 LOAD 段：

```
LOAD  0x031508  0x0000000000040000  ...  RW  0x10000
```

`0x40000 - 0x31508` 不是页大小的整数倍。加载器要求 `p_vaddr % pagesize == p_offset % pagesize`，
不满足时 `DT_STRTAB` 指向的位置与文件里的内容对不上，于是 `.gnu.version_r` / `.gnu.version_d`
里的名字全变成随机字符串。libpng 因此加载失败，连累 DT_NEEDED 它的 libfreetype 一起失败，
Wine 就彻底没有字体——窗口画得出来，但一个字都没有。

**为什么 CI 没拦住**：`readelf` 通过 section header 的 `sh_link` 找字符串表，那条路径是对的，
所以 `readelf -V` 打印出来的名字完全正常。只有运行期走 `DT_STRTAB` 才会踩空。
两条路径在正常 ELF 上等价，恰恰在被 patchelf 搬过的文件上分叉。

**规则**：SONAME 只能在链接时定（`-Wl,-soname,...`）。要改就重链，别 patch。
MiceWine 的 [`packages/libpng/build.sh`](https://github.com/KreitinnSoftware/MiceWine-Packages/blob/main/packages/libpng/build.sh)
是四行朴素 autotools，不碰 patchelf，所以上游从来没遇到这个问题。

**断言**：`ci/verify/wine-deps.sh` 遍历所有 `.so`，检查每个 LOAD 段的
`p_vaddr` 与 `p_offset` 页同余。当时扫 imagefs v29，134 个库里只有 libpng 一个中招。

`ci/wrapper/build-tzst.sh` 仍在用 `patchelf --set-rpath` / `--replace-needed` /
`--remove-needed`——那几种改写不需要扩容 `.dynstr`，产物通过同一条断言，且真机验证正常。
危险的是**加长字符串表**的操作（`--set-soname` / `--add-needed` / 换更长的 rpath）。

---

## 2. 符号版本（verneed / verdef）在 Bionic 上是真生效的

Android linker 会检查 verneed：对每个 `.gnu.version_r` 条目，要在**已加载的 DT_NEEDED 子库**
里找到 soname 完全相同的那个。所以：

- 库 A 链接了带 version script 的库 B（如 libpng 的 `PNG16_0`），A 就会带上 verneed，
  运行期 B 必须以**同一个 soname** 成功加载。
- B 加载失败时，报错文本是「在 A 的 DT_NEEDED 里找不到 B」，容易误判成"库缺失"。
  先确认 B 本身能不能单独加载。

libpng 保留 `PNG16_0` 是刻意的（`packages/compress/libpng.sh`：Android cmake 不生成
version script 会丢掉它），freetype 那边的 verneed 也就必须匹配得上。

---

## 3. 版本化 soname 的软链要齐

Android linker 忽略版本号语义，但 `DT_NEEDED` 里写的就是文件名。消费者写
`libzstd.so.1`，rootfs 里只有 `libzstd.so` 就是加载失败。`config.sh` 的
`ensure_soname_link` 负责补齐，`ci/verify/wine-deps.sh` 里按文件名逐个断言。

同一个坑的另一面：**只丢实体不给软链**。WinNative 预编译的 `extra_libs.tzst` 里只有
`libGL.so.1.5.0`，没有 `libGL.so.1`，而 Wine `opengl32` dlopen 的正是 `libGL.so.1`——
那条 OpenGL 栈从来就没通过。自建的 `mesa-gl` 由 meson 正常安装，软链完整。

---

## 复现手法（不用启动 Wine）

imagefs 里有几个 aarch64 可执行文件可以直接触发整条依赖链，比起跑一局游戏快得多：

```bash
adb shell 'run-as app.amphora sh -c "
  export LD_LIBRARY_PATH=/data/user/0/app.amphora/files/imagefs/usr/lib:/system/lib64
  files/imagefs/usr/bin/fc-cache --version"'
```

`fc-cache` 拉起 fontconfig → freetype → libpng → zlib 一整条链，输出版本号就说明这条链是通的。
配合 `LD_PRELOAD=<某个库>` 可以把报错往下逼一层，定位到真正加载失败的那个库。
