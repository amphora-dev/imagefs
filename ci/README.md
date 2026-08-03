# CI contracts — amphora-dev/imagefs

## Layout

```text
ci/
  upstream.sh              # L1 leaf upstream repos + default refs (single source)
  setup/     install-build-deps.sh  resolve-runner-ndk.sh
  gate/      imagefs-publish.sh     box64-build.sh  wrapper-build.sh
  publish/   fixed-release.sh       prune-assets.sh  bump-manifest.sh
  verify/    imagefs-artifact.sh    wine-deps.sh     pkg-selftest.sh
  box64/     build-wcp.sh
  wrapper/   build-tzst.sh  push-device.sh
```

A gate and its builder must clone the **same** repo and ref, otherwise the gate
decides "already published" from a sha the builder never produces. Both read
[`ci/upstream.sh`](upstream.sh); NDK discovery is likewise shared via
[`lib/ndk.sh`](../lib/ndk.sh).

## Layers

| Layer | Mechanism | Example |
|-------|-----------|---------|
| L0 | composite + `ci/**` | `setup-ndk-build`, `bump-manifest` |
| L1 leaf | independent workflow | `build-box64.yml` → Release `box64`; `build-wrapper.yml` → Release `wrapper` |
| L2 graph | independent workflow | `build-imagefs.yml` → Release `amphora` |

Do **not** split `packages/*` into per-package Actions jobs. Incremental rebuilds stay inside one graph job via content stamps (`lib/pkg.sh`).

L1 **wrapper** reuses the graph's staging sysroot (subset of packages) but publishes a separate artifact — never packs into `imagefs.txz`.

Mesa is built **twice, on purpose**: the Vulkan ICD (`libvulkan_wrapper.so`, L1 leaf, Pipetto fork) ships in `wrapper.tzst` because the Vulkan driver is a real swap point; desktop GL (`libGL.so.1`, package `mesa-gl`, upstream release tarball, zink + xlib GLX) rides inside `imagefs.txz` because nothing swaps libGL. Both use the same Termux link profile (`system=linux` + `-D__TERMUX__`), which is what keeps `liblog`/`libcutils`/`libsync` out of `DT_NEEDED`. This replaces WinNative's prebuilt `graphics_driver/extra_libs.tzst`, which is now abolished.

## Toolchain

- **graph (imagefs):** `ANDROID_API=26` (`config.sh`) — Amphora minSdk / Bionic imagefs
- **leaf (box64):** `ANDROID_API=31` (`ci/box64/build-wcp.sh`) — WinNative Bionic flags; runtime NEEDED is only libc/libm/libdl (safe on API 26 devices)
- **leaf (wrapper):** staging at API 26 + Mesa compile at `WRAPPER_API=30` (`ci/wrapper/build-tzst.sh`) — needs `memfd_create`; links unversioned X11/xcb SONAMEs from staging

## Publish

- Fixed tags `amphora` / `box64` / `wrapper` via `ci/publish/fixed-release.sh` (gh, `--clobber`)
- Pin via `.github/actions/bump-manifest` → `ci/publish/bump-manifest.sh`
- imagefs: skip when artifact SHA == published amphora (`ci/gate/imagefs-publish.sh`)
- box64: skip when tip shortsha already on tag (`ci/gate/box64-build.sh`), then prune (`ci/publish/prune-assets.sh`)
- wrapper: skip when mesa shortsha already on tag (`ci/gate/wrapper-build.sh`), then prune; pins the **`runtimeAssets[]`** entry for `graphics_driver/wrapper.tzst` — that is the one Amphora installs from, via `RuntimeAssetProvisioner`. (It used to be mirrored into `components.turnip` too; nothing resolved that copy and the two drifted, so it is gone.) Same Mesa shortsha with a recipe fix: merge to `main` (push always rebuilds) or `workflow_dispatch` with **force**; Release upload `--clobber`s `wrapper-<shortsha>.tzst`.
- Local device inject (keeps `runtime-assets` + `imagefs` + `contents/adrenotools/wrapper` pins in sync, and arms Amphora `.local-override`): `bash ci/wrapper/push-device.sh artifacts/wrapper-*.tzst`
- Clear override (resume remote pin): `bash ci/wrapper/push-device.sh --clear`

## Triggers

Only **positive** `paths:` (no `paths-ignore`). Anything else → **Actions → Run workflow**.

| Workflow | Auto (`push` / `pull_request`) | Manual |
|----------|--------------------------------|--------|
| imagefs | `packages/**` `lib/**` `vendor/{winlator-bionic,mesa-gl-patches,wrapper-patches,zstd-patches}/**` `*.sh` (repo root) + own workflow file | `workflow_dispatch` (`force_publish`) |
| box64 | `ci/box64/**` `vendor/box64-patches/**` + own workflow file | `workflow_dispatch` (`box64_ref` / `force`) |
| wrapper | `ci/wrapper/**` `vendor/wrapper-patches/**` (+ zstd-patches via staging recipes) X11/drm/sysvshm/zlib/zstd + own workflow | `workflow_dispatch` (`mesa_ref` / `force`) |

Not on the allow-list (docs, shared `ci/setup|gate|publish|verify` edits that don't touch leaf paths, actions, README): edit freely; rebuild when you need it via dispatch.
No schedule. Fixed Release tags remain `amphora` / `box64` / `wrapper` (not git version tags).
