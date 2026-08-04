kind: manual

description: |
  NDK r29 libc++ shared runtime for aarch64 Android.

  This element demonstrates consuming a file from the NDK build dependency
  while publishing only the target runtime library.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

config:
  install-commands:
  - |
    set -eu
    source="%{ndk-toolchain}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
    destination="%{install-root}%{prefix}/lib/libc++_shared.so"
    test -f "$source"
    mkdir -p "$(dirname "$destination")"
    install -m 0755 "$source" "$destination"
    "$STRIP" "$destination"

  strip-commands: []
