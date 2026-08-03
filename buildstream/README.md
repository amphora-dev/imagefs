# BuildStream proof of concept

This is an opt-in migration experiment, not the production imagefs builder.
It proves that an Android package can be built into an isolated,
content-addressed artifact without restoring `staging`, `src` or stamp files.

## Scope

- Ubuntu Base 24.04.4: glibc sandbox runtime, pinned by SHA-256
- Android NDK r29: toolchain artifact, pinned by SHA-256
- zlib 1.3.1: independent `aarch64-linux-android26` artifact
- GitHub Actions: persists BuildStream's content-addressed store

The zlib output contains only:

```text
/usr/lib/libz.so*
/usr/include/{zlib.h,zconf.h}
/usr/lib/pkgconfig/zlib.pc
```

The Ubuntu build runtime and NDK are build dependencies and are not copied into
the zlib artifact.

## Run locally

Install host sandbox dependencies:

```bash
sudo apt-get install bubblewrap fuse3 git lzip patch python3-venv xz-utils
bash ci/setup/install-buildstream.sh
```

Then build and inspect:

```bash
buildstream/bst build compress/zlib.bst
buildstream/bst show compress/zlib.bst --format '%{state} %{full-key}'
buildstream/bst artifact checkout compress/zlib.bst \
  --deps none \
  --directory /tmp/buildstream-zlib
```

The first run downloads Ubuntu Base (~29 MB) and NDK r29 (~783 MB). Later runs
reuse source and artifact objects from `~/.cache/buildstream`; if the zlib
element, source, NDK or base runtime changes, BuildStream computes a different
artifact key instead of mutating an old sysroot.

## Deliberate limits

- Only zlib is migrated; the production `build-all.sh` path is unchanged.
- NDK's zip does not preserve executable modes or symlinks through the community
  source plugin, so the toolchain element restores both before publishing its
  artifact. This matters for LLVM multicall tools such as `llvm-strip`.
- zstd is the next useful trial, but requires a sandbox-provided CMake and Make.
  This PoC first validates the harder foundation: glibc sandbox + NDK artifact +
  Android ELF output + cache reuse.
