# CI contracts

CI 仅通过 BuildStream 构建。upstream commit、Host SDK、NDK、cross-files 和
package dependencies 都是 artifact key 的显式输入。

## Layout

```text
ci/
  setup/install-buildstream.sh
  gate/{imagefs-publish,box64-build,wrapper-build,wine-build,dxvk-build,vkd3d-build}.sh
  publish/{fixed-release,prune-assets,bump-manifest}.sh
  verify/{imagefs-artifact,wine-deps,dxvk-wcp,vkd3d-wcp}.sh
  cache/{pack,restore}-buildstream-cas.sh   # sticky local CAS; see ci/cache/README.md
  wrapper/build-tzst.sh
  dxvk/build-dxvk-wcp.sh
  vkd3d/build-vkd3d-wcp.sh
```

L1 gate（Box64 / wrapper / Wine / DXVK / VKD3D）直接读取对应 `.bst` 中固定的
源码 commit。构建器与 gate 因此不会使用不同 ref。更新 upstream 时只修改元素
source ref，并检查元素内的版本元数据。

## WCP 命名

WCP 产物名 = `profile.json` 的 `versionName`，amphora 端按
`type + verName + verCode` 判定同一 profile，因此身份字段变化必须体现在文件名里：

- Box64：`Box64-<maj>.<min>.<rev>-<upstream9>-p<p8>.wcp`，`-p<p8>` 是
  `vendor/box64-patches/pipetto-controller-fix.patch` 的 sha256 前 8 位。
  补丁变化 → 新 versionName → 设备不会与旧 profile 冲突；
  `ci/gate/box64-build.sh` 的去重 gate 同时匹配 commit 与补丁指纹。

## Toolchains

多 API 水位是按产物角色拆开的，不要随意统一。完整说明见
[`docs/API-LEVELS.md`](../docs/API-LEVELS.md)。

| API | 产物 |
|-----|------|
| 26 | imagefs package graph（AArch64 Bionic，minSdk 地板） |
| 30 | Mesa GL + Vulkan wrapper（Amphora Bionic/Linux 画像） |
| 31 | Box64 WCP（独立 L1） |
| 35 | Proton Wine x86_64 Unix ELF + LLVM-MinGW PE |

Host SDK 和 NDK 均由 `buildstream-sdk.bst` junction 提供，不读取 GitHub runner
预装 NDK。

## Publish

- 固定 Release tags：`amphora`、`box64`、`wrapper`、`wine`、`dxvk`、`vkd3d`
- `fixed-release.sh` 上传或替换当前产物
- `prune-assets.sh` 删除同一固定 tag 下的旧 L1 assets
- `bump-manifest` action 更新 `amphora-dev/content_manifest`
- push 到 `main` 会构建；手动 dispatch 可用 `force` 覆盖去重 gate

Release 与 manifest 字段由 artifact 内生成的 `.env` 文件传递，workflow 不重新
推断版本或摘要。

## Local sticky BuildStream cache

Dev machines can restore the Actions BuildStream CAS published under fixed tag
`wine-dev-bst-cache` (see [`ci/cache/README.md`](cache/README.md)). This does
not replace the `build-proton-wine` release path.
