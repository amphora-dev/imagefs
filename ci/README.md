# CI contracts

CI 仅通过 BuildStream 构建。upstream commit、Host SDK、NDK、cross-files 和
package dependencies 都是 artifact key 的显式输入。

## Layout

```text
ci/
  setup/install-buildstream.sh
  gate/{imagefs-publish,box64-build,wrapper-build,wine-build}.sh
  publish/{fixed-release,prune-assets,bump-manifest}.sh
  verify/{imagefs-artifact,wine-deps}.sh
  wrapper/build-tzst.sh
```

Box64 和 wrapper gate 直接读取对应 `.bst` 中固定的源码 commit。构建器与 gate
因此不会使用不同 ref。更新 upstream 时只修改元素 source ref，并检查元素内的
版本元数据。

## Toolchains

- imagefs package graph：AArch64 Bionic API 26
- Box64：AArch64 Bionic API 31
- wrapper：imagefs target sysroot + Mesa API 30
- Proton Wine：x86_64 Bionic API35 + LLVM-MinGW x86_64/i386 PE

Host SDK 和 NDK 均由 `buildstream-sdk.bst` junction 提供，不读取 GitHub runner
预装 NDK。

## Publish

- 固定 Release tags：`amphora`、`box64`、`wrapper`、`wine`
- `fixed-release.sh` 上传或替换当前产物
- `prune-assets.sh` 删除同一固定 tag 下的旧 L1 assets
- `bump-manifest` action 更新 `amphora-dev/content_manifest`
- push 到 `main` 会构建；手动 dispatch 可用 `force` 覆盖去重 gate

Release 与 manifest 字段由 artifact 内生成的 `.env` 文件传递，workflow 不重新
推断版本或摘要。
