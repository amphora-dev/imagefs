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
- Termux `libandroid-shmem` runtime and Vulkan headers/registry artifacts
- libffi as the first standard Autotools cross-compiled artifact
- xorgproto/xtrans target metadata and static GNU libiconv
- libxshmfence consuming relocated xorgproto
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

## Host SDK and target sysroot

Autotools/CMake/Meson packages use one complete host rootfs from the fixed
`buildstream-host-sdk` Release. It contains GCC/G++, Autotools, CMake,
Meson/Ninja, Perl/Python/Mako and graph support tools. BuildStream imports the
single tar source pinned by SHA-256; the earlier 14-`.deb` bootstrap has been
removed.

We evaluated importing `buildpack-deps:bookworm` first, but the released
BuildStream 2.7 docker source rejects the modern OCI index/manifest media types;
upstream support is still an unmerged change. The generated host SDK tar uses
released core capabilities instead of vendoring that patch or maintaining a
converted registry image.

`ci/buildstream/build-host-sdk.sh` starts from the SHA-pinned Ubuntu Base, uses
apt in a separate
networked bubblewrap generation step, records the complete dpkg manifest and
exports a deterministic `imagefs-host-sdk-noble-amd64.tar.xz`. The fixed
`buildstream-host-sdk` Release is published only from `main`.

The generator is reproducible across the local Cloud VM and GitHub runner:
both produced a 131 MB archive with SHA-256
`8f51c84c396969e4dd0383f1d281bf8270fde251e0427326755fa1bc5d0ba9c1`.
`host-sdk.lock` enforces this result, so an apt repository update fails closed
until the package manifest and lock are reviewed together.

Host tools remain at sandbox `/`. Android package dependencies are relocated
with BuildStream's dependency `config.location` to `/opt/android-sysroot`;
`PKG_CONFIG_SYSROOT_DIR` and `PKG_CONFIG_LIBDIR` point only there. The
`tests/autotools-sysroot-smoke.bst` element asserts Autoconf/Automake/Libtool are
available while target zlib is visible only through that sysroot.

libffi 3.4.6 is the first consumer. It builds through the official `autotools`
element, checks out to about 200 KB and preserves the `LIBFFI_*_8.0` symbol
versions.

Common Android flags and target pkg-config isolation are project defaults for
every `autotools` element. Package elements only declare sources, build
dependencies, exceptional configure switches and output-specific cleanup.

The official plugin's optional `.la` cleanup uses Bash-only `read -d` while the
sandbox command shell is POSIX `dash`; it can silently leave archives behind.
Library elements therefore perform a small portable `find -delete` cleanup and
CI asserts that static libiconv contains no `.la` metadata.

| Autotools element | Checkout | Bootstrap cold build |
|---|---:|---:|
| `libiconv` | 2.1 MB | 12 s |
| `xorgproto` | 4.5 MB | 3 s |
| `xtrans` | 272 KB | 2 s |

Together with libffi, all four resolve from a warm local CAS in 335 ms.

`libxshmfence` is the first non-test package that stages another target
artifact (`xorgproto`) at `/opt/android-sysroot`. The 40 KB checkout contains
only its header, pkg-config file and AArch64 DSO, not xorgproto's headers. The
pollfd backend, unversioned Android SONAME and `xshmfence_*` ABI match the
production recipe.

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

The Android leaf artifacts built in parallel in under one second locally:

| Element | Key | Checkout |
|---|---|---:|
| `libcxx-shared` | `33414228a3e01ff612ca089d0d9899f9f9770fa38b649ca43733e8afddec03bf` | 1.4 MB |
| `android-sysvshm` | `570cfd4ef7165a56e709aa61f1930a67ef37fd6554449882747ef322e591d92e` | 20 KB |
| `android-spawn` | `f11873124258c1ba8c4a5fb048708fa012ffd7429faca68ed12edf268d3a76e2` | 32 KB |
| `android-sysv-semaphore` | `7049017a461af2b232426269904dc233aad0d12df2c2fd02fbd292160469d411` | 16 KB |

Their exported ABI and SONAMEs are checked in CI. The first runner to add these
four elements restored the existing toolchain CAS, built and verified all six
package artifacts in 9 seconds, and uploaded them as separate directory trees.

Two more source artifacts are now covered:

| Element | Key | Checkout |
|---|---|---:|
| `libandroid-shmem` | `7f8fc23bd7c3144acfcd189ce3ea711e406aa59fd752cd888f71e34f0bc424c6` | 28 KB |
| `vulkan-headers` | `bb5165e5edf091ca2c00cb6bd8273cc43ebbb65186ef52c6726046d26fdf2083` | 32 MB |

`libandroid-shmem` pins both the full upstream commit and GitHub archive
SHA-256, exports the expected `libandroid_shm*` ABI, and deliberately omits the
polluting `sys/shm.h`. Vulkan-Headers publishes its headers and registry without
pulling the NDK into its build dependencies.

## Deliberate limits

- Thirteen packages are migrated; production `build-all.sh` is unchanged.
- NDK's zip does not preserve executable modes or symlinks through the community
  source plugin, so the toolchain element restores both before publishing its
  artifact. This matters for LLVM multicall tools such as `llvm-strip`.
- zstd is linked from its upstream library source set without CMake. This keeps
  host tools declared (shell/coreutils + NDK only) and preserves SONAME at link
  time, but differs from the production CMake recipe.
- Vulkan CMake package metadata is not generated yet; headers and the registry
  used by current downstream recipes are present.
- libpng is the next high-risk Autotools package; it remains on the production
  path until a BuildStream build passes dedicated `PNG16_0`, SONAME and LOAD
  segment alignment checks.
- GMP remains deferred until a supported, pinned Linux host compiler artifact
  is available. NDK Clang is kept strictly on its supported Android target.
