# Fast Proton Wine development (BuildStream-aligned)

Day-to-day Proton / wineandroid work should stay **drop-in compatible** with CI
WCP, not a divergent NDK knife. Official release pins still come from CI.

## Three layers

```text
1. bst deps once
   ci/wine/dev-bootstrap-sysroot.sh
   → android-x86_64 sysroot, pulse deb, prefixPack, host-freetype
   → writes /home/box/src/bst-artifacts/dev-env.sh

2. persistent configure + make
   same flags as ci/wine/build-proton-wcp.sh via ci/wine/proton-wcp-env.sh
   out-of-tree: /home/box/src/wine-bst-dev-build
   wine-tools:  /home/box/src/wine-bst-dev-wine-tools

3. incremental make → drop-in Proton-*.wcp
   default TARGETS=dlls/wineandroid.drv/all
   overlays into a CI-layout package tree and repacks Amphora-installable WCP
```

```text
CI release / truth (unchanged)
  l1/proton-wine-wcp.bst → build-proton-wcp.sh → Proton-*.wcp
  gate: build-proton-wine
```

Local fast output uses the **same** `profile.json` schema, `bin/` + `lib/wine/`
layout, `prefixPack.txz`, and strip rules. Amphora can install a local
`Proton-*.wcp` the same way as a CI artifact. Do not treat local WCP as a
release pin unless you intentionally promote it through CI.

## Quick start

```bash
# One-time (sysroot may take many hours; script backgrounds bst and logs)
bash ci/wine/dev-bootstrap-sysroot.sh
# watch: tail -f /workspace/bst-sysroot-build.log
# resume anytime: bash ci/wine/dev-bootstrap-sysroot.sh

source /home/box/src/bst-artifacts/dev-env.sh

# First full local build → drop-in WCP (slow once)
MODE=full bash ci/wine/dev-fast-build.sh

# Daily: incremental + repack WCP from persistent package tree
bash ci/wine/dev-fast-build.sh
TARGETS='dlls/wineandroid.drv/all dlls/win32u/all' bash ci/wine/dev-fast-build.sh
```

### Overlay onto an existing CI WCP (no local full install yet)

```bash
source /home/box/src/bst-artifacts/dev-env.sh
# After configure+incremental make at least once:
BASE_WCP=/path/to/Proton-11.0-........wcp bash ci/wine/dev-fast-build.sh
```

This unpacks the CI WCP, replaces rebuilt DLLs at **identical paths**
(e.g. `lib/wine/x86_64-unix/wineandroid.so`), and repacks a new
`Proton-*.wcp` under `/workspace/fast-wineandroid-bst/`.

## Shared configure fragment

| File | Role |
|------|------|
| `ci/wine/proton-wcp-env.sh` | CC/CFLAGS/LDFLAGS/PKG_CONFIG + exact `./configure` args |
| `ci/wine/build-proton-wcp.sh` | CI/BuildStream full WCP (sources the fragment) |
| `ci/wine/dev-fast-build.sh` | Local persistent / incremental / drop-in WCP |
| `ci/wine/dev-bootstrap-sysroot.sh` | One-time bst sysroot + assets |

If CI and local ever disagree on flags, fix **only** `proton-wcp-env.sh`.

## Why `/home/box/src/wine-android-build` is wrong

That tree was configured **without** pulse / vulkan / fontconfig / gstreamer /
the BuildStream android-x86_64 sysroot. Binaries from it are **not** ABI/layout
compatible with CI Proton WCP and previously left CI broken when mistaken for
the fast path. Demote it; do not use it for Amphora drops.

`proton-wine/scripts/fast-wineandroid-build.sh` is similarly demoted — it points
here instead.

## Optional device smoke

After a drop-in WCP is produced, install it like any CI Proton package, or for a
quick file-level check push the overlaid paths from the unpacked package tree.
Device smoke is optional; CI remains the release gate.

## Env vars

| Var | Meaning |
|-----|---------|
| `ANDROID_NDK_HOME` | NDK r29 (box default under `/home/box/src/toolchains/`) |
| `LLVM_MINGW_ROOT` | LLVM-MinGW UCRT |
| `ANDROID_X86_64_SYSROOT` | bst checkout of `wine/sysroot-x86_64.bst` |
| `PULSE_DEV_DEB` | Termux pulseaudio 13.0-1 x86_64 deb (CI-pinned) |
| `PREFIX_PACK` | CI-pinned `prefixPack-11.0-….txz` |
| `HOST_FREETYPE` | Native FreeType for wine-tools |
| `BASE_WCP` / `BASE_WCP_TREE` | Seed package tree for overlay repack |
| `MODE` | `incremental` (default) / `full` / `configure` / `pack` |
| `TARGETS` | make targets (default `dlls/wineandroid.drv/all`) |
| `BUILD_DIR` | default `/home/box/src/wine-bst-dev-build` |
| `OUT_DIR` | default `/workspace/fast-wineandroid-bst` |
