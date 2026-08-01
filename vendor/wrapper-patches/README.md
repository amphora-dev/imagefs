# Pipetto vulkan wrapper patches (NDK / Amphora)

Applied by `ci/wrapper/build-tzst.sh` onto [Pipetto-crypto/mesa](https://github.com/Pipetto-crypto/mesa) `wrapper-25`.

| Patch | Why |
|-------|-----|
| `0001-anon-file-use-memfd-create.patch` | With `-D__TERMUX__`, Mesa takes the Android `SYS_memfd_create` path; NDK headers often lack that constant. Use libc `memfd_create` (compile with `WRAPPER_API>=30`). |
| `0002-wrapper-include-fcntl.patch` | Wrapper sources call `open`/`O_*` without including `fcntl.h` under NDK. |
| `0003-termux-not-detect-os-android.patch` | With `-D__TERMUX__`, do **not** set `DETECT_OS_ANDROID`. NDK clang defines `__ANDROID__`, which otherwise pulls `liblog`/`libcutils`/`libsync` into `DT_NEEDED`; packing those android-stub `.so` into imagefs shadows `/system` and breaks Adreno load (`vkCreateInstance` **-9**). Termux/official wrapper ICDs use Linux Mesa paths + `__TERMUX__` WSI/AHB. |

Do not vendor the full Mesa tree here — CI clones upstream.

Runtime adrenotools/hooks are **not** patched here; see `vendor/adrenotools-prebuilt/`.
