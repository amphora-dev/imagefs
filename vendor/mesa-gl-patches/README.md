# Mesa desktop GL patches (NDK / Termux link profile)

Applied by `packages/graphics/mesa-gl.sh` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-termux-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-termux-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Termux profile avoids. Under `__TERMUX__` take the generic `buffer_handle_t` instead. |
| `0002-micewine-emutls-glapi-symbols.patch` | NDK clang emits glapi's `thread_local` variables as `__emutls_v.*`. Use MiceWine-Packages' fix: **replace** the two plain names in `dri.sym.in` with their emulated-TLS names. The previous Amphora patch incorrectly appended both sets, leaving `libEGL`/`libGL` with unresolved plain TLS imports at runtime. |
| `0003-zink-readback-skip-unacquired.patch` | `zink_kopper_set_readback_needs_update` indexes `swapchain->images[dt_idx]` with no check. `dt_idx` is `UINT32_MAX` until acquire and again after present; DirectDraw → WineD3D front-buffer writes still hit `image_barrier` in that window, so the unguarded index is an OOB segfault after the first swap. Skip until an image is actually acquired (same guard other kopper call sites already use). |
| `0004-zink-acquire-swapchain-before-barrier.patch` | The readback guard alone only moved the fault downstream: the same unacquired resource still reached Turnip's `tu_barrier` with `VkImageMemoryBarrier2.image = VK_NULL_HANDLE`. At the common Zink image-barrier entry, acquire any swapchain resource whose `dt_idx` is `UINT32_MAX`; this establishes a valid Vulkan image and image ownership before emitting the barrier. |

The recipe deliberately keeps emulated TLS. The MiceWine patch aligns the DRI
version script with clang's actual symbols instead of changing the TLS ABI.

Keep this set minimal: everything else must come from upstream sources so the
build stays a plain "download release tarball → cross-compile" recipe.
