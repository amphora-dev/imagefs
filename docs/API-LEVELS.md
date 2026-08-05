# Android API levels

imagefs 同时使用多个 NDK API 水位。这不是疏忽，而是按产物角色拆开的硬边界。
**不要**在未核对下列约束前把某一水位“统一”成另一水位。

## Matrix

| API | Triple / profile | 产物 | 为什么是这个数 |
|-----|------------------|------|----------------|
| **26** | `aarch64-linux-android26` · `meson-aarch64-android26.ini` | imagefs 主图（rootfs 包） | 与 Amphora app `minSdk=26` 对齐；rootfs 必须能在 Android 8+ 设备上跑 |
| **30** | `aarch64-linux-android30` · `meson-mesa-api30.ini` · `WRAPPER_API=30` | Mesa GL（imagefs 内）+ Vulkan wrapper ICD | `memfd_create` 等 libc 入口；Amphora Bionic/Linux Mesa 画像（`-D__AMPHORA__`） |
| **31** | `aarch64-linux-android31-clang` | Box64 WCP | Box64 独立 L1；高于 rootfs 地板，不链进 imagefs.txz |
| **35** | `x86_64-linux-android35` · `meson-x86_64-android35.ini` / `meson-mesa-x86_64-api35.ini` | Proton Wine Unix ELF + 开发 sysroot | 16KB page / 现代 x86_64 Bionic 目标；与 aarch64 rootfs 分离 |

Host 工具链一律来自 `buildstream-sdk` junction 的 NDK r29，不读 runner 预装 NDK。

## 关系图

```text
Amphora app (minSdk 26, targetSdk 28)
        │
        ▼
┌─────────────────── aarch64 ───────────────────┐
│  imagefs packages …………… API 26                │
│  mesa-gl (in imagefs) …… API 30 Amphora profile│
│  wrapper.tzst (L1) ……… API 30 + imagefs sysroot│
│  box64 WCP (L1) …………… API 31                  │
└───────────────────────────────────────────────┘

┌─────────────────── x86_64 ────────────────────┐
│  wine/sysroot + Proton WCP …… API 35          │
└───────────────────────────────────────────────┘
```

## 为什么不能随便收敛

### 26 → 更高
抬高 imagefs 默认 triple 等于抬高整棵 rootfs 的 `__ANDROID_API__`，会丢掉
minSdk 26 设备。除非 Amphora app 同步抬 `minSdk`，否则禁止。

### Mesa / wrapper 降到 26
API 26 的 NDK libc 没有可靠的 `memfd_create` 封装；wrapper patch
`0001-anon-file-use-memfd-create` 明确要求 `WRAPPER_API>=30`。降级会回到
`SYS_memfd_create` / 缺常量的老坑。

### Box64 降到 26 或并进 imagefs
Box64 是独立 L1 artifact，刻意不打进 `imagefs.txz`。API 31 是当前
`l1/box64-wcp.bst` 的固定编译器选择；若要降到 26，需要单独验证 dynarec /
信号路径，不能只改 clang 后缀。

### Wine 降到 26/30
Wine 侧是 **x86_64 guest** 开发 sysroot，目标含 flexible 16KB page（API35
画像）。与 aarch64 rootfs 的 API 地板无关；强行对齐只会制造错误的安全感。

## 源码锚点

| 水位 | 主要锚点 |
|------|----------|
| 26 | `project.conf` `target-triple`；`buildstream/recipes/**` 默认 |
| 30 | `buildstream-sdk` `meson-mesa-api30.ini`；`ci/wrapper/build-tzst.sh` `WRAPPER_API`；`graphics/mesa-gl.bst` |
| 31 | `l1/box64-wcp.bst` `aarch64-linux-android31-clang` |
| 35 | `sync-arch-elements.py` / wine elements `x86_64-linux-android35`；`ci/wine/build-proton-wcp.sh` |

## 变更检查单

改任一 API 水位前：

1. 对照上表确认产物角色（rootfs / ICD / Box64 / Wine）
2. 同步修改对应 meson profile 或 clang 后缀（SDK junction 可能要 bump）
3. 跑该产物的 verify gate（`ci/verify/*`）
4. 若动到 26：确认 Amphora `minSdk` 仍匹配
5. 若动到 30：确认 `memfd_create` 与 `__AMPHORA__` 画像仍成立
6. 若动到 35：确认 16KB page / Wine WCP 元数据描述仍正确
