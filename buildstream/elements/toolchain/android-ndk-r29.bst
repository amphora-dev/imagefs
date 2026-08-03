kind: manual

description: |
  Android NDK r29 as a BuildStream artifact.

  The community zip source normalizes file modes, so the install step restores
  execute bits for host tools. Pinning the zip SHA-256 makes the 783 MB toolchain
  an immutable input shared by all Android package artifacts.

depends:
- base/ubuntu.bst

sources:
- kind: zip
  url: google-android:android-ndk-r29-linux.zip
  ref: 4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf
  base-dir: android-ndk-r29

config:
  install-commands:
  - |
    mkdir -p "%{install-root}%{ndk-root}"
    cp -a . "%{install-root}%{ndk-root}/"
    find "%{install-root}%{ndk-toolchain}/bin" -type f -exec chmod 0755 {} +
    test -x "%{install-root}%{ndk-toolchain}/bin/%{target-triple}-clang"
