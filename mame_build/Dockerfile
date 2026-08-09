# =============================================================================
# Build environment for MAME 0.223 (Game & Watch) for TrimUI Brick (tg5040)
#
# Strategy:
#   - Native arm64 build (Apple Silicon Mac runs linux/arm64 containers
#     at full speed; no cross-compile needed)
#   - Ubuntu 20.04 (glibc 2.31) is binary-compatible with the device
#     (device glibc >= 2.31, verified by the phase-B libretro core)
#   - SDL2 2.0.20 built from source: fbcon video driver (device has /dev/fb0
#     but no X11/libdrm), ALSA audio via dlopen (device has libasound.so.2)
#   - Output: static libstdc++/libgcc linkage, dynamic libSDL2 bundled
#     in the pak (see build.sh / deploy.sh)
# =============================================================================
ARG DOCKER_BASE_IMAGE
FROM ${DOCKER_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make python3 git lld \
    ca-certificates wget tar xz-utils \
    pkg-config linux-libc-dev libasound2-dev libx11-dev \
    libsdl2-ttf-dev libfontconfig1-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- SDL2 2.0.20 (fbcon + dummy video, ALSA via dlopen) ----
# fbcon needs linux/fb.h (linux-libc-dev). ALSA is dlopen'd at runtime,
# so the built libSDL2 only depends on glibc at runtime.
ARG SDL2_VERSION
RUN mkdir -p /opt/sdl2-src && cd /opt/sdl2-src \
    && wget -qO SDL2.tar.gz https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VERSION}/SDL2-${SDL2_VERSION}.tar.gz \
    && tar xzf SDL2.tar.gz \
    && cd SDL2-${SDL2_VERSION} \
    && ./configure --prefix=/opt/sdl2 \
        --enable-video-fbcon \
        --enable-video-dummy \
        --disable-video-x11 \
        --disable-video-wayland \
        --disable-video-kmsdrm \
        --disable-video-opengl \
        --disable-video-opengles \
        --disable-video-vulkan \
        --enable-alsa \
        --disable-pulseaudio \
        --disable-esd \
        --disable-arts \
        --disable-jack \
        --disable-sndio \
    && make -j8 && make install \
    && rm -rf /opt/sdl2-src

ENV SDL_INSTALL_ROOT=/opt/sdl2
ENV PATH=/opt/sdl2/bin:${PATH}
