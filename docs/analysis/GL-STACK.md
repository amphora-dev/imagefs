# 桌面 OpenGL 栈：为什么走 DRI/EGL 而不是 xlib GLX

> 决策记录。2026-08。对应改动：`packages/graphics/mesa-gl.sh` 由 `-Dglx=xlib`
> 改为 `-Dglx=dri -Degl=enabled`。

## 背景

Wine 的 `opengl32` EGL 后端需要一份桌面 OpenGL。DirectDraw 由 Amphora 强制
选择 cnc-ddraw 或 DxWrapper Dd7to9，再进入 D3D9/DXVK，不回退 WineD3D。废止
`extra_libs.tzst` 后 OpenGL 栈由 `packages/graphics/mesa-gl.sh` 自建。最初按
WinNative 的形态选了 `-Dglx=xlib`，因为 xlib GLX 完全在客户端模拟 GLX，不需要
X server 实现 GLX 扩展——而 Amphora 的内置 Java X server 只有 BigReq / DRI3 /
MIT-SHM / Present / Sync / XInput2。

真机上这条路走不通，且不是配置问题，是结构问题。

## xlib GLX 的两个死结

### 一、zink 进不去，进去了也呈现不出来

`src/gallium/targets/libgl-xlib/meson.build` 的 `dependencies` 只有
`driver_swrast` / `driver_virgl` / `driver_asahi`，没有 `driver_zink`，所以
`-DGALLIUM_ZINK` 从不定义，`sw_screen_create_named` 里没有 zink 分支。而
`sw_screen_create_vk` 把显式设置的 `GALLIUM_DRIVER` 当权威：

```c
if (screen) return screen;
else if (i == 0 && drivers[i][0] != '\0') return NULL;   /* 不再回退 */
```

于是 `GALLIUM_DRIVER=zink` 直接返回 NULL，连已编进去的 softpipe 都不尝试，
表现为 `Mesa: warning: Failed to initialize display` 加 Wine 的
`X11DRV_WineGL_InitOpenglInfo couldn't initialize OpenGL`，OpenGL 初始化失败。

补上 `driver_zink` 也只解决一半：zink 的呈现完全绑定 kopper。
`zink_resource.c` 只在 `loader_private` 非空时创建 kopper displaytarget，而
`loader_private` 只有 DRI 前端会给；`zink_flush_frontbuffer` 遇到非 swapchain
资源直接 return；`zink_create_screen(struct sw_winsys *winsys, ...)` 甚至把传进
去的 winsys 丢掉。所以 xlib 下 zink 能渲染，但 `SwapBuffers` 什么都不出。

### 二、fakeglx 的 drawable 缓存与 fbconfig 冲突

这一条更致命，且与用哪个 gallium 驱动无关。

`glXCreateWindow` 直接把 X Window ID 当 GLXWindow 返回（源码注释
`/* A hack for now */`），`glXMakeContextCurrent` 只按 drawable 查
`XMesaFindBuffer`，完全不比对 context 的 visual：

```c
drawBuffer = XMesaFindBuffer( dpy, draw );
if (!drawBuffer)
   drawBuffer = XMesaCreateWindowBuffer( xmctx->xm_visual, draw );
```

于是同一个 X 窗口上换 fbconfig（Wine 换像素格式、重建 context 都会）必然命中
用旧 visual 建的 buffer，`_mesa_make_current` 的 `check_compatible` 在
`depthBits` / `stencilBits` 上失配：

```
Mesa: warning: MakeCurrent: incompatible visuals for context and drawbuffer
Mesa: error: GL User Error: glGetString called without a rendering context
```

此后每个 GL 调用都失败，`glGetString(GL_VENDOR)` 返回 NULL（AIO 测试的 GPU Info
就是空的）。这在 X server 侧无法修复——缓存和 ID 复用都在客户端 libGL 里。

## WinNative 是怎么绕过去的

