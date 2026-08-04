kind: autotools

description: |
  libX11 1.8.10 for Android/Bionic.

  Target xorgproto/xtrans/libxcb/sysvshm artifacts are composed under the target
  sysroot. The two small source edits preserve Bionic pthread semantics and the
  unversioned Winlator libXcursor loader name.

depends:
- filename: host/noble-amd64.bst
  junction: buildstream-sdk.bst
  type: build
- filename: toolchains/android-ndk-r29.bst
  junction: buildstream-sdk.bst
  type: build
- filename: wine/x86_64/x11/xorgproto.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/xtrans.bst
  type: build
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/x11/libxcb.bst
  type: all
  config:
    location: /opt/android-sysroot
- filename: wine/x86_64/android/android-sysvshm.bst
  type: all
  config:
    location: /opt/android-sysroot

sources:
- kind: tar
  url: xorg:lib/libX11-1.8.10.tar.xz
  ref: 2b3b3dad9347db41dca56beb7db5878f283bde1142f04d9f8e478af435dfdc53

variables:
  target-triple: x86_64-linux-android35
  conf-global: --host=x86_64-linux-android
  conf-root: "%{build-root}"
  command-subdir: _build
  conf-local: >-
    host_alias=x86_64-linux-android
    --enable-shared
    --disable-static
    --disable-specs
    --without-xmlto
    --without-fop
    --without-xsltproc
    --enable-malloc0returnsnull
    xorg_cv_malloc0_returns_null=yes

environment:
  LDFLAGS: "-L/opt/android-sysroot/usr/lib -Wl,-rpath,/usr/lib -Wl,--allow-shlib-undefined -lsysvshm"

config:
  configure-commands:
  - |
    sed -i 's/XTHREADLIB=-lpthread/XTHREADLIB=-pthread/g' "%{conf-root}/configure"
    if [ -f "%{conf-root}/src/CrGlCur.c" ]; then
      sed -i 's/"libXcursor\.so\.1"/"libXcursor.so"/' "%{conf-root}/src/CrGlCur.c"
    fi
  - |
    %{configure}
  strip-commands:
  - |
    find "%{install-root}" -type f -name '*.la' -delete
    find "%{install-root}%{prefix}/lib" -type f -name 'libX11.so*' \
      -exec "$STRIP" {} +
