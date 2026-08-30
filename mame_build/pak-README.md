# GW_MAME.pak — Game & Watch on TrimUI (native MAME)

Game & Watch for NextUI via a **standalone native MAME 0.223** binary
(G&W-only source subset, aarch64, with SVG-rendering performance patches).
Not a libretro core — no NextUI resume/quicksave integration (quit with X).

## Install

1. Copy/extract the `.pakz` at the root of your SD card (creates
   `Emus/tg5040/GW_MAME.pak/` and `Roms/Game & Watch MAME (GW_MAME)/`), or
   install via the NextUI **Pak Store**.
2. Put your MAME Game & Watch romset zips in
   `Roms/Game & Watch MAME (GW_MAME)/` (e.g. `gnw_ball.zip`, `gnw_mariocm.zip`).
3. Reinsert the SD card; "Game & Watch MAME" appears in the system list.

## Workarounds and caveats

- Brightness/volume are restored by NextUI's `syncsettings.elf` on launch.
- If the screen stays black after MAME is killed abruptly, reboot the device
  (mali fbdev video driver quirk).
- Standalone pak: no resume, quicksave or in-game menu integration; the MAME
  menu opens with **Start** instead.

## Controls (global scheme, all G&W games)

| Brick button | Action                            |
|--------------|-----------------------------------|
| D-pad        | movement                          |
| A            | action button (if the game has one) |
| Y            | Game A                            |
| B            | Game B                            |
| Select       | Time                              |
| X            | quit back to NextUI               |
| Start        | MAME in-game menu                 |

In the MAME menu: D-pad navigates, A confirms, X goes back / quits.

Settings changed in the MAME menu are stored in this pak's `cfg/` and reset
when the pak is updated or reinstalled.

## Optional case artwork

The pak ships without artwork. If you want the full-console view (much slower
than the default Internal LCD view), drop MAME artwork zips
(`gnw_ball.zip`, ...) into `.userdata/tg5040/mame/artwork/` on the SD card.
Both the artwork and this pak are built on MAME resources — see the project
repo for build details and licensing.