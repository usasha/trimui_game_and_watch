# Native MAME for Game & Watch on TrimUI Brick (NextUI / tg5040)

Standalone MAME 0.223 binary for playing Game & Watch on the TrimUI Brick,
packaged as a NextUI `GW.pak`.

## Why this exists

NextUI has no Game & Watch emulator. The libretro MAME core runs too slowly
(its 1671x1080 SVG LCD rendering is heavy, and the core + frontend overhead
does not help). This pak runs a **native MAME 0.223** binary built for
aarch64 with a G&W-only source subset, using the device's own stock
SDL2 (`/usr/trimui/lib`, "mali" fbdev video driver).

## Reproducing the build

Requirements: macOS with Docker (or any docker host), ~6 GB free disk.

    cd mame_build
    ./build.sh            # builds Docker image + MAME subset binary
    # artifacts land in mame_build/out/  (mame + lib/)

Pinned in `pins.env`:
- `MAME_TAG=mame0223` (MAME 0.223 - oldest with full G&W support)
- `MAME_SOURCES=src/mame/drivers/hh_sm510.cpp` (G&W-only subset, ~50 MB)
- `DOCKER_BASE_IMAGE=ubuntu:20.04` (glibc 2.31 <= device's ~2.33)
- `SDL2_VERSION=2.0.20` (built from source; only used as a build-time dep
  - the pak actually runs the *device's* SDL2 from /usr/trimui/lib)
- `OPTIMIZE=2`, `BUILD_JOBS=4` (8 GB Docker VM safety)

Build flags of note:
- `ARCHOPTS="-DASMJIT_BUILD_X86=1 -UASMJIT_BUILD_HOST"` - the vendored
  asmjit only ships the x86 backend; on aarch64 it would try to include
  the missing arm.h otherwise.
- `LDOPTS="-static-libstdc++ -static-libgcc -fuse-ld=lld"` - static C++
  runtime; lld keeps the final link within the 8 GB VM.
- `NO_X11=1 NO_OPENGL=1` etc. - no desktop video/audio deps.

## Deploying

    ./deploy.sh           # assembles + uploads GW.pak, cfg files, artwork

The device must be reachable via SSH (default `root@192.168.1.107`,
override with `DEVICE_IP=...`). This replaces `Emus/tg5040/GW.pak` and
writes:
- `Emus/tg5040/GW.pak/` - `mame`, `lib/` (SDL2_ttf/fontconfig chain),
  `launch.sh`
- `.userdata/tg5040/mame/cfg/` - `default.cfg` (global controls),
  `gnw_ball.cfg`, `gnw_mariocm.cfg`, `gnw_fire.cfg` (Internal view)
- `.userdata/tg5040/mame/artwork/` - optional artwork zips

## Controls (global scheme, all G&W games)

| Brick button | Action |
|---|---|
| D-pad | movement (JOYSTICK_*: hat remap) |
| A | action button (if the game has one) |
| Y | Game A |
| B | Game B |
| Select | Time |
| X | quit back to NextUI (UI Cancel) |
| Start | open MAME in-game menu (UI Select) |

In the MAME menu: D-pad navigates, A confirms, X goes back, X on the
main menu quits the game.

The mapping lives in `mame_build/cfg/default.cfg` as MAME type-based
defaults. Device button->SDL order: `0=B 1=A 2=Y 3=X 6=Select 7=Start`.
MAME input tokens are player-prefixed (`P1_JOYSTICK_LEFT`,
`P1_BUTTON1`, `P1_SELECT`) except player-0 types (`START1`, `START2`,
`UI_CANCEL`) - see `src/emu/inpttype.ipp` token rules.

## Performance notes

- `-video accel` uses the SDL accelerated (EGL) renderer - about 2x faster
  than the software renderer on the Brick.
- Expect ~35% of full speed in the default view with artwork; the Internal
  view (no artwork) is lighter. The LCD SVG render (1671x1080) dominates.
  G&W games remain playable at these rates (low-motion LCD games).

## Diagnostics

- `bench.sh [game] [seconds]` - headless speed benchmark over SSH
- `sdl_present_test.c`, `joydump.c` - SDL present/joystick debug tools
  (build with the SDK SDL2 headers; run inside the pak via the
  `inputtest` flag in `launch.sh`)
- The binary has lightweight `INPDEBUG` event logging in
  `input_sdl.cpp` (visible with `-verbose`).

## Caveats

- Standalone pak: no NextUI resume/quicksave/in-game-menu integration.
- The "mali" SDL video driver can wedge the display if MAME is killed
  abruptly (SIGKILL) - reboot the device if the screen stays black.
- NextUI auto-sleep can kick in during idle benchmark sessions.
