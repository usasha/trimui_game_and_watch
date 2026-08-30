# brick_gw — Game & Watch on TrimUI Brick (GW_MAME.pak for NextUI)

Runs Game & Watch on the TrimUI Brick (tg5040) using a **standalone native
MAME 0.223** binary (not a libretro core), packaged as a NextUI
`GW_MAME.pak` and distributed as `GW_MAME.pakz` (manual / Pak Store).

## Repo layout

- `mame_build/` — everything: Docker build of the MAME subset binary,
  deploy/package/release scripts, launcher, controls cfg, performance
  patches, docs
- `artwork/` — optional case-artwork zips (kept local, **not** shipped:
  gitignored, ~31 MB, unused by the default Internal view)
- `pak.json` — Pak Store manifest (name/version/release asset must stay in
  sync with every tagged release)

## Quick start

    cd mame_build
    ./build.sh       # Docker build → out/mame + out/lib/  (~6 GB free disk)
    ./deploy.sh      # assemble GW_MAME.pak, upload to device via SSH
                     # requires DEVICE_IP / DEVICE_PASS env vars

See `mame_build/README.md` for the full guide: build flags, controls,
performance patches, packaging and release.

## Releasing (Pak Store)

    ./release.sh v1.0.0      # builds if needed, packages, creates GitHub release

1. Bump `version` (and `changelog`) in `../pak.json`, tag, release.
2. Install `dist/GW_MAME.pakz` on-device and test.
3. Submit to the Pak Store issue form with the repo URL.

## Performance

The G&W SVG screens are large (1671x1080) and dominated the CPU on the
Brick's Cortex-A53. Two patches in `mame_build/patches/` (skip-unchanged
frames + half-resolution SVG screen) plus `-frameskip 4` in the launcher
take gnw_ball from ~46% to ~90% of full speed.

## Licensing

The distributed binary is a modified build of MAME 0.223 (GPL-2.0+).
Source, exact upstream tag, and applied patches are in `mame_build/`
(`pins.env`, `patches/`). See `LICENSE`.