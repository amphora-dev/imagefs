# Wine recc and layered cache

This document records the cache architecture, correctness invariants, measured
performance, and known non-cacheable work for `l1/proton-wine-wcp.bst`.

## Goals

A Proton pin change gives the Wine element a new BuildStream key even when most
source files are unchanged. The cache design must:

- avoid rebuilding unchanged C/C++ objects;
- avoid thousands of fine-grained WAN requests on the normal path;
- retain a durable seed when GitHub's local snapshot expires;
- invalidate objects when source, headers, compiler binaries, or flags change;
- preserve independent, concurrent BuildStream workflows for other products.

## Cache layers

The production workflow is `.github/workflows/build-proton-wine.yml`.

```text
1. Exact BuildStream element artifact available remotely?
   yes -> pull the artifact; do not download or save an Actions snapshot
   no  -> continue

2. GitHub Actions Wine snapshot available?
   yes -> restore cas + actioncache and use a local recc action cache
   no  -> use the Phoenix recc action cache as a seed

3. Run and verify the build.
   A real, successful main build saves the next immutable Actions snapshot.
```

The artifact preflight is read-only and does not download the artifact:

```bash
buildstream/bst artifact show --deps none l1/proton-wine-wcp.bst
```

An exact element hit is the cheapest path because BuildStream transfers only
the requested artifact. The Actions snapshot is restored only when the exact
element is absent.

### GitHub Actions snapshot

One cache entry contains both directories:

```text
~/.cache/buildstream/cas
~/.cache/buildstream/actioncache
```

Action-result metadata refers to output digests in CAS, so the directories must
be restored together. Sources, logs, and artifact refs are intentionally not in
the snapshot.

GitHub cache entries are immutable. Each real main build uses a unique key and
restores the newest prior key by prefix:

```text
wine-recc-local-v3-Linux-<run-id>-<run-attempt>
wine-recc-local-v3-Linux-
```

Only trusted main builds save the canonical lineage. Branch runs can restore a
default-branch snapshot but do not save competing snapshots. Runs on the same
ref are serialized because independently extended snapshots cannot be merged.
The workflow retains the newest two main snapshots.

### Local versus remote action-cache mode

`ci/setup/configure-remote-cache.sh` accepts:

```text
BST_ACTION_CACHE_MODE=remote  # default
BST_ACTION_CACHE_MODE=local
```

Remote mode configures Phoenix as BuildStream's storage and action-cache
upstream. It is used when no GitHub snapshot exists, and fills both Phoenix and
the first local snapshot.

Local mode keeps remote element artifact and source services, but omits the
storage/action-cache upstream used by the recc-facing casd. BuildStream 2.7
otherwise treats that upstream as writable and validates every local action
result over the WAN. A restored snapshot therefore selects local mode.

New actions produced in local mode advance the next GitHub snapshot but do not
immediately update Phoenix. This is safe: stale entries can reduce disaster-
recovery hit rate but cannot match an action with different inputs. A future
snapshot miss uses Phoenix as a seed and updates it with newly compiled results.

## Action-key correctness

### Absolute dependency paths

`RECC_DEPS_GLOBAL_PATHS=1` includes headers and libraries below absolute paths
such as the NDK sysroot, `/opt/android-x86_64-sysroot`, and the extracted Pulse
SDK. Without it, a sysroot update could replay an object created from old
headers.

### Compiler binaries

recc does not include the invoked compiler executable in an action key. The
build script hashes the contents of every wrapped host GCC, NDK clang, and
llvm-mingw clang entry point into:

```text
RECC_REMOTE_PLATFORM_toolchain=<sha256>
```

A compiler update at an unchanged installation path therefore cold-starts the
action cache once instead of replaying objects produced by the old compiler.

### Unix compiler target

The NDK target-prefixed compiler name is not recognized by recc. Unix `CC` and
`CXX` call the real `clang`/`clang++` with
`--target=x86_64-linux-android30`. The target is part of `CC` rather than only
`CFLAGS`, because Wine link recipes use `$(CC) ... $(LDFLAGS)` without
`$(CFLAGS)`.

### PE compiler wrappers

Wine invokes bare llvm-mingw `clang` for PE objects. The build script inserts
absolute-path shims that invoke recc only for the llvm-mingw compiler entries;
NDK and host compilers retain their own explicit wrappers.

## Interpreting the summary

A real build prints a workflow annotation and job summary such as:

```text
recc actions: hit=8824 miss=89 updated=0 not_compiler=3421
```

- `hit`: successful action-cache lookups.
- `miss`: cache-only actions executed locally.
- `updated`: successful local results added to the active action cache.
- `not_compiler`: wrapped invocations intentionally passed through locally.

The stable 89 misses are configure probes that exit nonzero and are not
uploaded. `not_compiler` does not mean thousands of normal C/C++ source files
missed the cache.

## `not_compiler` classification

