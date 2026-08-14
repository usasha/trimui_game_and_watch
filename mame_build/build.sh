#!/bin/bash
# =============================================================================
# Build native MAME 0.223 (full build, Game & Watch capable) for TrimUI Brick
#
# Reproducible: all versions pinned in pins.env. Builds in an arm64 Ubuntu
# 20.04 Docker container (native on Apple Silicon).
#
# Prerequisites:
#   - Docker running
#   - ~6 GB free disk space, 16 GB RAM recommended
#
# Usage:
#   ./build.sh             # full build (docker image + MAME)
#   ./build.sh --no-build  # only build MAME (reuse existing docker image)
#   ./build.sh --no-clone  # reuse existing mame_src clone
#   ./build.sh --force     # rebuild even if out/mame exists
# =============================================================================
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "${BUILD_ROOT}/pins.env"

MAME_SRC="${BUILD_ROOT}/mame_src"
OUT_DIR="${BUILD_ROOT}/out"
IMAGE_NAME="mame-gw-0223:0.223"
BUILD_LOG="${BUILD_ROOT}/build_mame.log"

log() { echo "[build] $*"; }
err() { echo "[build ERROR] $*" >&2; }

# --- Step 1: Build the docker image -----------------------------------------
build_image() {
    log "Building docker image ${IMAGE_NAME} (SDL2 ${SDL2_VERSION})..."
    docker build --platform linux/arm64 \
        --build-arg SDL2_VERSION="${SDL2_VERSION}" \
        --build-arg DOCKER_BASE_IMAGE="${DOCKER_BASE_IMAGE}" \
        -t "${IMAGE_NAME}" "${BUILD_ROOT}"
}

# --- Step 2: Clone MAME at the pinned tag -----------------------------------
clone_mame() {
    if [ -d "${MAME_SRC}/.git" ] && [ -n "$1" ]; then
        log "Using existing MAME source: ${MAME_SRC}"
        return
    fi
    log "Cloning mamedev/mame at tag ${MAME_TAG} (shallow)..."
    rm -rf "${MAME_SRC}"
    git clone --depth 1 --branch "${MAME_TAG}" "${MAME_REPO}" "${MAME_SRC}"
    log "MAME source ready."
}

