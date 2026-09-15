# Proton Wine CI + local fast path

| Script | Role |
|--------|------|
| `build-proton-wcp.sh` | CI/BuildStream full WCP (release truth) |
| `proton-wcp-env.sh` | Shared configure/env/packaging fragment |
| `dev-bootstrap-sysroot.sh` | One-time bst sysroot + pulse/prefixPack |
| `dev-fast-build.sh` | Persistent incremental → drop-in `Proton-*.wcp` |

See [`docs/DEV-FAST-WINE.md`](../../docs/DEV-FAST-WINE.md).
