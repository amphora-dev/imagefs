# BuildStream graph

仓库根目录的 `project.conf` 定义生产构建。所有 package 都在隔离 sandbox 中构建
并输出只包含自身 `/usr` 内容的 CAS artifact。

## Shared SDK

`buildstream-sdk.bst` 以完整 Git commit 固定
`amphora-dev/buildstream-sdk`，并提供：

- Ubuntu Noble amd64 Host SDK
- Android NDK r29
- Meson Android/native profiles

package 的 target dependencies 通过 `config.location` 放到
`/opt/android-sysroot`，Host SDK 留在 sandbox `/`。`PKG_CONFIG_SYSROOT_DIR`
和 `PKG_CONFIG_LIBDIR` 只指向 target sysroot，避免 host headers/libraries
污染 Android artifact。

## Targets

```text
imagefs/package.bst
  imagefs/runtime.bst
    imagefs/staging.bst
      40 package elements + imagefs/base-layout.bst

l1/box64-wcp.bst
l1/wrapper-tzst.bst
```

`imagefs/runtime.bst` 完成 merged-usr composition 与裁剪；
`imagefs/package.bst` 生成可复现 `imagefs.txz`、SHA-256 和分卷。

Box64 是独立 CMake/WCP artifact。wrapper 元素将固定 Mesa 与
libadrenotools source、目标依赖和 NDK 放入同一 sandbox，再调用
`ci/wrapper/build-tzst.sh` 完成 ABI 校验与 TZST 打包。

## Commands

```bash
bash ci/setup/install-buildstream.sh

buildstream/bst show imagefs/package.bst
buildstream/bst build imagefs/package.bst
buildstream/bst build l1/box64-wcp.bst
buildstream/bst build l1/wrapper-tzst.bst
```

源码、patch、element、junction ref 和依赖 artifact 都参与 key 计算。不得在
BuildStream 外维护平行 package recipes、共享 staging 或完成标记。
