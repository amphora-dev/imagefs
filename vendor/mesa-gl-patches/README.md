# Mesa desktop GL patches (NDK / Amphora Bionic-Linux profile)

Applied by `buildstream/elements/graphics/mesa-gl.bst` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-amphora-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-amphora-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Amphora Bionic/Linux profile avoids. Under `__AMPHORA__` (or legacy `__TERMUX__`) take the generic `buffer_handle_t` instead. |
| `0003-zink-readback-validate-swapchain-image.patch` | WineD3D front-buffer writes can run after present reset `dt_idx` and before the next acquire. Validate the index against `num_images` before marking the image for readback, preventing `images[UINT32_MAX]` and other out-of-range writes. |
| `0004-zink-acquire-swapchain-on-write-barrier.patch` | A write barrier needs a real swapchain `VkImage`. Acquire it immediately before the write/readback path and verify that an index was assigned. Read-only barriers deliberately do not acquire or wait. |
| `0005-zink-disable-dac-on-qcom-blob.patch` | Mesa 26.2 began using `VK_KHR_device_address_commands` (`CmdBindVertexBuffers3KHR`) for vertex binding. Qualcomm's proprietary Android driver advertises the extension but crashes at the first WineD3D/DX7 draw (`vulkan.adreno.so`, near-NULL access). Keep the extension for Mesa Turnip and other drivers; force the established vertex-buffer binding path only for the proprietary blob. |

The recipe explicitly selects native ELF TLS for every GL frontend and the
megadriver. This is not implied by API 30 in our `system=linux`,
`platforms=x11` cross profile: leaving the NDK default in place can mix
`__emutls_v.*` definitions with plain `_mesa_glapi_tls_*` references and make
`libEGL`/`libGL` fail `dlopen`.

Keep this set minimal: everything else must come from upstream sources so the
build stays a plain "download release tarball → cross-compile" recipe.

The Zink patches remain necessary even when PE32 DirectDraw wrappers are
enabled: x86_64 applications cannot load those wrappers and fall back to
Proton's builtin ddraw → WineD3D → OpenGL/Zink.
