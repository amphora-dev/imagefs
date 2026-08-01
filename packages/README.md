# Package recipes

`depends.conf` stays at this root (topo / stamps). Recipes live in category dirs:

| Dir | Packages |
|-----|----------|
| `compress/` | zlib zstd brotli libpng |
| `text/` | pcre2 freetype libiconv fontconfig glib libffi libexpat |
| `android/` | android-sysvshm libandroid-shmem libcxx-shared android-spawn android-sysv-semaphore |
| `x11/` | xorgproto libxcb xtrans libx11 + X extensions |
| `graphics/` | libdrm vulkan-headers vulkan-loader mesa-gl |
| `crypto/` | openssl gmp nettle gnutls |
| `audio/` | alsa-lib alsa-android-aserver sdl2 |
| `media/` | gstreamer gst-plugins-base |

Lookup: `lib/pkg.sh` → `pkg_recipe_path <name>` resolves `packages/*/<name>.sh`.
Package **names** in `depends.conf` / `ALL_PACKAGES` are unchanged.
