# BuildStream CAS export / restore

Goal: seed a sticky local `~/.cache/buildstream` from the same Actions cache
key used by `build-proton-wine`, so a resident machine can do incremental Wine
builds without paying for a cold GitHub runner every time.

Release packaging still goes through `build-proton-wine` (gate unchanged).

## Actions → release

1. After a successful `build-proton-wine` run (warm cache), dispatch
   **export-buildstream-cache**.
2. Workflow restores the identical cache key, packs CAS, uploads an artifact,
   and refreshes fixed tag **wine-dev-bst-cache**.
3. The CAS is large (~3.5GiB zstd). GitHub Release assets must be **&lt;2GiB**,
   so `pack-buildstream-cas.sh` streams into `*.tar.zst.partNN` pieces plus
   `*.parts` and `*.tar.zst.sha256sum`.

Scripts live under `ci/cache/` so they do **not** match `ci/wine/**` path
filters and will not alone re-trigger a full Wine rebuild.

## Local restore

```bash
# Preview
bash ci/cache/restore-buildstream-cas.sh --dry-run

# First seed (or replace)
bash ci/cache/restore-buildstream-cas.sh --force

# Then build incrementally as usual
bash ci/setup/install-buildstream.sh
buildstream/bst build l1/proton-wine-wcp.bst
```

Single-file / offline:

```bash
bash ci/cache/restore-buildstream-cas.sh \
  --force \
  --url file:///path/to/buildstream-cas-proton-wine.tar.zst
```

## Keys

Must stay aligned with `.github/workflows/build-proton-wine.yml`:

`buildstream-proton-wine-v1-${{ runner.os }}-${{ hashFiles('project.conf', 'buildstream/elements/buildstream-sdk.bst', 'buildstream/elements/l1/proton-wine-wcp.bst', 'buildstream/elements/wine/**', 'ci/wine/**') }}`
