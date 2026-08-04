kind: compose

description: Self-built x86_64 Android API35 development sysroot for Proton Wine.

depends:
- { filename: wine/x86_64/compress/zlib.bst, type: build }
- { filename: wine/x86_64/compress/brotli.bst, type: build }
- { filename: wine/x86_64/compress/libpng.bst, type: build }
- { filename: wine/x86_64/text/libffi.bst, type: build }
- { filename: wine/x86_64/text/libexpat.bst, type: build }
- { filename: wine/x86_64/text/pcre2.bst, type: build }
- { filename: wine/x86_64/text/libiconv.bst, type: build }
- { filename: wine/x86_64/text/freetype.bst, type: build }
- { filename: wine/x86_64/text/fontconfig.bst, type: build }
- { filename: wine/x86_64/text/glib.bst, type: build }
- { filename: wine/x86_64/crypto/gmp.bst, type: build }
- { filename: wine/x86_64/crypto/nettle.bst, type: build }
- { filename: wine/x86_64/crypto/gnutls.bst, type: build }
- { filename: wine/x86_64/audio/alsa-lib.bst, type: build }
- { filename: wine/x86_64/android/android-sysvshm.bst, type: build }
- { filename: wine/x86_64/android/libcxx-shared.bst, type: build }
- { filename: wine/x86_64/x11/xorgproto.bst, type: build }
- { filename: wine/x86_64/x11/xtrans.bst, type: build }
- { filename: wine/x86_64/x11/xcb-proto.bst, type: build }
- { filename: wine/x86_64/x11/libxau.bst, type: build }
- { filename: wine/x86_64/x11/libxdmcp.bst, type: build }
- { filename: wine/x86_64/x11/libxcb.bst, type: build }
- { filename: wine/x86_64/x11/libx11.bst, type: build }
- { filename: wine/x86_64/x11/libxext.bst, type: build }
- { filename: wine/x86_64/x11/libxfixes.bst, type: build }
- { filename: wine/x86_64/x11/libxrender.bst, type: build }
- { filename: wine/x86_64/x11/libxcursor.bst, type: build }
- { filename: wine/x86_64/x11/libxi.bst, type: build }
- { filename: wine/x86_64/x11/libxxf86vm.bst, type: build }
- { filename: wine/x86_64/graphics/vulkan-headers.bst, type: build }
- { filename: wine/x86_64/graphics/libdrm.bst, type: build }
- { filename: wine/x86_64/media/sdl2.bst, type: build }
- { filename: wine/x86_64/media/gstreamer.bst, type: build }
- { filename: wine/x86_64/media/gst-plugins-base.bst, type: build }

config:
  integrate: false
