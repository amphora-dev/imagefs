# Mesa desktop GL patches (NDK / Termux link profile)

Applied by `packages/graphics/mesa-gl.sh` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-termux-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-termux-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Termux profile avoids. Under `__TERMUX__` take the generic `buffer_handle_t` instead. |

The recipe explicitly selects native ELF TLS for every GL frontend and the
megadriver. This is not implied by API 30 in our `system=linux`,
`platforms=x11` cross profile: leaving the NDK default in place can mix
`__emutls_v.*` definitions with plain `_mesa_glapi_tls_*` references and make
`libEGL`/`libGL` fail `dlopen`.

Keep this set minimal: everything else must come from upstream sources so the
build stays a plain "download release tarball → cross-compile" recipe.
