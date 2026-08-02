# Mesa desktop GL patches (NDK / Termux link profile)

Applied by `packages/graphics/mesa-gl.sh` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-termux-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-termux-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Termux profile avoids. Under `__TERMUX__` take the generic `buffer_handle_t` instead. |
| `0002-libgl-xlib-link-zink.patch` | The `libgl-xlib` target lists only `driver_swrast` / `driver_virgl` / `driver_asahi`, so `GALLIUM_ZINK` is never defined and `sw_screen_create_named` has no zink branch. Since `sw_screen_create_vk` returns NULL (rather than trying the next driver) whenever an explicitly requested `GALLIUM_DRIVER` is unavailable, `GALLIUM_DRIVER=zink` then kills the entire GL stack. Add `driver_zink` the way `targets/dri` already does; it is `declare_dependency()` when zink is not built, so the line is safe either way. |

Keep this set minimal: everything else must come from upstream sources so the
build stays a plain "download release tarball → cross-compile" recipe.
