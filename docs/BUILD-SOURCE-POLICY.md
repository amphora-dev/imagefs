# 二进制来源与源码构建策略

> 最后更新：2026-08-11  
> 适用范围：`amphora-dev/imagefs` 及其向 Amphora app 交付的运行时组件。

## 1. 原则

“自己构建”应表示：从固定的上游源码和补丁，在 Amphora 控制的可复现构建图中产出并
验证二进制。它不表示重写 Wine、Mesa 或 PulseAudio，也不要求把编译器本身从零
bootstrap。

是否自构建按以下风险决定：

1. 二进制是否进入用户设备的运行时；
2. Amphora 是否需要 Android/Bionic、16 KB page、Box64 或私有 ABI 补丁；
3. 上游是否提供可追溯源码、许可证和可复现配方；
4. 自构建能否增加实际门禁，而不是只更换下载地址；
5. 维护成本是否会挤占运行时兼容性工作。

源码 tarball 或 git commit 来自别人，不等于使用别人的预编译产物。BuildStream 固定
源码哈希、工具链、补丁和依赖后，产物仍由 Amphora 构建。

## 2. 当前组件矩阵

| 组件 | 当前来源 | 是否由 Amphora 构建 | 结论 |
|---|---|---:|---|
| imagefs 基础库、X11、GStreamer、Mesa GL | 固定源码归档 | 是 | 保持；已在 BuildStream 图内 |
| Proton Wine | `amphora-dev/proton-wine` 固定 commit | 是 | 保持；Android 补丁和 ABI 风险高 |
| Box64 | `ptitSeb/box64` 固定 commit + 本地 patch | 是 | 保持；JIT/Android 适配必须可回归 |
| DXVK / VKD3D-Proton | 固定 git commit + 本地构建脚本 | 是 | 保持；PE 架构和 shader 工具链有门禁 |
| Vulkan wrapper / libadrenotools | Pipetto fork 固定 commit | 是 | 保持；Android loader 和 RPATH 需要控制 |
| Proton PrefixPack | Amphora 设备测试生成，Release SHA 固定 | 是，生成与消费分阶段 | 合理的 bootstrap 产物，不回退到第三方 seed |
| PulseAudio x86_64 开发输入 | Termux PA13 `.deb`，SHA 固定 | **否**，仅构建期 | 过渡例外；不进入 WCP/imagefs |
| PulseAudio AArch64 daemon/client/modules | Amphora app 内 WinNative PA13 匹配套件 | **否** | 优先补齐源码构建 |
| NDK、llvm-mingw、host glslang | 固定的预编译工具链 | 否，仅构建期 | 不建议为“全自建”而重建 |
| Turnip 游戏 ICD | 不属于 imagefs 主包，由内容资产交付 | 当前 imagefs 不构建 | 建议建立独立源码构建与设备矩阵后再接管 |

`imagefs/runtime.bst` 明确拒绝把 `libvulkan_freedreno.so` 混入 rootfs。Turnip 与 Mesa
GL/Zink 的发布节奏、设备适配和回退策略不同，不应为了形式上的“全在 imagefs”而合包。

## 3. PulseAudio 为什么从 17 改为 13

这次变化不是把已部署的 PA17 功能降级为 PA13。实际顺序是：

1. Amphora app 首先采用了 WinNative 的 PA13 Android 运行时套件；
2. 初版 Proton `winepulse.so` 构建误用了 Termux PA17 头文件和链接库；
3. 审计发现构建输入与真实运行时 ABI 不同；
4. Wine 构建输入随即改为 PA13，与 APK 运行时对齐。

必须对齐的不是只有 Pulse wire protocol：

- `libpulse` 是 Wine 的 public client 边界；
- `libpulsecommon-13.0.so`、`libpulsecore-13.0.so` 与 loadable modules 属于
  版本绑定的内部 ABI；
- `module-aaudio-sink` 与 `module-native-protocol-unix` 必须由同一套 core/common
  加载；
- Box64 把 x86_64 `winepulse.so` 的 `DT_NEEDED=libpulse.so` 包装到 APK 的 AArch64
  `libpulse.so`，编译期若引用 PA17 新符号，运行时不能靠协议兼容补救。

因此当前构建 fail-closed 验证：

- `PA_MAJOR == 13`、`PA_PROTOCOL_VERSION == 33`；
- Termux 开发库属于 `libpulsecommon-13.0.so` 套件；
- WCP 中存在 x86_64 Unix `winepulse.so` 及 x64/x86 PE `winepulse.drv`；
- 最终 Unix 驱动只依赖无版本名的 `libpulse.so`，不出现 `libpulse.so.0` 或
  `libpulsecommon-17`；
- imagefs 不提供 guest `libpulse`，防止绕过 APK 内匹配的 native wrapper。

选择 PA13 是**锁定当前已验证 ABI**，不是长期拒绝升级。升级到 PA17/后续版本必须同时
重建 daemon、client、core/common、`pactl`、全部 modules、AAudio sink 和 Wine
link input，再做一次完整设备发布；不能只换 Wine 的头文件。

## 4. 为什么当前使用 Termux/WinNative 产物

