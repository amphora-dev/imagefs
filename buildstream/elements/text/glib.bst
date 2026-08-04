kind: meson

description: |
  GLib 2.82.4 for Android/Bionic.

  Cross-only gnulib frexp/frexpl runtime probes are forced to their known-good
  Bionic result, matching the production MiceWine-derived recipe.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: toolchain/android-ndk-r29.bst
  type: build
- filename: compress/zlib.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: text/libffi.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: text/pcre2.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: text/libiconv.bst
  type: build
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: gnome:glib/2.82/glib-2.82.4.tar.xz
  ref: 37dd0877fe964cd15e9a2710b044a1830fb1bd93652a6d0cb6b8b2dff187c709
- kind: tar
  url: proxy-libintl:0.4.tar.gz
  ref: 13ef3eea0a3bc0df55293be368dfbcff5a8dd5f4759280f28e030d1494a5dffb
  directory: subprojects/proxy-libintl
- kind: local
  path: buildstream/files/meson-aarch64-android26.ini
  directory: .bst

variables:
  meson-local: >-
    -Dintrospection=disabled
    -Druntime_dir=/usr/var/run
    -Dlibmount=disabled
    -Dman-pages=disabled
    -Dtests=false
    -Dselinux=disabled
    -Dlibelf=disabled

environment:
  LDFLAGS: "-L/opt/android-sysroot/usr/lib -Wl,-rpath,/usr/lib -Wl,--allow-shlib-undefined -l:libiconv.a"

config:
  configure-commands:
  - |
    gnulib="%{conf-root}/glib/gnulib/meson.build"
    if grep -q 'frexpl.*missing or broken' "$gnulib"; then
      sed -i "/error.*frexp.*missing or broken/s/^/# /" "$gnulib"
      sed -i "/gl_cv_func_frexpl_works = false/s/^.*$/  gl_cv_func_frexpl_works = true/" "$gnulib"
      sed -i "/gl_cv_func_frexp_works = false/s/^.*$/  gl_cv_func_frexp_works = true/" "$gnulib"
    fi
  - |
    %{meson}
  strip-commands:
  - |
    libdir="%{install-root}%{prefix}/lib"
    for name in \
      glib-2.0 gobject-2.0 gio-2.0 gmodule-2.0 gthread-2.0 \
      girepository-2.0 intl; do
      find "$libdir" -type f -name "lib$name.so*" -exec "$STRIP" {} +
    done
