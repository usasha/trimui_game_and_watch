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

## Performance patches

`build.sh` auto-applies every script in `patches/` to the MAME source
before compiling, then verifies the edits took effect (build fails if a
patch cannot be applied). All patches are idempotent.

- `patches/0001_svg_skip_unchanged.py` (`src/emu/screen.cpp`)
  The G&W SVG screen was re-rendered every frame even when no segment
  changed: a full-screen background memcpy (~7.2 MB at 1671x1080) plus
  scalar blits of every lit segment. The patch makes `svg_renderer::render`
  return `UPDATE_HAS_NOT_CHANGED` when no output changed since the last
  committed draw, so the frame skips both the re-render and the texture
  re-upload. Commit-tracking via `screen.m_curbitmap` keeps it correct
  when combined with frameskip.
- `patches/0002_svg_half_res.py` (`src/mame/drivers/hh_sm510.cpp`)
  Halves the SVG screen size in `mcfg_svg_screen()` (1671x1080 ->
  835x540), cutting every resolution-scaled cost 4x (render memcpy,
  blits, texture upload, GPU source read). LCD segments are large flat
  shapes, so the difference is invisible once scaled to the 1024x768
  panel.

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
| Start | open MAME in-game menu (UI Configure - the TAB key in 0.223) |

In the MAME menu: D-pad navigates, A confirms (UI Select/Enter), X goes
back, X on the main menu quits the game.

The mapping lives in `mame_build/cfg/default.cfg` as MAME type-based
defaults. Device button->SDL order: `0=B 1=A 2=Y 3=X 6=Select 7=Start`.
MAME input tokens are player-prefixed (`P1_JOYSTICK_LEFT`,
`P1_BUTTON1`, `P1_SELECT`) except player-0 types (`START1`, `START2`,
`UI_CANCEL`) - see `src/emu/inpttype.ipp` token rules.

## Performance notes

- `-video accel` uses the SDL accelerated (EGL) renderer - about 2x faster
  than the software renderer on the Brick.
- With the patches above + `-frameskip 4` in `launch.sh`, gnw_ball runs at
  ~90% of full speed (measured via the `bench_seconds` mechanism). The
  frameskip skips the OSD present on 4 of 5 frames (the SVG screen update
  is skipped by MAME's own frameskip path too); the patches remove the
  redundant re-render/upload work that remains.
- Before the patches, the LCD SVG render (1671x1080) dominated and the
  Internal view ran at ~46%, the full console view at ~25%.

## Upstream status + future speedup ideas

MAME git history was surveyed (Aug 2026) for post-0.223 G&W/SVG rendering
work. Nothing worth porting:

- The only upstream attempt at SVG skip-unchanged rendering
  (`svg_renderer: Flag when output contents have not changed`, Nov 2021,
  PR #8791) was **reverted 2 days later** - it caused input lag / frame
  pacing jitter on tight games (gnw_dkjr) because video.cpp skips
  throttle/speed recompute on "unchanged" frames. Our patch 0001 is that
  same idea plus a commit-tracking guard (`m_curbitmap`) it lacked; the
  input-lag caveat still applies - check 0001 first if controls feel laggy.
- nanosvg re-base (2023) and all later render/screen/driver changes are
  correctness or refactors only; no renderer threading was ever added.

Remaining speedup approaches, roughly in order of effort:

1. Full console view: ship a stripped custom `.lay` (drop dust/gradient/
   bubbles/fix layers; keep backdrop + unit + screen) - artwork-zip only,
   no rebuild.
2. 30 Hz screen refresh (`set_refresh_hz(30)` in hh_sm510) - halves all
   per-second render work; game logic is MCU-clock-driven so speed is
   unaffected.
3. Build flags: `OPTIMIZE=3` + `-mtune=cortex-a53` (recover the ~30% the
   old mystery binary had over this build).
4. NEON blit/upload loops for the hot scalar paths (svg segment blits,
   texture row copies).
5. Structural: custom mini-frontend driving MAME headless (`-video none`)
   and rendering segments directly via SDL output notifiers - guaranteed
   full speed, weeks of work.

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
