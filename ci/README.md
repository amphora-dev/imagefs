# CI contracts

CI 仅通过 BuildStream 构建。upstream commit、Host SDK、NDK、cross-files 和
package dependencies 都是 artifact key 的显式输入。

## Layout

```text
ci/
  setup/install-buildstream.sh
  setup/configure-remote-cache.sh           # remote cache → ~/.config/buildstream.conf
  gate/{imagefs-publish,box64-build,wrapper-build,wine-build,dxvk-build,vkd3d-build}.sh
  publish/{fixed-release,prune-assets,bump-manifest}.sh
  verify/{imagefs-artifact,wine-deps,dxvk-wcp,vkd3d-wcp}.sh
  wrapper/build-tzst.sh
  dxvk/build-dxvk-wcp.sh
  vkd3d/build-vkd3d-wcp.sh
```

L1 gate（Box64 / wrapper / Wine / DXVK / VKD3D）直接读取对应 `.bst` 中固定的
源码 commit。构建器与 gate 因此不会使用不同 ref。更新 upstream 时只修改元素
source ref，并检查元素内的版本元数据。

## BuildStream 命令写法

BuildStream 用 `sh -c -e` 执行元素里的 `*-commands`，而 SDK 基础镜像是 Ubuntu，
`/bin/sh` 是 dash，所以 inline 命令只能写 POSIX sh。超过几行的逻辑放进
`ci/<组件>/*.sh`（`#!/usr/bin/env bash` + `set -euo pipefail`），元素里用
`bash .bst/ci/<组件>/<脚本>.sh` 调用，参数通过 `environment:` 传入；
Box64 / DXVK / VKD3D / Proton 都按这个写。`ci/lint/check-bst-inline-sh.py`
在 lint 工作流里对所有 inline 命令跑 `shellcheck -s sh`。

## WCP 命名

WCP 产物名 = `profile.json` 的 `versionName`，amphora 端按
`type + verName + verCode` 判定同一 profile，因此身份字段变化必须体现在文件名里：

- Box64：`Box64-<maj>.<min>.<rev>-<upstream9>-p<p8>.wcp`，`-p<p8>` 是
  `vendor/box64-patches/pipetto-controller-fix.patch` 的 sha256 前 8 位。
  补丁变化 → 新 versionName → 设备不会与旧 profile 冲突；
  `ci/gate/box64-build.sh` 的去重 gate 同时匹配 commit 与补丁指纹。

- Proton Wine：`Proton-<wine version>-<commit9>-x86_64.wcp`，commit 取自元素
  `PROTON_COMMIT`；它必须与 sources 的 git `ref` 一致（BuildStream stage 不保留
  `.git`，无法在沙箱内查询），`ci/gate/wine-build.sh` 校验两者，不一致即失败。

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

## Remote cache

`ci/setup/configure-remote-cache.sh` writes `~/.config/buildstream.conf` so
BuildStream uses `https://cas.arm.512.pub` for CAS, element artifacts, source
cache and the action cache behind `remote-apis-socket` (recc compile results).
That name is the origin A record. Do not switch it to the Cloudflare-proxied
`cas-arm.512.pub`: orange-cloud stalls buildbox gRPC streams, and pushes stop
making progress. Each RPC has a 900s timeout and a 30s keepalive.
Workflows get it through `.github/actions/setup-buildstream` with the
`BST_REMOTE_CACHE_TOKEN` secret; fork PRs have no secret and build from the
local cache. On a dev machine run the same script with `BST_REMOTE_CACHE_TOKEN`
set.