# --- Step 2b: Apply pinned patches -------------------------------------------
apply_patches() {
    log "Applying patches from ${BUILD_ROOT}/patches..."
    for py in "${BUILD_ROOT}"/patches/*.py; do
        [ -e "$py" ] || continue
        python3 "$py" "${MAME_SRC}"
    done
}

# --- Step 2c: Verify pinned patches took effect ------------------------------
verify_patches() {
    log "Verifying patches took effect..."
    if ! grep -q "m_last_draw_bitmap" "${MAME_SRC}/src/emu/screen.cpp"; then
        err "Patch 0001 (svg skip-unchanged) did not apply to screen.cpp"
        exit 1
    fi
    if ! grep -q "set_size(width / 2, height / 2)" "${MAME_SRC}/src/mame/drivers/hh_sm510.cpp"; then
        err "Patch 0002 (svg half-res) did not apply to hh_sm510.cpp"
        exit 1
    fi
    log "Patches verified."
}

# --- Step 3: Build MAME inside the container --------------------------------
build_mame() {
    log "Building MAME ${MAME_TAG} (full build)..."
    log "Jobs: ${BUILD_JOBS}. Log: ${BUILD_LOG}"

    # Delete prebuilt x86_64 GENie only on a fresh build so the makefile
    # rebuilds it for arm64 (0.223 makefile has a source-build rule for it).
    # IMPORTANT: regenerating GENie/projects bumps Makefile mtimes, and every
    # object depends on $(MAKEFILE) - a full rebuild gets triggered. So keep
    # the arm64 GENie stable across builds.
    local genie_bin="${MAME_SRC}/3rdparty/genie/bin/linux/genie"
    if [ -f "${genie_bin}" ] && file "${genie_bin}" | grep -q "x86-64"; then
        log "Removing prebuilt x86_64 GENie (will rebuild for arm64)"
        rm -f "${genie_bin}"
    fi

    mkdir -p "${OUT_DIR}/lib"

    # REGENIE only when projects are not generated yet (avoids mtime spiral)
    local regenie=0
    [ -f "${MAME_SRC}/build/projects/sdl/mame/gmake-linux/Makefile" ] || regenie=1

    docker run --rm --platform linux/arm64 \
        -e REGENIE="${regenie}" \
        -e OPTIMIZE="${OPTIMIZE}" \
        -e BUILD_JOBS="${BUILD_JOBS}" \
        -e MAME_SOURCES="${MAME_SOURCES}" \
        -v "${MAME_SRC}":/root/workspace \
        -v "${OUT_DIR}":/out \
        "${IMAGE_NAME}" \
        /bin/bash -c '
            set -e
            cd /root/workspace
            make linux \
                REGENIE=$REGENIE \
                SOURCES=$MAME_SOURCES \
                PYTHON_EXECUTABLE=python3 \
                OPTIMIZE=$OPTIMIZE \
                NOWERROR=1 \
                NO_X11=1 \
                NO_OPENGL=1 \
                NO_USE_PORTAUDIO=1 \
                NO_USE_MIDI=1 \
                USE_QTDEBUG=0 \
                USE_TAPTUN=0 \
                USE_PCAP=0 \
                NO_USE_XINPUT=1 \
                USE_LIBSDL=1 \
                SDL_INSTALL_ROOT=/opt/sdl2 \
                LDOPTS="-static-libstdc++ -static-libgcc -fuse-ld=lld" \
                ARCHOPTS="-U_FORTIFY_SOURCE -DASMJIT_BUILD_X86=1 -UASMJIT_BUILD_HOST" \
                -j$BUILD_JOBS
        ' 2>&1 | tee "${BUILD_LOG}"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        err "MAME build failed. See ${BUILD_LOG}"
        exit 1
    fi

    # Age the GENie binary so the makefile's regen rule
    # (Makefile depends on $(GENIE)) never re-triggers a project
    # regeneration - regeneration bumps Makefile mtimes, and every object
    # depends on $(MAKEFILE), causing a full rebuild on the next run.
    if [ -f "${MAME_SRC}/3rdparty/genie/bin/linux/genie" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            touch -t "$(date -v-2H +%Y%m%d%H%M.%S)" "${MAME_SRC}/3rdparty/genie/bin/linux/genie"
        else
            touch -d '2 hours ago' "${MAME_SRC}/3rdparty/genie/bin/linux/genie"
        fi
    fi
}

# --- Step 4: Collect artifacts ----------------------------------------------
copy_output() {
    # If the binary was already collected (e.g. rebuilt previously), keep it
    if [ -f "${OUT_DIR}/mame" ] && [ ! -f "${MAME_SRC}/mame" ]; then
        log "Reusing existing binary: ${OUT_DIR}/mame ($(ls -lh "${OUT_DIR}/mame" | awk '{print $5}'))"
    else
        # MAME 0.223 puts the binary at the source root, not in build/projects/
        local bin="${MAME_SRC}/mame"
        [ -f "$bin" ] || bin="${MAME_SRC}/build/projects/sdl/mame/gmake-linux/mame"
        if [ ! -f "$bin" ]; then
            err "Build output not found (tried ${MAME_SRC}/mame)"
            exit 1
        fi
        cp "$bin" "${OUT_DIR}/mame"
        log "mame binary copied: $(ls -lh "${OUT_DIR}/mame" | awk '{print $5}')"
    fi

    # Bundle every runtime dependency (except glibc core, statically linked
    # libstdc++/libgcc) so the device needs nothing we don't ship.
    # Device has its own libasound.so.2, but bundling ours is harmless
    # (glibc 2.31 <= device's) and makes the pak self-contained.
    docker run --rm --platform linux/arm64 \
        -v "${OUT_DIR}":/out \
        "${IMAGE_NAME}" \
        /bin/bash -c '
            set -e
            # glibc components stay with the device; libEGL also stays
            # (device has its own PowerVR libEGL.so.1 - do not shadow with Mesa)
            SKIP_RE="^(libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libstdc\+\+|libgcc_s|libgcc\.so|ld-linux|libnss_|libresolv|libutil|libcrypt|libEGL)"
            needlibs() { readelf -d "$1" | grep NEEDED | sed -E "s/.*\[(.*)\].*/\1/"; }
            # prefer the minimal SDL2 we built (/opt/sdl2, fbcon-only) over
            # the distro one (which drags in X11/wayland/pulseaudio)
            findlib() { find /opt/sdl2/lib /lib /usr/lib -name "$1" 2>/dev/null | head -1; }
            # first round: deps of mame itself
            needlibs /out/mame > /tmp/candidates.txt
            # iterate until no new libs are added
            while :; do
                new=0
                while read -r lib; do
                    echo "$lib" | grep -qE "$SKIP_RE" && continue
                    [ -f "/out/lib/$lib" ] && continue
                    found=$(findlib "$lib")
                    if [ -n "$found" ]; then
                        cp -L "$found" /out/lib/
                        echo "[bundle] $lib <- $found"
                        new=1
                    else
                        echo "[bundle] WARNING: $lib not found in container"
                    fi
                done < /tmp/candidates.txt
                [ "$new" = "0" ] && break
                # add transitive deps of everything bundled so far
                : > /tmp/candidates.txt
                for f in /out/lib/*.so*; do
                    [ -f "$f" ] || continue
                    needlibs "$f" >> /tmp/candidates.txt
                done
                sort -u /tmp/candidates.txt -o /tmp/candidates.txt
            done
        '
    log "Bundled libs:"
    ls -lh "${OUT_DIR}/lib/"
}

# --- Step 5: Verify ----------------------------------------------------------
verify_output() {
    log "--- verification ---"
    file "${OUT_DIR}/mame"

    local max_glibc
    max_glibc=$(strings "${OUT_DIR}/mame" | grep -o 'GLIBC_2\.[0-9]*' | sort -t. -k2 -n | tail -1)
    log "Max GLIBC symbol required by mame: ${max_glibc} (device requires >= ~2.31)"

    log "Remaining dynamic deps (must all be in out/lib/ or be device libs):"
    docker run --rm --platform linux/arm64 \
        -v "${OUT_DIR}":/out "${IMAGE_NAME}" \
        readelf -d /out/mame | grep NEEDED
}

# --- Main --------------------------------------------------------------------
main() {
    local no_build=""
    local no_clone=""
    local force=""
    for a in "$@"; do
        case "$a" in
            --no-build) no_build="1" ;;
            --no-clone) no_clone="1" ;;
            --force) force="1" ;;
        esac
    done

    if [ -z "${no_build}" ]; then
        build_image
    else
        log "Skipping docker image build (--no-build)"
    fi

    clone_mame "${no_clone}"
    apply_patches
    verify_patches
    if [ -f "${OUT_DIR}/mame" ] && [ -z "${force}" ]; then
        log "mame binary already exists in ${OUT_DIR} - skipping build (--force to rebuild)"
    else
        build_mame
    fi
    copy_output
    verify_output

    log ""
    log "Done! Artifacts in ${OUT_DIR}:"
    ls -lh "${OUT_DIR}/" "${OUT_DIR}/lib/"
    log "Next: ./deploy.sh"
}

main "$@"