他们的 libGL 是 **Mesa 24.3.0-devel**，来自
[`Pipetto-crypto/mesa` 分支 `zink-mesa-xlib`](https://github.com/Pipetto-crypto/mesa/tree/zink-mesa-xlib)
（血缘：Grima04/mesa-zink-xlib → alexvorxx/zink-xlib-termux → Pipetto）。四处改动：

1. 注释掉顶层 `meson.build` 的 `error('xlib based GLX requires softpipe or llvmpipe.')`
2. 给 `libgl-xlib` 加 `driver_zink`
3. `inline_sw_helper.h` 里 `sw_screen_create_named` 不再按驱动名分发，
   `zink_create_screen` 变成无条件调用
4. `zink_flush_frontbuffer` 的 kopper 主体整段注释掉，改为把 Vulkan image
   读回 CPU 再经 sw winsys `displaytarget_display` 推给 X

代价是每帧一次 GPU→CPU 同步读回加两次全帧拷贝，并且要长期背一棵侵入式 fork。

## 选定方案：`-Dglx=dri -Degl=enabled`

Wine 10.12 起有 EGL 后端，**10.17 起默认启用**，Wine 11 把 GLX 标记为 deprecated。
EGL 的 dlopen 在 `dlls/win32u/opengl.c`（不在 `winex11.so`）：

```c
if (!(funcs->egl_handle = dlopen( SONAME_LIBEGL, RTLD_NOW | RTLD_GLOBAL )))
```

平台用 `EGL_PLATFORM_X11_KHR` + `eglGetPlatformDisplay`。

关键性质：**Mesa 的 EGL x11 平台从不查询 GLX 扩展**——`src/egl` 全树关于 glx
只有一行注释掉的 `/* glXWaitX(); */`。所以内置 Java X server 不需要实现 GLX。

呈现走 DRI3 + Present，也就是 DXVK 已经在用、Amphora 的 `DRI3Extension` 与
`GPUImage`（AHB 导入 Vulkan 纹理）已经跑通的那条通路。DRI3 不可用时 Mesa 会
自动降级：先试 zink/kopper，再退 swrast（core X + MIT-SHM，两者我们都有）。

`targets/dri` 上游本来就列了 `driver_zink`，kopper 是原生呈现路径。Amphora
不再通过 WineD3D 把 DirectDraw front-buffer 操作送进该路径，因此删除本地
readback/barrier 行为补丁；Mesa 保持「上游发布 tarball + Termux 链接补丁」。

## 依赖与前置条件

imagefs 侧不需要新增包——`libxcb`（含 dri3 / present / sync / shm / xfixes /
randr 子库）、`libxshmfence`、`libX11-xcb`、`libXfixes` 已经在建。

必须满足的运行期条件：

| 条件 | 现状 |
|------|------|
| Wine ≥ 10.17（EGL 默认） | **待办**：当前 Proton 10.0-4 是 Wine 10.0，`win32u.so` 里没有任何 EGL 符号 |
| `libEGL.so.1` 为 EGL 1.5，且有 `EGL_KHR_create_context` / `_no_error` / `_no_config_context` / `EGL_EXT_platform_base` / `EGL_KHR_client_get_all_proc_addresses` | Mesa 的 `egl_dri2.c` 无条件置上这几项 |
| DRI3 ≥ 1.2 且 Present ≥ 1.2（`x11_dri3_has_multibuffer`） | DRI3 已刻意封顶 1.2，正好满足；Present 版本待核 |
| XFIXES ≥ 2 | **缺**。`x11_dri3_open` 解引用 `xcb_xfixes_query_version` 应答时没有 NULL 检查，扩展缺失会崩在那里而不是优雅失败 |
| DRI3 `FenceFromFD` + Sync fence | **缺**。GL 的 DRI3 loader 用 `xcb_dri3_fence_from_fd` / `xcb_sync_trigger_fence`，而我们为了让 DXVK 不走 FenceFromFD 把 DRI3 停在 1.2 |

最后两项只影响加速路径。缺它们时 Mesa 退到 swrast，OpenGL 仍然可用
（软件光栅化），且不再有 fakeglx 那一类 visual 失配问题。

## 落地顺序

1. **Mesa 切 DRI/EGL**（本次改动）+ Proton 升到 ≥ 10.17（已有
   `Proton-11.0-5-x86_64.wcp`）。此时 EGL 生效，最差也是 swrast，功能正确。
2. 给 Java X server 补 XFIXES（QueryVersion 到 ≥ 2 即可）并核对 Present 版本，
   打通 DRI3 multibuffer。
3. 视需要补 DRI3 `FenceFromFD` + Sync fence，让 zink/kopper 完整跑起来。

注意 `-Dglx=xlib` 与 `-Degl=enabled` 在 Mesa 里互斥
（`'EGL requires DRI, but GLX is being built with xlib support'`），所以这是一次
性切换，没有两种前端并存的中间态。Amphora 侧同时要去掉
`LIBGL_KOPPER_DISABLE=true`——在 xlib 前端它是无效残留，切到 DRI 前端后它会
真的把 kopper 关掉。
