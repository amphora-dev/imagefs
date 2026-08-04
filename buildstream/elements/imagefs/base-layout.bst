kind: manual

description: |
  merged-usr imagefs skeleton and Android system-library pointers.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build

config:
  install-commands:
  - |
    set -eu
    root="%{install-root}"
    usr="$root/usr"
    mkdir -p \
      "$usr/bin" "$usr/lib/pkgconfig" "$usr/etc" "$usr/share" \
      "$usr/tmp/.X11-unix" "$usr/tmp/.sound" "$usr/tmp/.sysvshm" \
      "$usr/include" "$usr/var/cache" "$usr/var/run" \
      "$root/home/xuser" "$root/opt" "$root/storage" \
      "$root/proc" "$root/sys" "$root/dev"
    ln -s usr/bin "$root/bin"
    ln -s usr/etc "$root/etc"
    ln -s usr/lib "$root/lib"
    ln -s usr/share "$root/share"
    ln -s usr/tmp "$root/tmp"

    for name in libc.so libdl.so libm.so liblog.so \
      libandroid.so libOpenSLES.so; do
      ln -s "/system/lib64/$name" "$usr/lib/$name"
    done
    for name in libpthread.so libpthread.so.0 librt.so librt.so.1; do
      ln -s /system/lib64/libc.so "$usr/lib/$name"
    done

    cat > "$usr/etc/os-release" <<'EOF'
    NAME="Winlator Bionic ImageFS"
    ID=winlator-bionic
    PRETTY_NAME="Winlator Bionic ImageFS"
    VERSION_ID="7.1.4"
    EOF
    printf 'adapter=mock\n' > "$usr/tmp/adapterinfo"
    mkdir -p \
      "$usr/etc/fonts/conf.d" "$usr/share/fonts" \
      "$usr/etc/alsa/conf.d" "$usr/lib/alsa-lib" \
      "$usr/share/vulkan/explicit_layer.d" \
      "$usr/share/vulkan/implicit_layer.d" \
      "$usr/lib/gstreamer-1.0"

  strip-commands: []
