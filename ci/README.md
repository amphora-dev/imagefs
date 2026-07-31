# CI contracts — amphora-dev/imagefs
#
# Layers
#   L0  composite + ci/*.sh     setup-ndk-build, bump-manifest, publish/prune/gate
#   L1  leaf workflow           build-box64.yml  (single upstream product → .wcp)
#   L2  graph workflow          build-imagefs.yml (depends.conf topo → imagefs.txz)
#
# Do NOT split packages/* into per-package Actions jobs. Incremental rebuilds
# stay inside one graph job via content stamps (lib/pkg.sh).
#
# Toolchain
#   graph (imagefs):  ANDROID_API=26  (config.sh) — matches Amphora minSdk / Bionic imagefs
#   leaf  (box64):    ANDROID_API=31  (ci/build-box64-wcp.sh) — WinNative Bionic flags;
#                     runtime NEEDED is only libc/libm/libdl, safe on API 26 devices
#
# Publish
#   Fixed tags `amphora` / `box64` via ci/publish-fixed-release.sh (gh, --clobber).
#   content_manifest pin via .github/actions/bump-manifest → ci/bump-content-manifest.sh.
#   imagefs: skip publish when artifact SHA == published amphora (ci/gate-imagefs-publish.sh).
#   box64:   skip build when tip shortsha already on tag (ci/gate-box64-build.sh),
#            then prune old WCP assets (ci/prune-release-assets.sh).
#
# Triggers
#   imagefs: push/PR with paths-ignore for docs + leaf sources; workflow_dispatch; tags
#   box64:   push on leaf sources only; workflow_dispatch (no schedule)
#
# Scripts
#   install-build-deps.sh / resolve-runner-ndk.sh
#   publish-fixed-release.sh / prune-release-assets.sh
#   verify-imagefs-artifact.sh
#   gate-imagefs-publish.sh / gate-box64-build.sh
#   bump-content-manifest.sh / build-box64-wcp.sh
