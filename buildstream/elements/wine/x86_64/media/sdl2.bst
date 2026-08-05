kind: cmake

description: |
  SDL2 2.30.11 for the Winlator Bionic audio/X11 profile.

  SDL intentionally takes its Linux/X11 branches while using the NDK compiler
  and sysroot, matching the production -U__ANDROID__ toolchain profile.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/audio/alsa-lib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: graphics/vulkan-headers.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libx11.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxext.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxfixes.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxrender.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxcursor.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxi.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxxf86vm.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: sdl:release-2.30.11/SDL2-2.30.11.tar.gz
  ref: 8b8d4aef2038533da814965220f88f77d60dfa0f32685f80ead65e501337da7f

variables:
  target-triple: x86_64-linux-android35
  ndk-libdir-triple: x86_64-linux-android
  android-cpu: x86_64
  cmake-local: >-
    -DCMAKE_SYSTEM_NAME=Linux
    -DCMAKE_SYSTEM_PROCESSOR=%{android-cpu}
    -DCMAKE_SYSROOT=%{ndk-toolchain}/sysroot
    -DCMAKE_C_FLAGS=-fPIC\ -O2\ -U__ANDROID__\ -I/opt/android-sysroot/usr/include
    -DCMAKE_CXX_FLAGS=-fPIC\ -O2\ -U__ANDROID__\ -I/opt/android-sysroot/usr/include
    -DBUILD_SHARED_LIBS=ON
    -DSDL_TEST=OFF
    -DSDL_TESTS=OFF
    -DSDL_AUDIO=ON
    -DSDL_ALSA=ON
    -DSDL_ALSA_SHARED=ON
    -DSDL_PULSEAUDIO=OFF
    -DSDL_JACK=OFF
    -DSDL_ESD=OFF
    -DSDL_ARTS=OFF
    -DSDL_NAS=OFF
    -DSDL_SNDIO=OFF
    -DSDL_FUSIONSOUND=OFF
    -DSDL_DISK=ON
    -DSDL_DUMMYAUDIO=ON
    -DSDL_VIDEO=ON
    -DSDL_OPENGL=OFF
    -DSDL_OPENGLES=ON
    -DSDL_EGL=ON
    -DSDL_VULKAN=ON
    -DSDL_X11=ON
    -DSDL_X11_SHARED=ON
    -DSDL_WAYLAND=OFF
    -DSDL_KMSDRM=OFF
    -DSDL_RPI=OFF
    -DSDL_DIRECTFB=OFF
    -DSDL_VIVANTE=OFF
    -DSDL_OFFSCREEN=OFF
    -DSDL_DUMMYVIDEO=ON
    -DSDL_LOADSO=ON
    -DSDL_DLOPEN=ON
    -DSDL_THREADS=ON
    -DSDL_TIMERS=ON
    -DSDL_FILE=ON
    -DSDL_FILESYSTEM=ON
    -DSDL_CPUINFO=ON
    -DSDL_EVENTS=ON
    -DSDL_JOYSTICK=ON
    -DSDL_HIDAPI=OFF
    -DSDL_HAPTIC=ON
    -DSDL_SENSOR=ON
    -DSDL_POWER=ON
    -DSDL_RENDER=ON
    -DSDL_STATIC=OFF
    -DSDL_SHARED=ON
    -DSDL_STATIC_PIC=ON

config:
  strip-commands:
  - |
    find "%{install-root}%{prefix}/lib" -type f -name 'libSDL2*.so*' \
      -exec "$STRIP" {} +
