# Credits

AOD ("Age of Dragon") is an open-source project. This file records every third-party
contribution used in the game. It is surfaced in-game on the Credits screen
(PLAN.md phase 1.4) and is a licence obligation, not a courtesy.

Per-asset provenance is tracked in `game/assets/LICENCES.md` and enforced in CI by
`tools/licence_audit.py`.

---

## Art

### 0 A.D. — Wildfire Games
**Used for:** unit, building, terrain and prop sprites, rendered from the project's 3D models to 2D isometric sprite sheets.
**Source:** https://play0ad.com
**Licence:** CC-BY-SA 3.0
**Note:** Derived sprite sheets are themselves distributed under CC-BY-SA 3.0.

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

*None yet — see [ASSET_MISSING.md](ASSET_MISSING.md) §1.6 and §2.6.*

---

## Adding an entry

Any new third-party asset, addon or code contribution must be added here **in the same
change that introduces it**, together with `game/assets/LICENCES.md`. Per PLAN.md §13.1:
credit only what is actually used, and only use licences compatible with an open-source
CC-BY-SA art release.
