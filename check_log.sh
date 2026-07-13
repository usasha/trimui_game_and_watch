#!/bin/sh
# =============================================================================
# Helper: Check the GW emulator log on the device
# =============================================================================
set -e
DEVICE_IP="192.168.1.106"
DEVICE_USER="root"
DEVICE_PASS="tina"
PLATFORM="tg5040"
EMU_TAG="GW"

SSH="sshpass -p ${DEVICE_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${DEVICE_USER}@${DEVICE_IP}"

${SSH} "cat '/mnt/SDCARD/.userdata/${PLATFORM}/logs/${EMU_TAG}.txt' 2>/dev/null || echo '(no log file yet)'"
