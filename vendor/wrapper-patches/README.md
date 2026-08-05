# Pipetto vulkan wrapper patches (NDK / Amphora)

Applied by `ci/wrapper/build-tzst.sh` onto the Mesa source pinned by
`buildstream/elements/l1/wrapper-tzst.bst`.

Compile profile: `-D__AMPHORA__` is the Amphora-owned switch for
"NDK toolchain + Linux Mesa paths". `-D__TERMUX__` is still defined as a
Pipetto compatibility alias wherever upstream code gates AHardwareBuffer /
X11 WSI on `__TERMUX__`.

| Patch | Why |
|-------|-----|
| `0001-anon-file-use-memfd-create.patch` | Under the Amphora/Termux-compat profile Mesa may take the Android `SYS_memfd_create` path; NDK headers often lack that constant. Use libc `memfd_create` (compile with `WRAPPER_API>=30`). |
| `0002-wrapper-include-fcntl.patch` | Wrapper sources call `open`/`O_*` without including `fcntl.h` under NDK. |
| `0003-amphora-not-detect-os-android.patch` | With `__AMPHORA__` (or legacy `__TERMUX__`), do **not** set `DETECT_OS_ANDROID`. NDK clang defines `__ANDROID__`, which otherwise pulls `liblog`/`libcutils`/`libsync` into `DT_NEEDED`; packing those android-stub `.so` into imagefs shadows `/system` and breaks Adreno load (`vkCreateInstance` **-9**). |

Do not vendor the full Mesa tree here — CI clones upstream.

`libadrenotools` + hooks are **self-built** from Mesa's `subprojects/libadrenotools` (pinned by `ADRENOTOOLS_REF` in `ci/wrapper/build-tzst.sh`). Keep C++ exceptions enabled in the wrapper cross file — `-fno-exceptions` produced a broken hook vintage.
