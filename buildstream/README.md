# BuildStream proof of concept

This is an opt-in migration experiment, not the production imagefs builder.
It proves that an Android package can be built into an isolated,
content-addressed artifact without restoring `staging`, `src` or stamp files.

## Scope

- Ubuntu Base 24.04.4: glibc sandbox runtime, pinned by SHA-256
- Android NDK r29: toolchain artifact, pinned by SHA-256
- zlib 1.3.1 and zstd 1.5.6: independent `aarch64-linux-android26`
  artifacts
- NDK libc++ runtime plus Winlator shm/spawn/semaphore compatibility artifacts
- GitHub Actions: persists BuildStream's content-addressed store

The package outputs contain only their own:

```text
/usr/lib/lib{z,zstd}.so*
/usr/include/{zlib,zstd,zdict,...}.h
/usr/lib/pkgconfig/{zlib,libzstd}.pc
```

The Ubuntu build runtime and NDK are build dependencies and are not copied into
package artifacts.

The project is rooted at the repository `project.conf`, allowing `kind: local`
sources to hash `vendor/` directly without copying them under `buildstream/`.

## Run locally

Install host sandbox dependencies:

```bash
sudo apt-get install bubblewrap fuse3 git lzip patch python3-venv xz-utils
bash ci/setup/install-buildstream.sh
```

Then build and inspect:

```bash
buildstream/bst build compress/zlib.bst compress/zstd.bst
buildstream/bst show compress/zstd.bst --format '%{state} %{full-key}'
buildstream/bst artifact checkout compress/zlib.bst \
  --deps none \
  --directory /tmp/buildstream-zlib
```

The first run downloads Ubuntu Base (~29 MB) and NDK r29 (~783 MB). Later runs
reuse source and artifact objects from `~/.cache/buildstream`; if the zlib
element, source, NDK or base runtime changes, BuildStream computes a different
artifact key instead of mutating an old sysroot.

GitHub runners often have an NDK preinstalled, but bind-mounting it would make
host contents invisible to the BuildStream cache key. A pinned NDK artifact is
intentional: the first fetch is larger, while later runners restore the same
verified content from CAS.

## Measured result

The validated artifact key is
`217d52ed32239ecfa4ea54c28bce3d145d306809b2727887d0df437d86da52a3`.
On the local trial, a second `bst build` completed from CAS in 334 ms. The
checked-out package is 240 KB, reports `Machine: AArch64` and
`SONAME: libz.so.1`, and contains neither `/opt/android-ndk` nor Ubuntu's
`/bin/sh`.

The first successful GitHub run spent 37 seconds in the build step (including
source fetch and NDK artifact creation). A second runner restored the CAS in
12 seconds and completed the same build step in 1 second. This demonstrates
cross-run package artifact reuse, not just a warm directory on one machine.

The zstd artifact key is
`a0386aadf65f00b0c17c46f9235c08393a0242c77ba308adae7005de75f4ff23`.
Its cold package compile took 9 seconds, a warm build took 333 ms, and the
checked-out artifact is 816 KB. It has `SONAME: libzstd.so.1` and exports the
`ZSTD_compress`, `ZSTD_decompress` and `ZSTD_versionNumber` ABI entry points.

## Deliberate limits

- Only six leaf packages are migrated; production `build-all.sh` is unchanged.
- NDK's zip does not preserve executable modes or symlinks through the community
  source plugin, so the toolchain element restores both before publishing its
  artifact. This matters for LLVM multicall tools such as `llvm-strip`.
- zstd is linked from its upstream library source set without CMake. This keeps
  host tools declared (shell/coreutils + NDK only) and preserves SONAME at link
  time, but differs from the production CMake recipe.
