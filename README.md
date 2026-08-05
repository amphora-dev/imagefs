# imagefs

Amphora 的 Bionic imagefs 构建项目，目标为
`aarch64-linux-android26`。构建系统只有 BuildStream 一条路径；Host SDK、
Android NDK r29 和 Meson profiles 来自 commit-pinned
[`amphora-dev/buildstream-sdk`](https://github.com/amphora-dev/buildstream-sdk)
junction。

## 本地构建

```bash
sudo apt-get install bubblewrap fuse3 git lzip patch python3-venv xz-utils
bash ci/setup/install-buildstream.sh

buildstream/bst build imagefs/package.bst
buildstream/bst artifact checkout imagefs/package.bst \
  --deps none --directory /tmp/imagefs-package
```

其他独立产物：

```bash
buildstream/bst build l1/box64-wcp.bst
buildstream/bst build l1/wrapper-tzst.bst
buildstream/bst build l1/proton-wine-wcp.bst
```

BuildStream 的 CAS 位于 `~/.cache/buildstream`。元素、源码、patch、junction
commit 或依赖发生变化时会生成新 artifact key，不恢复共享 staging、源码树或
stamp。

## 目录

```text
project.conf                         # BuildStream project 与交叉编译默认值
buildstream/recipes/                 # 平台无关包配方（编辑入口，非 element）
buildstream/elements/                # package、runtime、L1 artifact 图
buildstream/elements/buildstream-sdk.bst
buildstream/sync-arch-elements.py    # recipes → elements + wine/x86_64
ci/setup/install-buildstream.sh      # 固定 BuildStream/BuildBox 工具
ci/{gate,publish,verify}/            # 发布门禁与 artifact 验证
ci/wrapper/build-tzst.sh             # wrapper 元素的 sandbox 内打包器
vendor/                              # BuildStream local sources/patches
```

## CI 与产物

| Workflow | BuildStream target | Release |
|---|---|---|
| `build-imagefs.yml` | `imagefs/package.bst` | `amphora/imagefs.txz` |
| `build-box64.yml` | `l1/box64-wcp.bst` | `box64/Box64-*.wcp` |
| `build-wrapper.yml` | `l1/wrapper-tzst.bst` | `wrapper/wrapper-*.tzst` |
| `build-proton-wine.yml` | `l1/proton-wine-wcp.bst` | `wine/Proton-*.wcp` |

所有 upstream ref 都固定在对应 `.bst` 元素中。手动 workflow 仅支持
`force`，不接受绕过 BuildStream 的自定义源码 ref。

产物发布后由 `.github/actions/bump-manifest` 更新
`amphora-dev/content_manifest`：

- imagefs → `components.rootfs`
- Box64 → `components.box64`
- wrapper → `runtimeAssets[graphics_driver/wrapper.tzst]`

运行时 ABI/SONAME、裁剪和 ELF alignment 断言位于
[`ci/verify/`](ci/verify/) 及各元素的 install/strip commands 中。
