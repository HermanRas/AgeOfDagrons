# Per-asset provenance

Every asset this project ships must appear in this file. "Ships" means one of two
things:

1. **Inside the APK** — anything under `game/assets/`.
2. **Inside the downloadable art pack** — every atlas baked by a recipe in
   `tools/recipes/` (PLAN.md §3.2). The atlases are not committed, so the recipe is
   the durable record of what we ship and where it came from.

Checked by [`tools/licence_audit.py`](../../tools/licence_audit.py), which exits
non-zero on anything undeclared:

```
python tools/licence_audit.py
```

**Nothing runs that for you** — this repo has no CI (PLAN.md §1.2). Run it before a
release and whenever you add an asset. Attribution is a licence obligation, so an
undeclared asset is a licence violation, not untidiness.

Project-level credit lives in [`CREDITS.md`](../../CREDITS.md); this file is the
per-asset detail behind it.

---

## 0 A.D. — the required attribution

Everything in the generated table below derives from **0 A.D.** by rendering Wildfire
Games' 3D models to 2D isometric sprite atlases. Their `art/LICENSE.txt` requires three
things **verbatim**, and the audit fails if any of them is missing or shortened:

- Licence: **Creative Commons Attribution-ShareAlike 3.0** — http://creativecommons.org/licenses/by-sa/3.0/
- Original author: **Wildfire Games**
- Author link: http://www.wildfiregames.com/

**Modification made:** 3D meshes, textures and animations were rendered through a fixed
isometric orthographic camera and packed into trimmed texture atlases. CC-BY-SA 3.0 is
share-alike, so **our derived atlases are themselves CC-BY-SA 3.0** — see
[`LICENSE-ART.md`](../../LICENSE-ART.md). The game code is MIT; the two do not merge.

---

## Art pack — baked atlases

One row per recipe. Regenerate with `python tools/licence_audit.py --write`.

<!-- BEGIN GENERATED: recipes -->

<!-- Do not edit by hand. Regenerate with:
       python tools/licence_audit.py --write -->

| Asset ID | Source file | Origin | Licence |
|---|---|---|---|
| `vis.deer` | `deer.toml` | `art/actors/fauna/deer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_4x4` | `foundation_4x4.toml` | `art/actors/structures/fndn_4x4.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_8x8` | `foundation_8x8.toml` | `art/actors/structures/fndn_8x8.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.gold_mine` | `gold_mine.toml` | `art/actors/geology/metalmine_alpine.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.house` | `house.toml` | `art/actors/structures/hellenes/house.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_3x3` | `rubble_3x3.toml` | `art/actors/structures/destruct_stone_3x3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_town_center` | `rubble_town_center.toml` | `art/actors/structures/destruct_hele_cc.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.grass` | `terrain_grass.toml` | `grass/grass1.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.town_center` | `town_center.toml` | `art/actors/structures/athenians/civil_centre.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree` | `tree_oak.toml` | `art/actors/flora/trees/oak.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager` | `villager.toml` | `art/actors/units/athenians/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |

<!-- END GENERATED: recipes -->

---

## Shipped inside the APK

Assets committed under `game/assets/`. These are **not** from 0 A.D. and each needs its
own provenance.

| File | What | Origin | Licence |
|---|---|---|---|
| `icons/icon_16x16.png`, `icons/icon_32x32.png`, `icons/icon_48x48.png`, `icons/icon_64x64.png`, `icons/icon_128x128.png`, `icons/icon_256x256.png`, `icons/icon_1024x1024.png`, `icons/icon.ico` | Application launcher icon, all sizes | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/boot_splash.png` | Boot splash image | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/res_food.png`, `ui/icons/res_wood.png`, `ui/icons/res_gold.png`, `ui/icons/res_stone.png`, `ui/icons/res_villagers.png` | Resource-bar icons, 100×100 RGBA (ASSET_MISSING.md §1.5, phase 7.1) | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/act_move.png`, `ui/icons/act_stop.png`, `ui/icons/act_build.png`, `ui/icons/act_attack.png`, `ui/icons/act_guard.png`, `ui/icons/act_destroy.png`, `ui/icons/act_garrison.png`, `ui/icons/act_enter.png`, `ui/icons/act_leave.png`, `ui/icons/act_exit.png` | Action-panel icons, 100×100 RGBA (phase 4.4/8.x) | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/hud_techtree.png`, `ui/icons/hud_score.png`, `ui/icons/hud_trade.png`, `ui/icons/hud_chat.png`, `ui/icons/hud_settings.png` | HUD buttons around the minimap panel, 100×100 RGBA (phase 8.x; `hud_settings` currently unused) | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |

> ### On the AI-generated assets
>
> All of the above were generated by the project owner with Google Gemini on a paid
> account — the launcher icon, the boot splash and the HUD icon set. Recorded
> explicitly rather than left as "ours", because generated assets carry a different set of
> facts from drawn ones and the difference is invisible in the file itself.
>
> **Why this is fine to ship.** Google's generative-AI terms do not claim ownership of
> output; what the service produces for you is yours to use, including commercially. No
> third party's rights are being relied on here, so nothing needs crediting to anyone else
> and there is no copyleft to propagate. These are **not** 0 A.D. material and carry none
> of its CC-BY-SA obligations.
>
> **The one caveat worth writing down.** In several jurisdictions — the US most clearly —
> purely AI-generated images may attract no copyright at all, because copyright wants a
> human author. That does not stop us shipping them; it means they may not be *ours to
> restrict*, so treat them as effectively unprotectable rather than as MIT-licensed
> project code. Practically this only matters if someone else reuses the icon and we would
> want to object. If that ever matters, replace them with drawn originals.
>
> **If they are regenerated or replaced,** update this row in the same change. Note also
> that Gemini output carries Google's SynthID watermark, so these files are detectable as
> AI-generated regardless of what this file says.

---

## Not shipped, and why

Recording these matters as much as recording what does ship — the reason they are absent
is a licence constraint, and someone will otherwise "fix" it by committing them.

| What | Where | Why it is not committed |
|---|---|---|
| Kibyra UI packs | `UI_Sprites/` | Free for personal and commercial use, but redistributing the original files is **not** permitted. Each developer downloads them — see [`UI_Sprites/README.md`](../../UI_Sprites/README.md) |
| HUD icon source sheets | `Icons/Icons_sheet_500x500.png`, `Icons/MapIcons_500x100.png` | The sheets the individual 100×100 icons were cut from, plus `Icons/icons.txt` and `Icons/map_icons.txt` describing them. Working sources, like the root `UI_Design*.jpg` references — the cut icons under `game/assets/ui/icons/` are what ships. Kept so the 5×5 sheet's remaining empty slots can be filled from the same artwork |
| 0 A.D. source art | `art_source/` (outside the repo) | ~11 GB shallow clone; a build input, never redistributed |
| Baked atlases | `art_work/out/` (outside the repo) | Build output. Reproducible from the committed recipes plus `isobake` |

---

## Adding an asset

Add it here **in the same change that introduces it**, per PLAN.md §13.1: credit only
what is actually used, and only use licences compatible with an open-source CC-BY-SA art
release. For a new baked atlas, fill in the recipe's `[attribution]` block and run
`--write`; the table above is generated from exactly that.
