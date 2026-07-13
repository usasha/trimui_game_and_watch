#!/bin/sh
# =============================================================================
# Phase A: Deploy a prebuilt MAME libretro core as a NextUI GW.pak
# =============================================================================
# This script is reproducible and version-controlled. It:
#   1. Downloads the prebuilt aarch64 MAME libretro core from libretro buildbot
#   2. Assembles a GW.pak directory (launch.sh + core + default.cfg)
#   3. Deploys GW.pak + artwork + MAME cfg files to the TrimUI Brick via SSH
#
# Prerequisites:
#   - sshpass (brew install sshpass / hudochenkov/sshpass/sshpass)
#   - unzip, curl, tar
#
# Usage:
#   ./deploy_phase_a.sh          # full deploy
#   ./deploy_phase_a.sh --no-download  # skip core download (use cached)
# =============================================================================
set -e

# --- Configuration ----------------------------------------------------------
DEVICE_IP="192.168.1.106"
DEVICE_USER="root"
DEVICE_PASS="tina"
PLATFORM="tg5040"
EMU_TAG="GW"
EMU_EXE="mame"

# Paths on host (this repo)
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
CORE_DIR="${BUILD_DIR}/core_download"
PAK_DIR="${BUILD_DIR}/GW.pak"
ARTWORK_SRC="${REPO_ROOT}/artwork"
CFG_SRC="${REPO_ROOT}/cfg"

# Paths on device
DEVICE_SDCARD="/mnt/SDCARD"
DEVICE_EMUS="${DEVICE_SDCARD}/Emus/${PLATFORM}"
DEVICE_ROMS="${DEVICE_SDCARD}/Roms/Game & Watch (${EMU_TAG})"
DEVICE_USERDATA="${DEVICE_SDCARD}/.userdata/${PLATFORM}"

# Buildbot URL for prebuilt aarch64 MAME core
CORE_URL="https://buildbot.libretro.com/nightly/linux/aarch64/latest/mame_libretro.so.zip"

# --- Helpers ----------------------------------------------------------------
# Device has no scp/rsync — use tar-over-ssh for all transfers
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="sshpass -p ${DEVICE_PASS} ssh ${SSH_OPTS} ${DEVICE_USER}@${DEVICE_IP}"

log() { echo "[deploy] $*"; }

# Transfer a local directory to a remote path via tar-over-ssh
# Usage: tar_to_remote <local_dir> <remote_dest_dir>
tar_to_remote() {
    local local_dir="$1"
    local remote_dir="$2"
    ${SSH} "mkdir -p '${remote_dir}'"
    tar -C "${local_dir}" -cf - . | ${SSH} "tar -C '${remote_dir}' -xf -"
}

# Transfer a single file to a remote path via tar-over-ssh
# Usage: file_to_remote <local_file> <remote_dest_dir>
file_to_remote() {
    local local_file="$1"
    local remote_dir="$2"
    ${SSH} "mkdir -p '${remote_dir}'"
    tar -C "$(dirname "${local_file}")" -cf - "$(basename "${local_file}")" | ${SSH} "tar -C '${remote_dir}' -xf -"
}

# --- Step 1: Download prebuilt core (if needed) -----------------------------
download_core() {
    mkdir -p "${CORE_DIR}"
    if [ -f "${CORE_DIR}/mame_libretro.so" ] && [ "$1" = "--no-download" ]; then
        log "Using cached core: ${CORE_DIR}/mame_libretro.so"
        return
    fi
    log "Downloading prebuilt MAME libretro core (aarch64)..."
    curl -L -o "${CORE_DIR}/mame_libretro.so.zip" "${CORE_URL}"
    (
        cd "${CORE_DIR}"
        unzip -o mame_libretro.so.zip
    )
    log "Core downloaded: $(ls -lh ${CORE_DIR}/mame_libretro.so | awk '{print $5}')"
}

