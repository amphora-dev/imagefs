# CI contracts — amphora-dev/imagefs

## Layout

```text
ci/
  setup/     install-build-deps.sh  resolve-runner-ndk.sh
  gate/      imagefs-publish.sh     box64-build.sh
  publish/   fixed-release.sh       prune-assets.sh  bump-manifest.sh
  verify/    imagefs-artifact.sh    wine-deps.sh     pkg-selftest.sh
  box64/     build-wcp.sh
```

## Layers

| Layer | Mechanism | Example |
|-------|-----------|---------|
| L0 | composite + `ci/**` | `setup-ndk-build`, `bump-manifest` |
| L1 leaf | independent workflow | `build-box64.yml` → Release `box64` |
| L2 graph | independent workflow | `build-imagefs.yml` → Release `amphora` |

Do **not** split `packages/*` into per-package Actions jobs. Incremental rebuilds stay inside one graph job via content stamps (`lib/pkg.sh`).

## Toolchain

- **graph (imagefs):** `ANDROID_API=26` (`config.sh`) — Amphora minSdk / Bionic imagefs
- **leaf (box64):** `ANDROID_API=31` (`ci/box64/build-wcp.sh`) — WinNative Bionic flags; runtime NEEDED is only libc/libm/libdl (safe on API 26 devices)

## Publish

- Fixed tags `amphora` / `box64` via `ci/publish/fixed-release.sh` (gh, `--clobber`)
- Pin via `.github/actions/bump-manifest` → `ci/publish/bump-manifest.sh`
- imagefs: skip when artifact SHA == published amphora (`ci/gate/imagefs-publish.sh`)
- box64: skip when tip shortsha already on tag (`ci/gate/box64-build.sh`), then prune (`ci/publish/prune-assets.sh`)

## Triggers

- **imagefs:** push/PR with paths-ignore for docs + leaf sources; `workflow_dispatch`; tags
- **box64:** push on leaf sources only; `workflow_dispatch` (no schedule)
