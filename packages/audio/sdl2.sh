#!/usr/bin/env bash
# SDL2 — cmake；桌面 GL 关闭（不依赖 libglvnd；Mesa libGL 来自 extra_libs）
# 依赖: alsa-lib
set -euo pipefail
source "$(dirname "$0")/../config.sh"

VER="2.30.11"
PKG_NAME="SDL2-$VER"
SRC_URL="https://github.com/libsdl-org/SDL/releases/download/release-$VER/SDL2-$VER.tar.gz"

cd "$SRC_DIR"
fetch_source "$PKG_NAME" sdl2.tar.gz "$SRC_URL" \
    "https://www.libsdl.org/release/SDL2-$VER.tar.gz"
cd "$PKG_NAME" && mkdir -p build_dir && cd build_dir

# 创建 cmake toolchain file 以正确处理交叉编译
TCFILE="$BUILD_DIR/sdl2-toolchain.cmake"
cat > "$TCFILE" << EOF
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_AR $AR)
set(CMAKE_STRIP $STRIP)
set(CMAKE_RANLIB $RANLIB)
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_FLAGS "$CFLAGS -U__ANDROID__")
set(CMAKE_CXX_FLAGS "$CXXFLAGS -U__ANDROID__")
set(CMAKE_EXE_LINKER_FLAGS "$LDFLAGS")
set(CMAKE_SHARED_LINKER_FLAGS "$LDFLAGS")
set(CMAKE_SYSROOT $TC/sysroot)
set(CMAKE_FIND_ROOT_PATH $PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
# 移除 /usr/include 从隐式搜索路径
set(CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES "$PREFIX/include;$TC/sysroot/usr/include;$TC/sysroot/usr/include/aarch64-linux-android")
EOF

cmake -DCMAKE_TOOLCHAIN_FILE="$TCFILE" \
    -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DSDL_TEST=OFF \
    -DSDL_TESTS=OFF \
    \
    -DSDL_AUDIO=ON \
    -DSDL_ALSA=ON \
    -DSDL_ALSA_SHARED=ON \
    -DSDL_PULSEAUDIO=OFF \
    -DSDL_JACK=OFF \
    -DSDL_ESD=OFF \
    -DSDL_ARTS=OFF \
    -DSDL_NAS=OFF \
    -DSDL_SNDIO=OFF \
    -DSDL_FUSIONSOUND=OFF \
    -DSDL_DISK=ON \
    -DSDL_DUMMYAUDIO=ON \
    \
    -DSDL_VIDEO=ON \
    -DSDL_OPENGL=OFF \
    -DSDL_OPENGLES=ON \
    -DSDL_EGL=ON \
    -DSDL_VULKAN=ON \
    -DSDL_X11=ON \
    -DSDL_X11_SHARED=ON \
    -DSDL_WAYLAND=OFF \
    -DSDL_KMSDRM=OFF \
    -DSDL_RPI=OFF \
    -DSDL_DIRECTFB=OFF \
    -DSDL_VIVANTE=OFF \
    -DSDL_OFFSCREEN=OFF \
    -DSDL_DUMMYVIDEO=ON \
    \
    -DSDL_LOADSO=ON \
    -DSDL_DLOPEN=ON \
    -DSDL_THREADS=ON \
    -DSDL_TIMERS=ON \
    -DSDL_FILE=ON \
    -DSDL_FILESYSTEM=ON \
    -DSDL_CPUINFO=ON \
    -DSDL_EVENTS=ON \
    -DSDL_JOYSTICK=ON \
    -DSDL_HIDAPI=OFF \
    -DSDL_HAPTIC=ON \
    -DSDL_SENSOR=ON \
    -DSDL_POWER=ON \
    -DSDL_RENDER=ON \
    \
    -DSDL_STATIC=OFF \
    -DSDL_SHARED=ON \
    -DSDL_STATIC_PIC=ON ..

# 修补: 移除 -isystem/usr/include (来自 ALSA 检测)
find . -name "flags.make" -exec sed -i 's|-isystem/usr/include||g' {} \;

make -j$JOBS
make install
$STRIP "$PREFIX/lib/libSDL2.so" 2>/dev/null || true

log "  SDL2 $VER: $(ls $PREFIX/lib/libSDL2*.so* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