# --- Step 2: Assemble GW.pak locally ----------------------------------------
assemble_pak() {
    log "Assembling GW.pak locally..."
    rm -rf "${PAK_DIR}"
    mkdir -p "${PAK_DIR}"

    # Copy the core
    cp "${CORE_DIR}/mame_libretro.so" "${PAK_DIR}/"

    # Create launch.sh (mirrors FBN.pak pattern)
    cat > "${PAK_DIR}/launch.sh" << 'LAUNCH_EOF'
#!/bin/sh

EMU_EXE=mame
CORES_PATH=$(dirname "$0")

###############################

EMU_TAG=$(basename "$(dirname "$0")" .pak)
ROM="$1"
mkdir -p "$BIOS_PATH/$EMU_TAG"
mkdir -p "$SAVES_PATH/$EMU_TAG"
mkdir -p "$CHEATS_PATH/$EMU_TAG"
HOME="$USERDATA_PATH"
cd "$HOME"
minarch.elf "$CORES_PATH/${EMU_EXE}_libretro.so" "$ROM" &> "$LOGS_PATH/$EMU_TAG.txt"
LAUNCH_EOF
    chmod +x "${PAK_DIR}/launch.sh"

    # Create default.cfg (minarch key bindings)
    cat > "${PAK_DIR}/default.cfg" << 'CFG_EOF'
bind Up = UP
bind Down = DOWN
bind Left = LEFT
bind Right = RIGHT
bind Select = SELECT
bind Start = START
bind X Button = X
bind Y Button = Y
bind B Button = B
bind A Button = A
bind L1 Button = L1
bind L2 Button = L2
bind R1 Button = R1
bind R2 Button = R2
CFG_EOF

    # default-brick.cfg (same layout for Brick hardware)
    cp "${PAK_DIR}/default.cfg" "${PAK_DIR}/default-brick.cfg"

    log "GW.pak assembled at ${PAK_DIR}"
    ls -lh "${PAK_DIR}/"
}

# --- Step 3: Deploy to device -----------------------------------------------
deploy_to_device() {
    log "Deploying to device (${DEVICE_IP})..."

    # Remove old GW.pak if exists, then create fresh
    ${SSH} "rm -rf '${DEVICE_EMUS}/${EMU_TAG}.pak'"

    # Transfer GW.pak (including the 378MB core — this takes a while)
    log "Transferring GW.pak (378MB core — please wait)..."
    tar_to_remote "${PAK_DIR}" "${DEVICE_EMUS}/${EMU_TAG}.pak"

    # Deploy artwork to multiple candidate locations (we'll narrow down after testing)
    # Location 1: $USERDATA_PATH/mame/artwork/ (MAME HOME-based default)
    log "Deploying artwork to userdata/mame/artwork/..."
    ${SSH} "mkdir -p '${DEVICE_USERDATA}/mame/artwork'"
    for f in "${ARTWORK_SRC}"/*.zip; do
        file_to_remote "$f" "${DEVICE_USERDATA}/mame/artwork"
    done

    # Location 2: inside the pak (in case minarch sets system dir to CORES_PATH)
    log "Deploying artwork to GW.pak/artwork/..."
    ${SSH} "mkdir -p '${DEVICE_EMUS}/${EMU_TAG}.pak/artwork'"
    for f in "${ARTWORK_SRC}"/*.zip; do
        file_to_remote "$f" "${DEVICE_EMUS}/${EMU_TAG}.pak/artwork"
    done

    # Deploy MAME cfg files (video view = "Unit and Backdrop")
    log "Deploying MAME cfg files..."
    ${SSH} "mkdir -p '${DEVICE_USERDATA}/mame/cfg'"
    for f in "${CFG_SRC}"/*.cfg; do
        file_to_remote "$f" "${DEVICE_USERDATA}/mame/cfg"
    done

    log "Deployment complete."
}

# --- Step 4: Verify on device -----------------------------------------------
verify_device() {
    log "Verifying on device..."
    ${SSH} "echo '=== GW.pak ===' && ls -lh '${DEVICE_EMUS}/${EMU_TAG}.pak/' && echo '=== artwork (userdata) ===' && ls '${DEVICE_USERDATA}/mame/artwork/' && echo '=== cfg (userdata) ===' && ls '${DEVICE_USERDATA}/mame/cfg/' && echo '=== roms ===' && ls '${DEVICE_ROMS}/'"
}

# --- Main -------------------------------------------------------------------
main() {
    download_core "$1"
    assemble_pak
    deploy_to_device
    verify_device
    log ""
    log "Done! On the device, navigate to: Game & Watch (GW) > gnw_ball"
    log "After testing, check the log with:  ./check_log.sh"
}

main "$@"
