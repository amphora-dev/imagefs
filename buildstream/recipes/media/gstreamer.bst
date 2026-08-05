# Platform-agnostic package recipe. Not a BuildStream element.
# Edit this file, then run: python3 buildstream/sync-arch-elements.py
kind: meson

description: |
  GStreamer 1.26.1 core runtime for Wine's winegstreamer bridge.

depends:
- filename: profiles/android-cross-files.bst
  junction: buildstream-sdk.bst
  type: build
  config:
    location: /opt/amphora-sdk/profiles
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: text/glib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: gstreamer:gstreamer/gstreamer-1.26.1.tar.xz
  ref: 30a4c4a5e48345583eb596aa265d0f53c0feb93011d93a6aaa70dd6e3c519dc4

variables:
  meson-local: >-
    -Dintrospection=disabled
    -Ddoc=disabled
    -Dtests=disabled
    -Dexamples=disabled
    -Dbenchmarks=disabled
    -Dtools=disabled
    -Dptp-helper-permissions=none
    -Dgst_debug=false
    -Dnls=disabled

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libgst*.so*' \
      -exec "$STRIP" {} +
