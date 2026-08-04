kind: compose

description: Complete BuildStream imagefs development sysroot.

depends:
- { filename: imagefs/base-layout.bst, type: build }
- { filename: compress/zlib.bst, type: build }
- { filename: compress/zstd.bst, type: build }
- { filename: compress/brotli.bst, type: build }
- { filename: compress/libpng.bst, type: build }
- { filename: text/libffi.bst, type: build }
- { filename: text/libexpat.bst, type: build }
- { filename: text/pcre2.bst, type: build }
- { filename: text/libiconv.bst, type: build }
- { filename: text/freetype.bst, type: build }
- { filename: text/fontconfig.bst, type: build }
- { filename: text/glib.bst, type: build }
- { filename: android/android-sysvshm.bst, type: build }
- { filename: android/libandroid-shmem.bst, type: build }
- { filename: android/libcxx-shared.bst, type: build }
- { filename: android/android-spawn.bst, type: build }
- { filename: android/android-sysv-semaphore.bst, type: build }
- { filename: x11/xorgproto.bst, type: build }
- { filename: x11/xtrans.bst, type: build }
- { filename: x11/xcb-proto.bst, type: build }
- { filename: x11/libxau.bst, type: build }
- { filename: x11/libxdmcp.bst, type: build }
- { filename: x11/libxcb.bst, type: build }
- { filename: x11/libx11.bst, type: build }
- { filename: x11/libxext.bst, type: build }
- { filename: x11/libxfixes.bst, type: build }
- { filename: x11/libxrender.bst, type: build }
- { filename: x11/libxcursor.bst, type: build }
- { filename: x11/libxi.bst, type: build }
- { filename: x11/libxxf86vm.bst, type: build }
- { filename: x11/libxshmfence.bst, type: build }
- { filename: crypto/gmp.bst, type: build }
- { filename: crypto/nettle.bst, type: build }
- { filename: crypto/openssl.bst, type: build }
- { filename: crypto/gnutls.bst, type: build }
- { filename: audio/alsa-lib.bst, type: build }
- { filename: audio/alsa-android-aserver.bst, type: build }
- { filename: graphics/vulkan-headers.bst, type: build }
- { filename: graphics/libdrm.bst, type: build }
- { filename: graphics/vulkan-loader.bst, type: build }
- { filename: graphics/mesa-gl.bst, type: build }
- { filename: media/sdl2.bst, type: build }
- { filename: media/gstreamer.bst, type: build }
- { filename: media/gst-plugins-base.bst, type: build }

config:
  integrate: false
