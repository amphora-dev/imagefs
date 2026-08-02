# Mesa desktop GL patches (NDK / Termux link profile)

Applied by `packages/graphics/mesa-gl.sh` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-termux-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-termux-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Termux profile avoids. Under `__TERMUX__` take the generic `buffer_handle_t` instead. |

There is deliberately **no zink patch here**. Zink only needs patching to reach the
`libgl-xlib` target, whose `dependencies` upstream omits `driver_zink`; and even
patched in, zink cannot present through the xlib software winsys because its
`flush_frontbuffer` is written entirely against kopper displaytargets, which only
the DRI frontend creates. WinNative works around both by carrying
[`Pipetto-crypto/mesa` `zink-mesa-xlib`](https://github.com/Pipetto-crypto/mesa/tree/zink-mesa-xlib),
which comments out the softpipe/llvmpipe requirement, forces `sw_screen_create_named`
to always return zink, and rewrites `zink_flush_frontbuffer` into a full-frame GPU→CPU
readback plus `XPutImage`. We build `-Dglx=dri -Degl=enabled` instead, where
`targets/dri` already lists `driver_zink` and kopper is the native present path, so
none of that is needed.

Keep this set minimal: everything else must come from upstream sources so the
build stays a plain "download release tarball → cross-compile" recipe.
