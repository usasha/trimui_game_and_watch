#!/bin/sh
# =============================================================================
# Deploy native MAME GW.pak to the TrimUI Brick via SSH (tar-over-ssh)
#
# Deploys the standalone native MAME pak:
#   Emus/tg5040/GW.pak/  -> mame, lib/libSDL2-2.0.so.0, launch.sh
# Artwork + MAME cfg stay in $USERDATA_PATH/mame/ (already deployed).
#
# Prerequisites:
#   - sshpass, tar
#   - mame_build/out/mame + mame_build/out/lib/ built by build.sh
#   - device reachable (default 192.168.1.107, override DEVICE_IP=...)
#
# Usage:
#   ./deploy.sh             # deploy pak
# =============================================================================
set -e

DEVICE_IP="${DEVICE_IP:-192.168.1.107}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-tina}"
PLATFORM="tg5040"
EMU_TAG="GW"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${BUILD_ROOT}/out"
PAK_DIR="${OUT_DIR}/GW.pak"
CFG_SRC="${BUILD_ROOT}/cfg"
ARTWORK_SRC="${REPO_ROOT}/artwork"

# Paths on device
DEVICE_SDCARD="/mnt/SDCARD"
DEVICE_EMUS="${DEVICE_SDCARD}/Emus/${PLATFORM}"
DEVICE_USERDATA="${DEVICE_SDCARD}/.userdata/${PLATFORM}"
DEVICE_MAME_CFG="${DEVICE_USERDATA}/mame/cfg"
DEVICE_MAME_ART="${DEVICE_USERDATA}/mame/artwork"

# Device SSH is slow (dropbear) - generous connect timeout
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=40"
SSH="sshpass -p ${DEVICE_PASS} ssh ${SSH_OPTS} ${DEVICE_USER}@${DEVICE_IP}"

log() { echo "[deploy] $*"; }
err() { echo "[deploy ERROR] $*" >&2; }

tar_to_remote() {
    local local_dir="$1"
    local remote_dir="$2"
    ${SSH} "mkdir -p '${remote_dir}'"
    tar --exclude='._*' -C "${local_dir}" -cf - . | ${SSH} "tar -C '${remote_dir}' -xf -"
}

# --- Pre-check ---------------------------------------------------------------
if [ ! -f "${OUT_DIR}/mame" ] || [ ! -f "${OUT_DIR}/lib/libSDL2-2.0.so.0" ]; then
    err "Missing build artifacts. Run build.sh first."
    exit 1
fi

# --- Assemble pak ------------------------------------------------------------
assemble_pak() {
    log "Assembling GW.pak..."
    rm -rf "${PAK_DIR}"
    mkdir -p "${PAK_DIR}/lib"
    cp "${OUT_DIR}/mame" "${PAK_DIR}/mame"
    cp "${OUT_DIR}/lib/libSDL2-2.0.so.0" "${PAK_DIR}/lib/"
    cp "${BUILD_ROOT}/launch.sh" "${PAK_DIR}/launch.sh"
    chmod +x "${PAK_DIR}/launch.sh" "${PAK_DIR}/mame"
    log "Pak contents:"
    ls -lh "${PAK_DIR}/" "${PAK_DIR}/lib/"
}

# --- Deploy ------------------------------------------------------------------
deploy_to_device() {
    log "Deploying to device (${DEVICE_IP})..."
    ${SSH} "rm -rf '${DEVICE_EMUS}/${EMU_TAG}.pak'"
    log "Transferring GW.pak..."
    tar_to_remote "${PAK_DIR}" "${DEVICE_EMUS}/${EMU_TAG}.pak"

    # Control scheme + views (global default.cfg + per-game cfgs)
    log "Deploying MAME cfg files..."
    ${SSH} "mkdir -p '${DEVICE_MAME_CFG}'"
    tar --exclude='._*' -C "${CFG_SRC}" -cf - . | ${SSH} "tar -C '${DEVICE_MAME_CFG}' -xf -"

    # Artwork (used only if a view selects it; Internal view ignores it)
    log "Deploying artwork..."
    if ls "${ARTWORK_SRC}"/*.zip > /dev/null 2>&1; then
        ${SSH} "mkdir -p '${DEVICE_MAME_ART}'"
        for f in "${ARTWORK_SRC}"/*.zip; do
            tar --exclude='._*' -C "$(dirname "$f")" -cf - "$(basename "$f")" | \
                ${SSH} "tar -C '${DEVICE_MAME_ART}' -xf -"
        done
    fi

    log "Verifying..."
    ${SSH} "ls -lh '${DEVICE_EMUS}/${EMU_TAG}.pak/' '${DEVICE_EMUS}/${EMU_TAG}.pak/lib/' && echo '--- cfg:' && ls '${DEVICE_MAME_CFG}/'"
}

# --- Main --------------------------------------------------------------------
main() {
    assemble_pak
    deploy_to_device
    log ""
    log "Done! Test on device: Game & Watch (GW) > gnw_ball"
    log "Headless benchmark: ./bench.sh"
}

main "$@"
