# Mesa desktop GL patches (NDK / Termux link profile)

Applied by `packages/graphics/mesa-gl.sh` onto the upstream Mesa release tarball
(`MESA_GL_VER`, default in that recipe), **after**
`vendor/wrapper-patches/0003-termux-not-detect-os-android.patch`, which is shared
with the Vulkan wrapper build.

| Patch | Why |
|-------|-----|
| `0001-termux-no-android-native-handle.patch` | NDK clang defines `__ANDROID__`, so `include/vulkan/vk_android_native_buffer.h` includes AOSP's `<cutils/native_handle.h>`, which does not exist outside an AOSP tree. Mesa's own escape hatch (`-Dandroid-stub=true`) is rejected since 25.3 unless `platforms=android`, and `platforms=android` is exactly what the Termux profile avoids. Under `__TERMUX__` take the generic `buffer_handle_t` instead. |
| `0002-emutls-export-glapi-tls.patch` | The NDK defaults to `-femulated-tls`, which renames glapi's two `thread_local`s to `__emutls_v.*`. `dri.sym.in` only lists the plain names, so the real ones fall into `local: *` and libGL/libEGL fail to link. Export the `__emutls_v.*` names too. |

**Do not "fix" that by turning emulated TLS off.** It looks like the smaller change — the symbol names line up and the patch goes away — but glapi declares the dispatch pointer `__THREAD_INITIAL_EXEC`, and initial-exec TLS in a `dlopen`'d solib can only come out of bionic's small surplus static TLS block. `libgallium` is exactly that: Wine opens `libEGL`, which pulls it in. Threads that miss the surplus get a bogus offset, and the first `GET_DISPATCH()` dereference segfaults — DirectDraw renders frame one, then dies the moment wined3d's command-stream thread issues a GL call. Emulated TLS goes through `__emutls_get_address` (a pthread key), which does not depend on the thread pointer register and works under `dlopen` on any thread.

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
