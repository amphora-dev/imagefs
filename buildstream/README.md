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
- portable GMP with separate host GCC and Android NDK compiler roles
- CMake leaves: Brotli, Expat and PCRE2
- libpng with PNG16_0/SONAME/LOAD alignment enforcement
- FreeType over target zlib/libpng/Brotli through a shared Meson cross-file
- Fontconfig over the completed target font dependency graph
- GLib over target zlib/libffi/PCRE2/static libiconv
- OpenSSL and GnuTLS/Hogweed crypto runtime layer
- minimal libdrm Meson artifact for the graphics stack
- Vulkan loader with XCB/Xlib WSI over the target X11 graph
- SDL2 Linux/X11 profile over target ALSA and completed X11 headers
- GStreamer core/base Wine media runtime libraries
- Mesa desktop GL/EGL with Zink + softpipe and native TLS enforcement
- complete merged-usr staging/runtime composition and reproducible imagefs.txz
- Nettle/Hogweed over target GMP and minimal ALSA lib
- Android audio-server ALSA PCM plugin and configuration
- libxcb plus separately cached xcb-proto, libXau and libXdmcp inputs
- libX11 over the composed XCB/xtrans/sysvshm target graph
- first X11 extension layer: Xext, Xfixes and Xrender
- remaining X11 client layer: Xcursor, Xi and Xxf86vm
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
`942776693e88cdc95a93e2e9b351e75f3a8be1fddfa1b85d3081787946852af3`.
`host-sdk.lock` enforces this result, so an apt repository update fails closed
until the package manifest and lock are reviewed together.
Meson 1.11.2 is installed from a pinned PyPI version and recorded separately in
the SDK pip manifest.

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

The first CMake batch uses the official plugin with centralized NDK/sysroot
flags:

| CMake element | Key | Checkout | Cold build |
|---|---|---:|---:|
| `brotli` | `88fa5768e77b89eaf6dae1c5e3a5133a3ea25e42a18d1022ba2ff2b5a17d8997` | 944 KB | 4 s |
| `libexpat` | `90a7132a462820bce0f473133fd1795ce6cec9d6d3740239a2ea7df814eab77c` | 432 KB | 4 s |
| `pcre2` | `3d572e160c04c031e3c9f7451dca90ec5d0d93c1bf6b0b0bcae53a2473b0e281` | 3.0 MB | 9 s |

All DSOs are stripped, versioned SONAMEs match downstream NEEDED entries and
the three-package warm build takes 433 ms. CMake target probes are linked
instead of forced static, preventing host-style false positives such as
`-lpthreads`.

The first font dependencies are:

| Element | Key | Checkout | Cold package build |
|---|---|---:|---:|
| `libpng` | `cd01ce8881a9041fedbeceaf9485d772590ec944701cd0a54bef0eac8299f096` | 752 KB | 4 s |
| `freetype` | `310647c50594a8ed8f6d62c14ca951f3659df9e69ba5ef17b11dfd404b87bd49` | 1.7 MB | 5 s |

libpng fails closed on PNG16_0, `libpng16.so.16`, unresolved NEON symbols and
LOAD page congruence. FreeType's Meson build records target zlib,
libpng16 and Brotli NEEDED entries without carrying those dependencies. Their
warm build takes 432 ms.

The upper text layer is:

| Element | Key | Checkout | Cold package build |
|---|---|---:|---:|
| `fontconfig` | `fde64b4e8f7ffb79a1a8e0bfe438bcc30b70d04e75fbc704ca9f3a954751b9b6` | 888 KB | ~6 s |
| `glib` | `f71063e0d2dee146d3f68d278f204e10bb0076d3baa5042d3e5501af86d5b5bf` | 20 MB | 25 s |

GLib pins proxy-libintl as an explicit offline source, applies the known Bionic
frexp/frexpl cross result, and strips all six GLib DSOs plus `libintl.so`.
Fontconfig installs merged-usr-compatible `/usr/etc/fonts` paths. Their warm
build takes 438 ms.

The next dependency layer adds:

