#!/usr/bin/env bash
# Resolve a usable Android NDK on the runner / local machine and export
# ANDROID_NDK_HOME + ANDROID_NDK_ROOT. When $GITHUB_ENV is set (Actions), also
# persist those into the job environment.
set -euo pipefail

pick=""
for cand in \
  "${ANDROID_NDK_LATEST_HOME:-}" \
  "${ANDROID_NDK_HOME:-}" \
  "${ANDROID_NDK_ROOT:-}" \
  "${ANDROID_NDK:-}"; do
  if [ -n "$cand" ] && [ -x "$cand/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
    pick="$cand"
    break
  fi
done

if [ -z "$pick" ] && [ -d "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}/ndk" ]; then
  pick="$(ls -d "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/ndk/29.* 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$pick" ]; then
    pick="$(ls -d "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  fi
fi

if [ -z "$pick" ] && [ -d /opt/android-sdk/ndk ]; then
  pick="$(ls -d /opt/android-sdk/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi

if [ -z "$pick" ] || [ ! -x "$pick/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
  echo "FAIL: no usable Android NDK (set ANDROID_NDK_HOME)" >&2
  ls -la "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}/ndk" 2>/dev/null || true
  exit 1
fi

echo "Using NDK: $pick"
export ANDROID_NDK_HOME="$pick"
export ANDROID_NDK_ROOT="$pick"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "ANDROID_NDK_HOME=$pick"
    echo "ANDROID_NDK_ROOT=$pick"
  } >> "$GITHUB_ENV"
fi
