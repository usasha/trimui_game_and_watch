# brick_gw — Game & Watch on TrimUI Brick

Runs Game & Watch on the TrimUI Brick (tg5040) using a **standalone native
MAME 0.223** binary (not a libretro core), packaged as a NextUI `GW.pak`.

## Repo layout

- `mame_build/` — everything: Docker build of the MAME subset binary,
  deploy script, pak launcher, controls cfg, performance patches, docs
- `artwork/` — optional case-artwork zips (deployed by `mame_build/deploy.sh`)

## Quick start

    cd mame_build
    ./build.sh       # Docker build → out/mame + out/lib/
    ./deploy.sh      # assemble GW.pak, upload to device via SSH

See `mame_build/README.md` for the full guide: build flags, controls,
performance patches, benchmarking (`bench.sh`), and diagnostics.

## Performance

The G&W SVG screens are large (1671x1080) and dominated the CPU on the
Brick's Cortex-A53. Two patches in `mame_build/patches/` (skip-unchanged
frames + half-resolution SVG screen) plus `-frameskip 4` in the launcher
take gnw_ball from ~46% to ~90% of full speed.
