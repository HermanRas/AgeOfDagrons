# Credits

AOD ("Age of Dragon") is an open-source project. This file records every third-party
contribution used in the game. It is surfaced in-game on the Credits screen
(PLAN.md phase 1.4) and is a licence obligation, not a courtesy.

Per-asset provenance is tracked in `game/assets/LICENCES.md` and enforced in CI by
`tools/licence_audit.py`.

---

## Art

### 0 A.D. — Wildfire Games

Original author: **Wildfire Games** — http://www.wildfiregames.com/
Licence: **Creative Commons Attribution-ShareAlike 3.0** — http://creativecommons.org/licenses/by-sa/3.0/
Project home: https://play0ad.com

**Used for:** unit, building, terrain and prop sprites, rendered from Wildfire Games'
3D models to 2D isometric sprite sheets; and sound effects and music.

**Modifications:** 3D meshes and animations were rendered to 2D isometric sprite sheets
and packed into texture atlases. Audio was re-encoded and re-mixed. All such derived
works are released under CC-BY-SA 3.0, as the licence requires.

> The three elements above — the CC-BY-SA 3.0 link, the name "Wildfire Games", and the
> wildfiregames.com link — are required verbatim by `art/LICENSE.txt` and
> `audio/LICENSE.txt` in the 0 A.D. repository. Do not abbreviate them.

> *Status: planned. Nothing from 0 A.D. is in the project yet — see [ASSET_MISSING.md](ASSET_MISSING.md).*

### Kibyra — UI packs
**Used for:** UI chrome (panels, buttons, bars, frames, icons) and fonts.
**Source:** https://kibyra.itch.io/ui-fonts-dragon-huds-pack · https://kibyra.itch.io/free-medieval-fantasy-ui-pack
**Licence:** Free to download; personal and commercial use permitted; redistribution of the original files **not** permitted.
**Note:** Pack files are not redistributed by this project — see [`UI_Sprites/README.md`](UI_Sprites/README.md).

---

## Engine & libraries

### Godot Engine
**Source:** https://godotengine.org
**Licence:** MIT

---

## Audio

Sourced from **0 A.D.** — see the entry under *Art* above; the same three-part attribution
applies to `audio/` as to `art/`.

*None integrated yet — see [ASSET_MISSING.md](ASSET_MISSING.md) §1.6 and §2.6.*

---

## Tools

These are build-time only and ship nothing into the game, but are credited as used.

| Tool | Source | Licence |
|---|---|---|
| **blender_pyrogenesis_importer** — Stanley Sweet | https://github.com/StanleySweet/blender_pyrogenesis_importer | GPL-2.0 |
| **blender_directional_spritesheets** — Maghwyn | https://github.com/Maghwyn/blender_directional_spritesheets | MIT |
| **GdUnit4** | https://github.com/godot-gdunit-labs/gdUnit4 | MIT |
| **Blender** | https://www.blender.org | GPL |

---

## Adding an entry

Any new third-party asset, addon or code contribution must be added here **in the same
change that introduces it**, together with `game/assets/LICENCES.md`. Per PLAN.md §13.1:
credit only what is actually used, and only use licences compatible with an open-source
CC-BY-SA art release.
