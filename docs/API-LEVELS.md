# Android API levels

imagefs 同时使用两个 NDK API 水位。这不是疏忽，而是按产物角色拆开的硬边界。
**不要**在未核对下列约束前把 rootfs 地板（26）抬到 30，或把 Mesa/Wine/Box64
的 30 降回 26。

当前 Amphora app 已是 `minSdk=30`、`targetSdk=36`。rootfs 保留 API 26 是为了减少
基础共享库对较新 Bionic 符号的依赖并维持稳定 ABI，不再是因为 app 仍支持 API 26。

## Matrix

| API | Triple / profile | 产物 | 为什么是这个数 |
|-----|------------------|------|----------------|
| **26** | `aarch64-linux-android26` · `meson-aarch64-android26.ini` | imagefs 主图（rootfs 包） | 基础共享库使用保守 Bionic ABI；当前 app 地板更高，但无必要把整棵依赖图一并抬高 |
| **30** | `aarch64-linux-android30` · `x86_64-linux-android30` · `meson-mesa-api30.ini` · `meson-x86_64-android30.ini` · `meson-mesa-x86_64-api30.ini` · `WRAPPER_API=30` | Mesa GL + Vulkan wrapper ICD；Box64 WCP；Proton Wine Unix ELF / 开发 sysroot | `memfd_create` 等 libc 入口；Amphora Bionic/Linux Mesa 画像（`-D__AMPHORA__`）；Wine 另加 flexible 16KB page **linker flags**（与 API 数字无关） |

Host 工具链一律来自 `buildstream-sdk` junction 的 NDK r29，不读 runner 预装 NDK。

## 关系图

```text
Amphora app (minSdk 30, targetSdk 36)
        │
        ▼
┌─────────────────── aarch64 ───────────────────┐
│  imagefs packages …………… API 26                │
│  mesa-gl (in imagefs) …… API 30 Amphora profile│
│  wrapper.tzst (L1) ……… API 30 + imagefs sysroot│
│  box64 WCP (L1) …………… API 30                  │
└───────────────────────────────────────────────┘

┌─────────────────── x86_64 ────────────────────┐
│  wine/sysroot + Proton WCP …… API 30 + 16KB   │
└───────────────────────────────────────────────┘
```

## 为什么不能再收敛

### 26 → 更高
抬高 imagefs 默认 triple 等于抬高整棵 rootfs 的 `__ANDROID_API__`，会扩大对新
Bionic 符号的依赖并使缓存整体失效。app 当前虽已是 minSdk 30，也只能在有明确依赖
收益并完成全图 ABI/设备验证时调整，不能为“数字统一”而抬高。

### Mesa / wrapper / Box64 / Wine 降到 26
API 26 的 NDK libc 没有可靠的 `memfd_create` 封装；wrapper patch
`0001-anon-file-use-memfd-create` 明确要求 `WRAPPER_API>=30`。降级会回到
`SYS_memfd_create` / 缺常量的老坑。Box64 / Wine 同样以 API 30 为编译目标。

### 16KB page ≠ API 水位
Wine x86_64 ELF 的 flexible 16KB page 来自
`-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES` 与 `-Wl,-z,max-page-size=16384`
（见 SDK `meson-*-android30.ini` / `ci/wine/build-proton-wcp.sh`），由
`ci/verify/proton-wcp.sh` fail-closed 校验。改 API 数字时不得丢掉这些 flags。

## 源码锚点

| 水位 | 主要锚点 |
|------|----------|
| 26 | `project.conf` `target-triple`；`buildstream/recipes/**` 默认 |
| 30 | `buildstream-sdk` `meson-mesa-api30.ini` / `meson-x86_64-android30.ini` / `meson-mesa-x86_64-api30.ini`；`ci/wrapper/build-tzst.sh` `WRAPPER_API`；`graphics/mesa-gl.bst`；`l1/box64-wcp.bst`；`sync-arch-elements.py` / wine elements；`ci/wine/build-proton-wcp.sh` |

## 变更检查单

改任一 API 水位前：

1. 对照上表确认产物角色（rootfs / ICD / Box64 / Wine）
2. 同步修改对应 meson profile 或 clang 后缀（SDK junction 可能要 bump）
3. 跑该产物的 verify gate（`ci/verify/*`）
4. 若动到 26：审计新增 Bionic 符号、全图 artifact 变化和 API 30 实机启动
5. 若动到 30：确认 `memfd_create`、`__AMPHORA__` 画像与 Wine 16KB flags 仍成立
