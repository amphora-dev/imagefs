kind: meson

description: |
  Mesa 25.3.6 desktop GL/EGL with Zink + softpipe DRI frontends.

  Wine x86_64 API35 Mesa GL/EGL development stack. Fails closed on
  driver/TLS/stub ABI drift.

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
- filename: wine/x86_64/compress/zlib.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/compress/zstd.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/graphics/libdrm.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: x11/xorgproto.bst
  type: build
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/x11/libx11.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/x11/libxext.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/x11/libxfixes.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/x11/libxxf86vm.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/x11/libxshmfence.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/text/libexpat.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/android/libandroid-shmem.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: wine/x86_64/android/libcxx-shared.bst
  type: all
  config: { location: /opt/android-sysroot }
- filename: graphics/vulkan-headers.bst
  type: build
  config: { location: /opt/android-sysroot }

sources:
- kind: tar
  url: mesa:mesa-25.3.6.tar.xz
  ref: 59217efeac3b64e7ced958324b9db7494f1e0741aeb22d780276514cc1b8f206
- kind: local
  path: vendor/wrapper-patches/0003-amphora-not-detect-os-android.patch
  directory: .bst/wrapper-patches
- kind: local
  path: vendor/mesa-gl-patches
  directory: .bst/mesa-patches

variables:
  target-triple: x86_64-linux-android35
  ndk-libdir-triple: x86_64-linux-android
  android-cpu: x86_64
  meson-global: >-
    --cross-file=/opt/amphora-sdk/profiles/meson-mesa-x86_64-api35.ini
    --native-file=/opt/amphora-sdk/profiles/meson-native-x86_64.ini
    --buildtype=release
  meson-local: >-
    -Db_ndebug=true
    -Dplatforms=x11
    -Dglx=dri
    -Degl=enabled
    -Dopengl=true
    -Dgles1=disabled
    -Dgles2=disabled
    -Dgbm=disabled
    -Dgallium-drivers=zink,softpipe
    -Dvulkan-drivers=
    -Dllvm=disabled
    -Dshared-llvm=disabled
    -Dglvnd=disabled
    -Dxmlconfig=enabled
    -Dzstd=enabled
    -Dvideo-codecs=
    -Dandroid-libbacktrace=disabled
    -Dxlib-lease=disabled
    -Dvalgrind=disabled
    -Dbuild-tests=false

environment:
  PKG_CONFIG_PATH: ""
  PKG_CONFIG_SYSROOT_DIR: /opt/android-sysroot
  PKG_CONFIG_LIBDIR: "/opt/android-sysroot/usr/lib/pkgconfig:/opt/android-sysroot/usr/share/pkgconfig"

config:
  configure-commands:
  - |
    patch -p1 < .bst/wrapper-patches/0003-amphora-not-detect-os-android.patch
    for patch_file in .bst/mesa-patches/*.patch; do
      patch -p1 < "$patch_file"
    done
  - |
    %{meson}
  strip-commands:
  - |
    set -eu
    libdir="%{install-root}%{prefix}/lib"
    gl_real=
    egl_real=
    gallium=
    for candidate in "$libdir"/libGL.so.1.*; do
      [ -f "$candidate" ] && [ ! -L "$candidate" ] && gl_real="$candidate"
    done
    for candidate in "$libdir"/libEGL.so.1.*; do
      [ -f "$candidate" ] && [ ! -L "$candidate" ] && egl_real="$candidate"
    done
    for candidate in "$libdir"/libgallium*.so; do
      [ -f "$candidate" ] && gallium="$candidate"
    done
    test -n "$gl_real"
    test -n "$egl_real"
    test -n "$gallium"
    "$STRIP" --strip-unneeded "$gl_real" "$egl_real" "$gallium"
    ln -sfn "$(basename "$gl_real")" "$libdir/libGL.so.1"
    ln -sfn "$(basename "$egl_real")" "$libdir/libEGL.so.1"

    for dso in "$gl_real" "$egl_real" "$gallium"; do
      needed="$(readelf -dW "$dso" | awk -F'[][]' '/NEEDED/{print $2}')"
      for stub in liblog.so libcutils.so libsync.so libhardware.so libnativewindow.so; do
        if printf '%s\n' "$needed" | grep -qx "$stub"; then
          echo "$(basename "$dso") unexpectedly needs $stub" >&2
          exit 1
        fi
      done
      if readelf -Ws "$dso" | grep -qE '__emutls_(get_address|v\.)'; then
        echo "$(basename "$dso") contains emulated TLS" >&2
        exit 1
      fi
    done

    grep -q 'ZINK:' "$gallium"
    for frontend in "$gl_real" "$egl_real"; do
      readelf -Ws "$frontend" |
        awk '$4 == "TLS" && $7 == "UND" && $8 == "_mesa_glapi_tls_Dispatch" { found=1 } END { exit !found }'
    done
    readelf -Ws "$gallium" |
      awk '$4 == "TLS" && $7 != "UND" && $8 == "_mesa_glapi_tls_Dispatch" { found=1 } END { exit !found }'
    : > "$libdir/.libgl-zink"
