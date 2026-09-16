#!/usr/bin/env python3
"""Fail closed if PresentModesKHR thunk still calls the host ICD directly.

After make_vulkan, vkGetPhysicalDeviceSurfacePresentModesKHR must be a
USER_DRIVER thunk (vk_funcs → win32u), which advertises FIFO+MAILBOX+IMMEDIATE
and pairs with CreateSwapchain IMMEDIATE/MAILBOX→FIFO remap.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    thunks = Path("dlls/winevulkan/vulkan_thunks.c")
    if not thunks.is_file():
        print("missing dlls/winevulkan/vulkan_thunks.c after autogen", file=sys.stderr)
        return 1
    text = thunks.read_text(encoding="utf-8", errors="replace")
    pat = re.compile(
        r"thunk64_vkGetPhysicalDeviceSurfacePresentModesKHR\(void \*args\)\s*"
        r"\{.*?params->result = (.*?);",
        re.S,
    )
    m = pat.search(text)
    if not m:
        print("PresentModesKHR thunk64 not found after make_vulkan", file=sys.stderr)
        return 1
    call = m.group(1)
    if "vk_funcs->p_vkGetPhysicalDeviceSurfacePresentModesKHR" not in call:
        print(
            "PresentModesKHR thunk64 still host-passthrough; need proton-wine "
            "USER_DRIVER PresentModes + win32u remap pin. Got: "
            + call[:200],
            file=sys.stderr,
        )
        return 1
    print("ok: PresentModesKHR thunk uses vk_funcs (win32u)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
