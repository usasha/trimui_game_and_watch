#!/bin/sh
# =============================================================================
# GW.pak launcher: native MAME 0.223 standalone emulator for Game & Watch
#
# Standalone pak - no NextUI in-game menu / resume / quicksave integration.
# Quit back to NextUI with the X button (UI Cancel binding in cfg files).
# Brightness/volume restored by syncsettings.elf.
#
# Expects NextUI env: $ROM $PLATFORM $SDCARD_PATH $USERDATA_PATH $LOGS_PATH
#
# Benchmark support (dev): if $USERDATA_PATH/mame/bench_seconds exists,
# mame runs headless-style for that many seconds and prints Average speed
# to the log. Useful for UI-launched performance testing.
# =============================================================================

EMU_TAG=$(basename "$(dirname "$0")" .pak)
PAK_DIR=$(dirname "$0")
ROM="$1"
GAME=$(basename "$ROM" .zip)

# Bundled libs (SDL2_ttf/fontconfig chain) + the device's own SDL2 from the
# stock firmware (/usr/trimui/lib) which has the "mali" fbdev video driver.
# The device SDL2 must come FIRST so its libSDL2-2.0.so.0 wins.
export LD_LIBRARY_PATH="/usr/trimui/lib:$PAK_DIR/lib:$LD_LIBRARY_PATH"
export SDL_VIDEODRIVER=mali
export SDL_AUDIODRIVER=alsa

# MAME HOME + config/artwork locations on the SD card
export HOME="$USERDATA_PATH/mame"
mkdir -p "$HOME"
mkdir -p "$USERDATA_PATH/mame/cfg" "$USERDATA_PATH/mame/artwork"

# Restore NextUI brightness/volume around the standalone binary
if [ -f "$SDCARD_PATH/.system/$PLATFORM/bin/syncsettings.elf" ]; then
    "$SDCARD_PATH/.system/$PLATFORM/bin/syncsettings.elf" &
fi

cd "$PAK_DIR"

BENCH=""
if [ -f "$USERDATA_PATH/mame/bench_seconds" ]; then
    BENCH="-str $(cat "$USERDATA_PATH/mame/bench_seconds") -artpath /nonexistent"
fi

# Input debug mode (dev): if this file exists, run mame with -verbose so the
# INPDEBUG event logging (see input_sdl.cpp) shows what MAME receives.
if [ -f "$USERDATA_PATH/mame/inputtest" ]; then
    ./mame "$GAME" \
        -rompath "$(dirname "$ROM")" \
        -artpath /nonexistent \
        -video accel \
        -sound none \
        -skip_gameinfo \
        -verbose \
        -str 30 \
        > /mnt/SDCARD/.userdata/tg5040/logs/GW.txt 2>&1
    exit 0
fi

./mame "$GAME" \
    -rompath "$(dirname "$ROM")" \
    -artpath "$USERDATA_PATH/mame/artwork" \
    -cfg_directory "$USERDATA_PATH/mame/cfg" \
    -video accel \
    -view Internal \
    -sound sdl \
    -skip_gameinfo \
    -autosave \
    -sleep \
    $BENCH \
    > "$LOGS_PATH/$EMU_TAG.txt" 2>&1