| Element | Key | Checkout | Cold build |
|---|---|---:|---:|
| `nettle` | `6d3156ba3c5e9b90ae5024f96b169824696e2ab266cd9758612ae1b358cbcede` | 1.3 MB | 9 s |
| `alsa-lib` | `4d7526a5b070d96b3899f5fd3bbb3c4bf1e26cbcc0c10adf70d539036b9ad054` | 2.0 MB | 10 s |

Nettle consumes GMP only through `/opt/android-sysroot`; Hogweed has the
expected `libgmp.so` NEEDED entry without carrying GMP files in its artifact.
ALSA includes the external plugin headers and `libasound.so.2` compatibility
link. All Nettle/Hogweed/ALSA/topology DSOs are stripped. Together they resolve
from warm CAS in 429 ms.

The Android AServer PCM plugin is a separate 48 KB artifact with key
`db3ed651e6ed01f435bb4b21006f47c044a4512c9bc2ca170b9e10377aab8838`.
It consumes alsa-lib only through the target sysroot, exports
`_snd_pcm_android_aserver_open`, installs both loader-compatible plugin names
and carries its `/etc/alsa` configuration without embedding libasound.

SDL2's Linux/X11 profile is a 4.0 MB artifact with key
`17f5a037ddeb44d0161893ec9257fe8ad72db8ddebd89b2916a1a4511e756b53`.
It compiles with NDK Clang while `-U__ANDROID__` selects the production Linux
backends, dynamically opens target ALSA/X11 and resolves from warm CAS in
441 ms.

The TLS layer is:

| Element | Key | Checkout | Cold build |
|---|---|---:|---:|
| `openssl` | `07505a51419349d73a9b80f6f07e85608e6a108c39a0b71ac7e87ee02b3dbc60` | 20 MB | 48 s |
| `gnutls` | `737258858f5202cf7ed57dc513d84d21287b2c5673efc5f174abfb71f526ebcf` | 2.7 MB | 53 s |

GnuTLS builds only the LGPL runtime directories and explicitly records
GMP/Nettle/zlib/libc++ runtime dependencies. Its C++ DSO exposed another
shared-staging omission: `libc++_shared.so` was previously present but absent
from depends.conf. OpenSSL/GnuTLS warm together in 428 ms.

The final media/graphics layer is:

| Element | Key | Checkout | Cold package build |
|---|---|---:|---:|
| `gstreamer` | `be5ad64f85ebb12f3143d0706cee5e3b88e6bced71ed711eb8bb949c8d0df474` | 3.6 MB | ~20 s |
| `gst-plugins-base` | `ae24a36f94fe3aafa98ac41fb4f2ea2b9f693b3e824ea6f48fc8e29b286f2feb` | 5.9 MB | ~20 s |
| `mesa-gl` | `2c194a1d1ddd8fda0b4671c25ec9abb030f32852588b1c2b21843b2fc1594060` | 20 MB | 62 s |

GStreamer supplies all Wine-required core/app/audio/video/tag/GL DSOs and warms
in 439 ms. Mesa keeps its API30 Termux profile, pins both patch sets, verifies
Zink, rejects Android stub NEEDED entries and enforces one native TLS ABI; its
warm build takes 466 ms.

## Complete imagefs artifact

`imagefs/staging.bst` composes every package artifact with the merged-usr base
layout. `imagefs/runtime.bst` applies the production runtime prune policy and
reasserts Android system-library pointers. `imagefs/package.bst` creates the
reproducible split `imagefs.txz`.

The locally verified final result is:

- package key: `54af3ec3a6dc46462b1f249205d7d49fa85b2726481c13c806db6c1e90c2878b`
- runtime tree: 51 MB
- `imagefs.txz`: 12 MB
- SHA-256: `a48bdb748d0e9c2b3f12d37ac1e9ef30712cb055af6c36a4c9d2eebf1b6383e0`
- all required Wine/media/graphics dependencies present
- optional font/Vulkan/SDL/X input dependencies present
- all ELF LOAD segments page-congruent
- Mesa Zink marker/megadriver and Android shm exports valid

The XCB/X11 layer splits the old multi-upstream libxcb recipe into separately
cached inputs:

