kind: manual

description: |
  Android NDK r29 as a BuildStream artifact.

  The community zip source normalizes file modes, so the install step restores
  execute bits for host tools. Pinning the zip SHA-256 makes the 783 MB toolchain
  an immutable input shared by all Android package artifacts.

depends:
- filename: base/ubuntu.bst
  type: build

sources:
- kind: zip
  url: google-android:android-ndk-r29-linux.zip
  ref: 4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf
  base-dir: android-ndk-r29

config:
  install-commands:
  - |
    set -eu
    mkdir -p "%{install-root}%{ndk-root}"
    cp -a . "%{install-root}%{ndk-root}/"
    bindir="%{install-root}%{ndk-toolchain}/bin"

    # The zip source exposes Unix symlinks as tiny regular files containing the
    # link target. Recreate them so multicall LLVM tools see the right argv[0]
    # (llvm-strip -> llvm-objcopy is semantically different from invoking
    # llvm-objcopy directly).
    for candidate in "$bindir"/*; do
      [ -f "$candidate" ] || continue
      [ "$(wc -c < "$candidate")" -lt 128 ] || continue
      target="$(cat "$candidate")"
      case "$target" in
        *[!A-Za-z0-9._+-]*|"") continue ;;
      esac
      [ -e "$bindir/$target" ] || continue
      rm "$candidate"
      ln -s "$target" "$candidate"
    done

    find "$bindir" -type f -exec chmod 0755 {} +
    test -L "$bindir/clang"
    test -L "$bindir/llvm-strip"
    test -x "%{install-root}%{ndk-toolchain}/bin/%{target-triple}-clang"
