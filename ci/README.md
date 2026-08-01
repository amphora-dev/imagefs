# CI contracts — amphora-dev/imagefs

## Layout

```text
ci/
  setup/     install-build-deps.sh  resolve-runner-ndk.sh
  gate/      imagefs-publish.sh     box64-build.sh  wrapper-build.sh
  publish/   fixed-release.sh       prune-assets.sh  bump-manifest.sh
  verify/    imagefs-artifact.sh    wine-deps.sh     pkg-selftest.sh
  box64/     build-wcp.sh
  wrapper/   build-tzst.sh  push-device.sh
```

## Layers

| Layer | Mechanism | Example |
|-------|-----------|---------|
| L0 | composite + `ci/**` | `setup-ndk-build`, `bump-manifest` |
| L1 leaf | independent workflow | `build-box64.yml` → Release `box64`; `build-wrapper.yml` → Release `wrapper` |
| L2 graph | independent workflow | `build-imagefs.yml` → Release `amphora` |

Do **not** split `packages/*` into per-package Actions jobs. Incremental rebuilds stay inside one graph job via content stamps (`lib/pkg.sh`).

L1 **wrapper** reuses the graph's staging sysroot (subset of packages) but publishes a separate artifact — never packs into `imagefs.txz`.

## Toolchain

- **graph (imagefs):** `ANDROID_API=26` (`config.sh`) — Amphora minSdk / Bionic imagefs
- **leaf (box64):** `ANDROID_API=31` (`ci/box64/build-wcp.sh`) — WinNative Bionic flags; runtime NEEDED is only libc/libm/libdl (safe on API 26 devices)
- **leaf (wrapper):** staging at API 26 + Mesa compile at `WRAPPER_API=30` (`ci/wrapper/build-tzst.sh`) — needs `memfd_create`; links unversioned X11/xcb SONAMEs from staging

## Publish

- Fixed tags `amphora` / `box64` / `wrapper` via `ci/publish/fixed-release.sh` (gh, `--clobber`)
- Pin via `.github/actions/bump-manifest` → `ci/publish/bump-manifest.sh`
- imagefs: skip when artifact SHA == published amphora (`ci/gate/imagefs-publish.sh`)
- box64: skip when tip shortsha already on tag (`ci/gate/box64-build.sh`), then prune (`ci/publish/prune-assets.sh`)
- wrapper: skip when mesa shortsha already on tag (`ci/gate/wrapper-build.sh`), then prune; pins **`content_manifest.components.turnip`** *and* the matching **`runtimeAssets[]`** entry for `graphics_driver/wrapper.tzst` (Amphora installs from the latter via `RuntimeAssetProvisioner`). Same Mesa shortsha with a recipe fix: merge to `main` (push always rebuilds) or `workflow_dispatch` with **force**; Release upload `--clobber`s `wrapper-<shortsha>.tzst`.
- Local device inject (keeps `runtime-assets` + `imagefs` + `contents/adrenotools/wrapper` pins in sync): `bash ci/wrapper/push-device.sh artifacts/wrapper-*.tzst`

## Triggers

Only **positive** `paths:` (no `paths-ignore`). Anything else → **Actions → Run workflow**.

| Workflow | Auto (`push` / `pull_request`) | Manual |
|----------|--------------------------------|--------|
| imagefs | `packages/**` `lib/**` `vendor/winlator-bionic/**` `*.sh` (repo root) + own workflow file | `workflow_dispatch` (`force_publish`) |
| box64 | `ci/box64/**` `vendor/box64-patches/**` + own workflow file | `workflow_dispatch` (`box64_ref` / `force`) |
| wrapper | `ci/wrapper/**` `vendor/wrapper-patches/**` X11/drm/sysvshm/zlib/zstd recipes + own workflow | `workflow_dispatch` (`mesa_ref` / `force`) |

Not on the allow-list (docs, shared `ci/setup|gate|publish|verify` edits that don't touch leaf paths, actions, README): edit freely; rebuild when you need it via dispatch.
No schedule. Fixed Release tags remain `amphora` / `box64` / `wrapper` (not git version tags).