A benchmark wrapper recorded argv and elapsed time for every recc invocation,
then correlated the child PID with recc's per-process log. The classification
run was [36398121271](https://github.com/amphora-dev/imagefs/actions/runs/36398121271).

| Category | Count | Aggregate direct execution | Approx. wall ceiling at `-j4` |
|---|---:|---:|---:|
| Link commands | 1,703 | 59–83 s | 15–21 s |
| Rejected `-c` commands | 1,604 | 35–51 s | 9–13 s |
| Configure or other | 94 | about 3 s | under 1 s |
| Preprocessor | 12 | about 0.2 s | negligible |
| Compiler metadata query | 8 | about 0.1 s | negligible |

The 1,604 rejected compile commands are:

| Shape | Count | Explanation |
|---|---:|---|
| llvm-mingw generated `.spec.s` | 1,496 | recc 1.4.15 recognizes C/C++ source suffixes, not `.s`/`.S` |
| host GCC conftest | 58 | configure probes |
| Android clang conftest | 46 | configure probes |
| llvm-mingw conftest | 4 | configure probes |

The generated assembly command resembles:

```text
clang -target i686-windows -xassembler -c \
  -o tmp.../module.spec.o tmp.../module.spec.s
```

These commands also use generated temporary paths. Adding assembly support to
recc without stabilizing those paths would not guarantee reusable action keys.
All 3,421 passthroughs together can account for only about 29–34 seconds of
wall time at four jobs.

## Why link caching is disabled

recc supports linker actions with `RECC_LINK=1`, but each link would first:

1. execute the compiler driver with `-###` to recover the real linker command;
2. resolve direct and indirect libraries;
3. construct a Merkle tree and action;
4. query the action cache and materialize larger outputs.

The observed links average only about 35–48 ms each. Link dependency discovery
is likely to cost as much as direct local linking, while increasing snapshot
size and the stale-input correctness surface. The maximum warm-cache saving is
only about 15–21 seconds, so link caching remains disabled.

Assembly caching is also disabled: its maximum observed saving is about
9–13 seconds, and it requires both recc assembly support and stable generated
paths.

## Performance evidence

Times below are Wine sandbox `Running commands` unless noted.

| Scenario | Result | Time |
|---|---|---:|
| No recc, current control | full direct compile | 21:05 |
| Phoenix action cache, east-US runner | 8,824 hits / 89 misses | 13:28 |
| Phoenix action cache, west-US runner | 8,824 hits / 89 misses | 6:30–6:52 |
| GitHub snapshot, local action cache | 8,824 hits / 89 misses | 6:31–6:35 |
| New toolchain fingerprint, cold cache | 0 hits / 8,913 misses | 32:28 |
| Exact BuildStream element artifact | snapshot skipped; one artifact pulled | about 4–7 s |

Controlled workflow runs:

- no recc: [36372313405](https://github.com/amphora-dev/imagefs/actions/runs/36372313405)
- Phoenix warm, east: [36370900473](https://github.com/amphora-dev/imagefs/actions/runs/36370900473)
- Phoenix warm, west with phase metrics: [36380197485](https://github.com/amphora-dev/imagefs/actions/runs/36380197485)
- toolchain-fingerprint cold start: [36364266636](https://github.com/amphora-dev/imagefs/actions/runs/36364266636)
- first production `v3` seed: [36392305835](https://github.com/amphora-dev/imagefs/actions/runs/36392305835)
- production local snapshot: [36393936433](https://github.com/amphora-dev/imagefs/actions/runs/36393936433)
- production exact-artifact path: [36392020710](https://github.com/amphora-dev/imagefs/actions/runs/36392020710)

The production snapshot is about 1.46 GiB compressed. It restored in 18–24
seconds and saved in 20–33 seconds. Two retained snapshots use about 2.92 GiB
of the repository cache quota.

## Remaining build phases

The instrumented phase run was
[36399441452](https://github.com/amphora-dev/imagefs/actions/runs/36399441452).
Tracing itself adds overhead, so use the phase ordering rather than comparing
its total directly with production.

| Phase | Measured time |
|---|---:|
| Main `make` | 182.5 s |
| WCP tar + `zstd -19` | 41.7 s |
| Host wine-tools configure/build | 19.8 s |
| Target configure | 17.0 s |
| Package tree copy and strip | 15.7 s |
| Install | 5.4 s |
| Autogen | 5.2 s |

The main `make` phase still performs dependency discovery before each recc
lookup. That work, generated assembly, short local links, make scheduling, and
generated-code steps form the remaining cache-hit floor.

## Optimization decisions

Not currently recommended:

- **Full BuildStream directory in Actions cache:** previously produced 3.5–4.5
  GiB archives and included sources, logs, and refs not needed for recc hits.
- **Link caching:** at most tens of seconds of theoretical benefit with more
  dependency and correctness complexity.
- **Assembly caching:** small benefit and unstable generated paths.
- **Autoconf cache:** small measured configure time and substantial stale-probe
  risk across source/toolchain changes.
- **Persistent build tree:** large, fragile, and redundant with exact element
  artifacts plus action caching.
- **Static make oversubscription:** cache misses would run too many clang
  processes for the available CPUs.

Candidates for separate benchmarks:

1. Compare WCP `zstd` levels below `-19`; archive creation is about 42 seconds.
2. Evaluate a safe dependency-manifest cache, `clang-scan-deps`, or ccache
   direct mode. This targets the dependency scan paid before every recc hit and
   has more potential than caching links or generated assembly.

## Operations

Inspect the current snapshots:

```bash
gh cache list \
  --ref refs/heads/main \
  --key wine-recc-local-v3 \
  --json key,sizeInBytes,createdAt,lastAccessedAt
```

A non-forced manual dispatch exits before BuildStream setup when the current
Proton asset is already published:

```bash
gh workflow run build-proton-wine.yml --ref main -f force=false
```

A forced dispatch still checks the exact element artifact before deciding
whether the Actions snapshot is needed:

```bash
gh workflow run build-proton-wine.yml --ref main -f force=true
```

The Phoenix hostname must remain the origin record `cas.arm.512.pub`. The
Cloudflare-proxied `cas-arm.512.pub` has stalled long gRPC streams in prior
runs.

## External behavior references

- [GitHub dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
- [Managing GitHub Actions caches](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches)
- [actions/cache](https://github.com/actions/cache)