### Termux PA13 `.deb`

该文件只提供 x86_64 Android/Bionic 头文件与链接库：

- Wine 的 Unix 侧目标是 `x86_64-linux-android30`，普通 Ubuntu `libpulse-dev` 是
  glibc 产物，不能使用；
- 旧 Termux 仓库仍提供与 app PA13 同代的 Bionic 包；
- BuildStream 固定 URL 和 SHA，解包后检查版本与动态依赖；
- 只有编译/链接输入被使用，`.deb`、`libpulsecommon` 和 Termux 绝对路径均不进入
  最终 WCP。

所以它目前是一个精确的交叉编译 SDK，而不是设备运行时依赖。

### WinNative PA13 运行时

采用它的现实原因是该套件已经把以下内容作为一个匹配单元交付：

- AArch64 Pulse daemon 和 client；
- `libpulsecore/common-13.0`、`libsndfile`、`libltdl`；
- `pactl`、native protocol module、protocol helper；
- 非上游标准组件 `module-aaudio-sink`。

当前 Amphora 仓库没有 AAudio sink 的来源清晰源码、Android patch 集和完整构建配方。
仅从 upstream PulseAudio 13 构建 daemon，仍然得不到这条 AAudio 输出路径。复制匹配
套件比混搭“自建 core + 外部 module”安全，但缺点也明确：

- 无法自行补 16 KB page alignment；当前因此在 16 KB 设备回退 ALSA；
- 无法证明每个二进制的编译参数和源码 commit；
- 安全更新和符号审计依赖外部产物；
- app 仓库保存二进制，构建链不能重新生成并比对。

结论：当前选择适合作为恢复功能的过渡方案，不是最终供应链方案。

## 5. PulseAudio 自建目标

只有取得许可和来源明确的 `module-aaudio-sink` 源码后，才应切换。推荐结构：

```text
audio/pulseaudio-13.bst
  ├─ aarch64 runtime: daemon, pactl, libpulse*, core/common, native protocol
  └─ x86_64 dev: headers + public libpulse link input

audio/module-aaudio-sink.bst
  └─ 与同一 PA13 core headers 构建

l1/pulseaudio-apk-assets.bst
  ├─ jniLibs/arm64-v8a/*.so
  ├─ pulseaudio.tzst
  ├─ provenance.json
  └─ sha256sum

l1/proton-wine-wcp.bst
  └─ 依赖 x86_64 PA dev element，不再解 Termux deb
```

构建必须使用与其他 Android 运行时相同的 NDK 和 API 基线，并增加：

1. 所有 AArch64 ELF 的 16 KB `PT_LOAD` 对齐与同余检查；
2. SONAME、`DT_NEEDED`、导出符号和绝对路径白名单；
3. daemon 对所有 module 的 `dlopen` smoke test；
4. `pactl info`、sink ready、suspend/resume 和 AAudio disconnect 实机测试；
5. x86_64 Wine → Box64 wrapper → AArch64 `libpulse` 的端到端测试；
6. 构建两次 SHA 一致性和源码/patch/工具链 provenance。

在这些门禁完成前，不应删除 ALSA 回退。

## 6. 其他组件是否都应自建

### 应继续自建

- **Wine、Box64**：Android/Bionic、RELR、16 KB page、JIT 和 guest ABI 都需要本地
  patch 与验证。
- **Mesa GL、wrapper、DXVK、VKD3D**：它们直接决定图形兼容性，且源码构建已落地；
  改回预编译没有收益。
- **rootfs 共享库**：必须与同一 sysroot、SONAME 和裁剪策略一致。

### 建议下一步自建

- **PulseAudio 完整运行时**：当前最高供应链缺口，但前提是 AAudio sink 源码可审计。
- **Turnip 发布资产**：驱动对 Adreno 代际、Android loader、16 KB page 和 Mesa 版本
  高度敏感。应建立独立元素、设备 allowlist 和回退后接管，不能只把任意 Mesa main
  编译结果推给所有设备。

### 不值得为了形式而自建

- **NDK、llvm-mingw**：官方/固定工具链本身是构建输入；从 LLVM 源码 bootstrap
  成本很高，不能改善 Amphora 运行时 ABI。
- **host glslang 等 host tools**：不进入设备，只需固定版本、哈希并记录 provenance。
- **标准字体和 Windows redistributable**：是否可分发首先是许可证问题，不是能否编译
  的问题。

自建优先级应是“运行时风险 × 可修复收益”，不是预编译文件数量。对高风险运行时组件，
源码构建能带来 patch、16 KB 和 ABI 门禁；对稳定 host 工具，自建通常只增加维护面。

## 7. 变更门禁

引入任何新的预编译运行时文件前，必须记录：

- 来源 URL、版本/commit、SHA-256 和许可证；
- 目标 ABI、API level、page alignment、SONAME 与 `DT_NEEDED`；
- 为什么不能在当前 BuildStream 图中从源码构建；
- 替换/回退路径和删除该例外的条件。

把预编译输入改为源码构建时，不以“成功产出文件”为完成标准；必须证明新产物与消费者
的 ABI、行为和设备矩阵匹配。
