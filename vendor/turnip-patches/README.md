# Turnip patches (Mesa 26.2.6, Android KGSL build)

Applied in order by `ci/turnip/build-turnip.sh` (element `buildstream/elements/l1/turnip.bst`)
onto the upstream `mesa-26.2.6.tar.xz` release tarball with
`patch -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch`. Any failure stops the build.
The script hashes itself plus every `*.patch` here into the asset name
(`turnip-<mesa version>-s<s8>.zip`), so editing a patch makes a new asset.

`0001`-`0011` are Mesa MR 44838 (Danylo Piliaiev), the upstream `git format-patch`
output of `b889ab52c6b..2e30bbd3b7d`, bytes unchanged. They touch only
`src/freedreno/vulkan/tu_knl_kgsl.cc` and apply at a -48 line offset with no fuzz.
First release that has them: `mesa-26.3.0-rc2`; they carry no `mesa-stable` tag, so
26.2.x never gets them. Drop `0001`-`0011` when the pinned tarball contains them.

| Patch | Upstream | Why |
|-------|----------|-----|
| `0001-tu-kgsl-Prevent-overflow-in-kgsl_queue_wait_fence.patch` | `b889ab52c6b` | MR 44838 |
| `0002-tu-kgsl-Distinguish-timestamp-and-sync-wait-errors.patch` | `b7ad24ada3e` | MR 44838 |
| `0003-tu-kgsl-Prevent-indefinite-wait-times-for-0-timeout.patch` | `e984ef294ea` | MR 44838: a zero-timeout poll waited forever, so the timeline GC lock-stepped CPU and GPU (vkd3d slowdowns on A7xx). |
| `0004-tu-kgsl-Always-round-up-the-wait-timeout.patch` | `6cb65e61325` | MR 44838 |
| `0005-tu-kgsl-Prevent-OOB-array-access-in-kgsl_syncobj_for.patch` | `9a6269f65f4` | MR 44838 |
| `0006-tu-kgsl-Select-the-earliest-timestamp-for-wait-any.patch` | `59c291f6403` | MR 44838 |
| `0007-tu-kgsl-Correctly-interpret-poll-result-in-wait_any.patch` | `9dea49d1334` | MR 44838 |
| `0008-tu-kgsl-Propagate-syncobj-export-failures.patch` | `11b1a235aca` | MR 44838 |
| `0009-tu-kgsl-Handle-syncobj-errors-in-queue_submit.patch` | `7e0a2b88e74` | MR 44838 |
| `0010-tu-kgsl-Correctly-merge-timestamps-and-sync-files.patch` | `1da50a1b940` | MR 44838: merging a timestamp syncobj with a sync-file syncobj dereferenced NULL. Amphora's acquire semaphores are SYNC_FD imports. |
| `0011-tu-kgsl-Handle-FD-only-waits-in-wait_any.patch` | `2e30bbd3b7d` | MR 44838 |
| `0012-u_gralloc-fallback-detect-qcom-ubwc-without-gmsm.patch` | none (Amphora) | Newer Qualcomm gralloc no longer writes the `gmsm` magic, so the u_gralloc fallback never reads the UBWC bit and returns `DRM_FORMAT_MOD_INVALID`. Amphora's AHB import swapchain (usage 0xB00, `tiling=OPTIMAL`) resolves its layout through that fallback (no IMapper in `android-stub` builds), and `tu_image_init` then picks tiled/UBWC for a linear buffer. Taken from WinNative-Emu/Drivers `fix_gralloc_flushall.py` (WN-Turnip 1.06-b, the previous passing baseline). Not upstream in 26.3.0-rc3 or main. |

The build script checks these markers after patching and fails if one is wrong:
`kgsl_poll_timestamp` (0003) and
`ret.state == KGSL_SYNCOBJ_STATE_TS && sync->state == KGSL_SYNCOBJ_STATE_TS` (0010) in
`tu_knl_kgsl.cc`; `data[hnd->handle->numFds] == gmsm` absent and `numInts >= 2`
present in `u_gralloc_fallback.c` (0012).

Not adopted (see the Turnip survey): faking 16-bit storage on A630, PWR_MAX
forcing, GPU id spoofing, disabling 64-bit image atomics.
