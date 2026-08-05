kind: meson

description: |
  GStreamer Base 1.26.1 libraries required by Wine, with GLES2/EGL and ALSA.

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
- filename: wine/x86_64/media/gstreamer.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/text/glib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/audio/alsa-lib.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: gstreamer:gst-plugins-base/gst-plugins-base-1.26.1.tar.xz
  ref: 659553636f84dcf388cad5cf6530e02b0b2d3dc450e76199287ba9db6a6c5226

variables:
  target-triple: x86_64-linux-android35
  ndk-libdir-triple: x86_64-linux-android
  android-cpu: x86_64
  meson-global: "--cross-file=/opt/amphora-sdk/profiles/meson-x86_64-android35.ini --buildtype=release"
  meson-local: >-
    -Dintrospection=disabled
    -Ddoc=disabled
    -Dtests=disabled
    -Dexamples=disabled
    -Dnls=disabled
    -Dorc=disabled
    -Dgl=enabled
    -Dgl_platform=egl
    -Dgl_winsys=egl
    -Dgl_api=gles2
    -Dapp=enabled
    -Dalsa=enabled
    -Dpango=disabled
    -Dcdparanoia=disabled
    -Dlibvisual=disabled
    -Dogg=disabled
    -Dopus=disabled
    -Dtheora=disabled
    -Dvorbis=disabled
    -Dx11=disabled

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libgst*.so*' \
      -exec "$STRIP" {} +
