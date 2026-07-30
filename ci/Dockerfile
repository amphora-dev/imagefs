# =============================================================================
# ci/Dockerfile — winlator bionic imagefs 交叉编译环境
# =============================================================================
# 基础: Ubuntu 22.04 + 全套构建工具 (cmake / meson / autotools / perl ...)
# NDK r29 由 setup-env.sh 在构建时下载并缓存到 /tmp/imagefs-build/cache
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        ninja-build \
        autoconf \
        automake \
        libtool \
        libtool-bin \
        autotools-dev \
        pkg-config \
        perl \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        curl \
        wget \
        git \
        unzip \
        xz-utils \
        tar \
        bzip2 \
        gzip \
        ca-certificates \
        patch \
        file \
        rsync \
        binutils \
        gperf \
        flex \
        bison \
        gettext \
        texinfo \
        # patchelf: libsndfile/pulseaudio 的 SONAME/NEEDED 修正
        patchelf \
        # ccache: NDK clang 交叉编译加速 (CI 持久化到 /tmp/imagefs-build/cache/ccache)
        ccache \
        # libglib2.0-dev: 提供 glib-compile-schemas (pulseaudio configure 需要)
        libglib2.0-dev \
    # meson 保持较新版本 (glib 2.82 / harfbuzz 10.x 要求 >= 0.63)
    && pip3 install --no-cache-dir "meson>=1.3" \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