| Element | Key | Checkout |
|---|---|---:|
| `xcb-proto` | `d9c8b63aae41fe54f00af636e10fd389c740ebe6fb87e4b980a06c71341bff3d` | 1.2 MB |
| `libXau` | `c95d150997436bd732ea819607f033740e20676fa75ad80497a61cee55fbeae5` | 100 KB |
| `libXdmcp` | `30eb226dc33a2fc5808e69c2d62413f93f15d5ebe11ac85f490d828be03bb825` | 172 KB |
| `libxcb` | `8a6cacbadde653d8aa5c327ba55088572447dfa1265e2c3c988636019e2fd962` | 13 MB |
| `libX11` | `b815e7afc4dd9417af79db601215a09aae6f6d7ee39c7a7f8f2caa57c2803e8e` | 7.7 MB |

Generated Present headers include `xcb_present_pixmap_synced`. libX11 consumes
libxcb/xtrans/sysvshm from the target sysroot, links
`libandroid-sysvshm.so`, and retains the unversioned `libXcursor.so` dlopen
contract. The complete cached X11 graph resolves in 443 ms.

The first X11 extension layer is fully isolated and stripped:

| Element | Key | Checkout |
|---|---|---:|
| `libXext` | `9abc7ff198fc08c3d38e6f524611164d9111d151d7d3fc162dd5189a1911766d` | 620 KB |
| `libXfixes` | `719f0822f3e5b1a4ca0d9295b96973304ce5420301fa81cc1442c4948a2009c3` | 80 KB |
| `libXrender` | `df7980050abae892e90d465d732b298ae60de7cd635d270284ed962842c75ef5` | 136 KB |

Each artifact has only its own DSO/headers/pkg-config metadata and records
`libX11.so` as a runtime dependency. Their combined warm build takes 429 ms.

The remaining X11 client libraries are:

| Element | Key | Checkout |
|---|---|---:|
| `libXcursor` | `d2c762165c50666a8b7b0449c0f3b8f927cf89eeda0c8625e3d9e6da02316605` | 368 KB |
| `libXi` | `ed1a773c907e393b54248972f41709dddb451da5512895efcde6dfb9f3669b03` | 920 KB |
| `libXxf86vm` | `7bd5f266c88b5ea955367fc361d88a176196943299d7b285ca2c7788f50728ee` | 176 KB |

Their warm build takes 432 ms. Xcursor also exposed an old graph omission:
its configure directly needs xproto/renderproto/fixesproto even though
`depends.conf` relied on those files arriving transitively through shared
staging. The BuildStream element declares xorgproto explicitly.

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
| `vulkan-headers` | `d2f436a369d6a08a9e0ffb541e07785f2c1e36f9ad027a238958b43c84b80927` | 32 MB |
| `libdrm` | `f7d27250d3ca0c7a82b084cdb481087e7064ed9cc55ddc97d0c2c52532c4d38b` | 716 KB |
| `vulkan-loader` | `aca2e17c7b57d69ecb771f8b730fd10a62151930741ca424a69df172bad3b368` | 560 KB |

`libandroid-shmem` pins both the full upstream commit and GitHub archive
SHA-256, exports the expected `libandroid_shm*` ABI, and deliberately omits the
polluting `sys/shm.h`. Vulkan-Headers publishes its headers and registry without
pulling the NDK into its build dependencies. Its host-CMake install also
provides the config metadata consumed by Vulkan-Loader. libdrm and the loader
resolve together from warm CAS in 419 ms.

## Deliberate limits

- All forty production packages are migrated; libxcb's three bundled upstream
  inputs are separate BuildStream artifacts. A complete runtime image and
  `imagefs.txz` are generated, while production `build-all.sh` remains available
  for dual-build comparison.
- NDK's zip does not preserve executable modes or symlinks through the community
  source plugin, so the toolchain element restores both before publishing its
  artifact. This matters for LLVM multicall tools such as `llvm-strip`.
- zstd is linked from its upstream library source set without CMake. This keeps
  host tools declared (shell/coreutils + NDK only) and preserves SONAME at link
  time, but differs from the production CMake recipe.
- GMP build-time generators use the host SDK GCC while target objects use NDK
  Clang. NDK remains strictly on its supported Android target.
