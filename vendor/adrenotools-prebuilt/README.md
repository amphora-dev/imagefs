# Prebuilt libadrenotools (+ hooks)

Shipped next to `libvulkan_wrapper.so` in `wrapper.tzst`.

These blobs match the WinNative / Termux-packaged wrapper (Pipetto
`libadrenotools` @ `8483dfd`, Nov 2025). Amphora guest loading requires the
**hooks vintage to match** `libadrenotools.so` — a self-built adrenotools from
Mesa's `subprojects/libadrenotools.wrap` (`revision = HEAD`) under the wrapper
cross-file (`-fno-exceptions`, heavy strip) produced a smaller ABI-incompatible
hook set and caused guest `adrenotools_open_libvulkan` to fail → DXVK
`vkCreateInstance` **-9** (`VK_ERROR_INCOMPATIBLE_DRIVER`).

`ci/wrapper/build-tzst.sh` still builds the subproject for **link-time** symbols /
headers, then **packs these prebuilts** into the tzst (not the subproject
outputs).

| File | Role |
|------|------|
| `libadrenotools.so` | `adrenotools_open_libvulkan` |
| `libmain_hook.so` / `libhook_impl.so` / `libfile_redirect_hook.so` / `libgsl_alloc_hook.so` | hook set loaded from `ADRENOTOOLS_HOOKS_PATH` (imagefs `usr/lib`) |

Do not replace with NDK-rebuilt copies unless you rebuild and validate the full
hook set together on Adreno devices.
