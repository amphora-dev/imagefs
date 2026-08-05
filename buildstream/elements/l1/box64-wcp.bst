kind: cmake

description: |
  Box64 WCP from ptitSeb/box64 main at
  0db8df7757b523e41cf31b6204c47d22b8fb4f08.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build

sources:
- kind: git
  url: box64:box64.git
  ref: 0db8df7757b523e41cf31b6204c47d22b8fb4f08
  track: main
  checkout-submodules: false
- kind: local
  path: vendor/box64-patches/pipetto-controller-fix.patch
  directory: .bst/patches

variables:
  notparallel: true
  cmake-local: >-
    -DCMAKE_C_COMPILER=%{ndk-toolchain}/bin/aarch64-linux-android30-clang
    -DCMAKE_C_FLAGS=-Wno-int-conversion\ -Wno-incompatible-pointer-types\ -Wno-implicit-function-declaration
    -DANDROID=1
    -DBIONIC=1
    -DARM_DYNAREC=1
    -DBAD_SIGNAL=1
    -DTERMUX=0
    -DHAVE_TRACE=0
    -DNOGIT=ON

config:
  configure-commands:
  - |
    patch -p1 < .bst/patches/pipetto-controller-fix.patch
  - |
    %{cmake}
  install-commands:
  - |
    set -eu
    binary="%{build-root}/%{build-dir}/box64"
    "$STRIP" "$binary"
    interpreter="$(readelf -l "$binary" |
      awk -F: '/interpreter/{gsub(/[\[\] ]/,"",$2); print $2}')"
    test "$interpreter" = /system/bin/linker64

    major="$(awk '/#define BOX64_MAJOR/{print $3}' src/box64version.h)"
    minor="$(awk '/#define BOX64_MINOR/{print $3}' src/box64version.h)"
    revision="$(awk '/#define BOX64_REVISION/{print $3}' src/box64version.h)"
    commit_full=0db8df7757b523e41cf31b6204c47d22b8fb4f08
    commit_short=0db8df775
    full_version="$major.$minor.$revision-$commit_short"
    wcp_name="Box64-$full_version.wcp"
    work=/tmp/box64-wcp
    out="%{install-root}/artifacts"
    rm -rf "$work"
    mkdir -p "$work" "$out"
    install -m 0755 "$binary" "$work/box64"
    cat > "$work/profile.json" <<EOF
    {
      "type": "Box64",
      "versionName": "$full_version",
      "versionCode": 0,
      "description": "Box64-$full_version",
      "files": [
        {
          "source": "box64",
          "target": "\${bindir}/box64"
        }
      ]
    }
    EOF
    tar --owner=0 --group=0 --numeric-owner \
      --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name \
      -I 'xz -T1' -cf "$out/$wcp_name" -C "$work" box64 profile.json
    (
      cd "$out"
      sha256sum "$wcp_name" > "$wcp_name.sha256sum"
    )
    size="$(stat -c%s "$out/$wcp_name")"
    sha="$(awk '{print $1}' "$out/$wcp_name.sha256sum")"
    cat > "$out/box64-wcp.env" <<EOF
    FULL_VERSION=$full_version
    COMMIT_FULL=$commit_full
    COMMIT_SHORT=$commit_short
    WCP_NAME=$wcp_name
    SHA256=$sha
    SIZE=$size
    EOF
  strip-commands: []
