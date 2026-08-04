kind: manual

description: Runtime-pruned imagefs root assembled from all package artifacts.

depends:
- filename: base/host-sdk-autotools.bst
  type: build
- filename: imagefs/staging.bst
  type: build
  config:
    location: /imagefs

config:
  install-commands:
  - |
    set -eu
    root="%{install-root}"
    cp -a /imagefs/. "$root/"

    rm -rf \
      "$root/usr/include" \
      "$root/usr/cmake" \
      "$root/usr/lib/pkgconfig" \
      "$root/usr/lib/cmake" \
      "$root/usr/share/pkgconfig" \
      "$root/usr/share/cmake" \
      "$root/usr/share/aclocal" \
      "$root/usr/share/vala" \
      "$root/usr/local"
    find "$root/usr/lib" -type d -name include -prune -exec rm -rf {} +
    find "$root/usr/lib" \( -name '*.a' -o -name '*.la' \) -delete
    rm -rf \
      "$root/usr/share/man" \
      "$root/usr/share/doc" \
      "$root/usr/share/info" \
      "$root/usr/share/locale" \
      "$root/usr/share/bash-completion" \
      "$root/usr/share/zsh" \
      "$root/usr/share/gdb" \
      "$root/usr/share/gettext" \
      "$root/usr/share/GConf" \
      "$root/usr/share/licenses" \
      "$root/usr/share/ffmpeg" \
      "$root/usr/share/vulkan/registry" \
      "$root/usr/share/xcb" \
      "$root/usr/share/xml" \
      "$root/usr/share/gir-1.0" \
      "$root/usr/lib/girepository-1.0"

    rm -f \
      "$root/usr/lib"/libGLdispatch.so* \
      "$root/usr/lib"/libGLESv1_CM.so* \
      "$root/usr/lib"/libGLX.so* \
      "$root/usr/lib"/libOpenGL.so*

    for name in libc.so libdl.so libm.so liblog.so libEGL.so libGLESv2.so \
      libandroid.so libOpenSLES.so; do
      ln -sfn "/system/lib64/$name" "$root/usr/lib/$name"
    done
    for name in libpthread.so libpthread.so.0 librt.so librt.so.1; do
      ln -sfn /system/lib64/libc.so "$root/usr/lib/$name"
    done

    if [ -d "$root/usr/bin" ]; then
      find "$root/usr/bin" -mindepth 1 -maxdepth 1 \
        \( -type f -o -type l \) \
        ! -name fc-cache \
        ! -name glib-compile-schemas \
        ! -name gio-querymodules \
        -delete
    fi

    test ! -e "$root/usr/include"
    test -e "$root/usr/lib/libGL.so.1"
    test -e "$root/usr/lib/libEGL.so.1"
    test -e "$root/usr/lib/.libgl-zink"
    test -n "$(find "$root/usr/lib" -type f -name 'libgallium*.so' -print -quit)"
    for unwanted in libvulkan_freedreno.so libvkbasalt.so libbcn_layer.so; do
      test ! -e "$root/usr/lib/$unwanted"
    done

  strip-commands: []
