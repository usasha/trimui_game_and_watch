#!/bin/sh
# =============================================================================
# Deploy GW_MAME.pak to the TrimUI Brick via SSH (tar-over-ssh)
#
# Deploys the standalone native MAME pak:
#   Emus/tg5040/GW_MAME.pak/  -> mame, lib/, launch.sh, cfg/, README, LICENSE
# Optional case-artwork stays in $USERDATA_PATH/mame/artwork (already
# deployed; the pak itself ships without artwork).
#
# Prerequisites:
#   - sshpass, tar
#   - mame_build/out/mame + mame_build/out/lib/ built by build.sh
#   - device reachable: export DEVICE_IP (and DEVICE_USER/DEVICE_PASS if not
#     the defaults below - these are your personal-device settings, they must
#     NOT be hardcoded here because the repo is public)
#
# Usage:
#   DEVICE_IP=192.168.1.100 ./deploy.sh
# =============================================================================
set -e

DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-}"
PLATFORM="tg5040"
EMU_TAG="GW_MAME"

if [ -z "${DEVICE_IP}" ] || [ -z "${DEVICE_PASS}" ]; then
    err "DEVICE_IP and DEVICE_PASS must be set (e.g. DEVICE_IP=192.168.1.100 DEVICE_PASS=... ./deploy.sh)"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${BUILD_ROOT}/out"
PAK_DIR="${OUT_DIR}/${EMU_TAG}.pak"
ARTWORK_SRC="${REPO_ROOT}/artwork"

# Paths on device
DEVICE_SDCARD="/mnt/SDCARD"
DEVICE_EMUS="${DEVICE_SDCARD}/Emus/${PLATFORM}"
DEVICE_USERDATA="${DEVICE_SDCARD}/.userdata/${PLATFORM}"
DEVICE_MAME_ART="${DEVICE_USERDATA}/mame/artwork"

# Device SSH is slow (dropbear) - generous connect timeout
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=40"
SSH="sshpass -p ${DEVICE_PASS} ssh ${SSH_OPTS} ${DEVICE_USER}@${DEVICE_IP}"

log() { echo "[deploy] $*"; }
err() { echo "[deploy ERROR] $*" >&2; }

# shellcheck source=pak_lib.sh
. "${BUILD_ROOT}/pak_lib.sh"

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

# --- Deploy ------------------------------------------------------------------
deploy_to_device() {
    log "Deploying to device (${DEVICE_IP})..."
    ${SSH} "rm -rf '${DEVICE_EMUS}/${EMU_TAG}.pak'"
    log "Transferring ${EMU_TAG}.pak..."
    tar_to_remote "${PAK_DIR}" "${DEVICE_EMUS}/${EMU_TAG}.pak"

    # Optional case-artwork is NOT bundled with the pak. If artwork zips exist
    # locally, deploy them to userdata so views other than Internal find them.
    if ls "${ARTWORK_SRC}"/*.zip > /dev/null 2>&1; then
        log "Deploying optional artwork..."
        ${SSH} "mkdir -p '${DEVICE_MAME_ART}'"
        for f in "${ARTWORK_SRC}"/*.zip; do
            tar --exclude='._*' -C "$(dirname "$f")" -cf - "$(basename "$f")" | \
                ${SSH} "tar -C '${DEVICE_MAME_ART}' -xf -"
        done
    fi

    log "Verifying..."
    ${SSH} "ls -lh '${DEVICE_EMUS}/${EMU_TAG}.pak/' '${DEVICE_EMUS}/${EMU_TAG}.pak/lib/' '${DEVICE_EMUS}/${EMU_TAG}.pak/cfg/'"
}

# --- Main --------------------------------------------------------------------
main() {
    assemble_pak
    deploy_to_device
    log ""
    log "Done! Test on device: Game & Watch MAME (GW_MAME) > gnw_ball"
    log "Headless benchmark: ./bench.sh"
}

main "$@"