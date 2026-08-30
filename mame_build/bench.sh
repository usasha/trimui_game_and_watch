#!/bin/sh
# =============================================================================
# Headless benchmark of native MAME on the device.
# Runs the game for N seconds with the device's mali SDL video driver and
# reports MAME's built-in average speed. The screen shows the game briefly;
# the device sleeps if left idle afterwards.
#
# Usage: DEVICE_IP=... DEVICE_PASS=... ./bench.sh [game=gnw_ball] [seconds=30]
# =============================================================================
set -e

DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-}"
PLATFORM="tg5040"
GAME="${1:-gnw_ball}"
SECONDS="${2:-30}"

if [ -z "${DEVICE_IP}" ] || [ -z "${DEVICE_PASS}" ]; then
    echo "[bench ERROR] DEVICE_IP and DEVICE_PASS must be set" >&2
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=40"
SSH="sshpass -p ${DEVICE_PASS} ssh ${SSH_OPTS} ${DEVICE_USER}@${DEVICE_IP}"

PAK="/mnt/SDCARD/Emus/${PLATFORM}/GW_MAME.pak"
ROMS="/mnt/SDCARD/Roms/Game & Watch MAME (GW_MAME)"
MAME_HOME="/mnt/SDCARD/.userdata/${PLATFORM}/mame"

echo "[bench] ${GAME} for ${SECONDS}s (device mali fbdev video, no audio)"
${SSH} "cd '${PAK}' && \
    HOME='${MAME_HOME}' \
    SDL_VIDEODRIVER=mali \
    LD_LIBRARY_PATH=/usr/trimui/lib:'${PAK}/lib' \
    ./mame '${GAME}' \
        -rompath '${ROMS}' \
        -artpath '${MAME_HOME}/artwork' \
        -cfg_directory '${PAK}/cfg' \
        -video accel -sound none -skip_gameinfo \
        -str ${SECONDS} -verbose 2>&1 | grep -E 'Video: |Average speed|Sound: |Joystick|Input: Adding|Starting|Initialization failed|error|SDL'"