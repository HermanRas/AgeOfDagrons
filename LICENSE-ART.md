# Art & audio licence

The AOD repository is under **two** licences. This file covers the second one.

| What | Licence | Where |
|---|---|---|
| **Software** — GDScript, scenes, `project.godot`, `tools/`, documentation | **MIT** | [`LICENSE`](LICENSE) |
| **Art & audio** — sprites, atlases, terrain, animations, sound effects, music | **CC-BY-SA 3.0** | this file |

The split is deliberate. See [PLAN.md](PLAN.md) §2.3: only the art is copyleft.

---

## Why the art is CC-BY-SA 3.0

AOD's sprites are **rendered from [0 A.D.](https://play0ad.com)'s 3D models**, which
Wildfire Games release under Creative Commons Attribution-ShareAlike 3.0. That licence
is *share-alike*: a derived work must carry the same licence. Our 2D isometric sprite
sheets are derived works, so they are CC-BY-SA 3.0 and there is no choice in the matter.

Full text: <http://creativecommons.org/licenses/by-sa/3.0/>

## Required attribution

Reusing AOD art means reproducing all three of the following, **verbatim and
unabbreviated**. These exact elements are required by `art/LICENSE.txt` and
`audio/LICENSE.txt` in the 0 A.D. repository:

> Original author: **Wildfire Games** — <http://www.wildfiregames.com/>
> Licence: **Creative Commons Attribution-ShareAlike 3.0** — <http://creativecommons.org/licenses/by-sa/3.0/>

…plus a statement of what was changed. Ours is recorded in [CREDITS.md](CREDITS.md):
3D meshes and animations were rendered to 2D isometric sprite sheets and packed into
texture atlases; audio was re-encoded and re-mixed.

## What this means in practice

- **Using AOD's code** in your own project: MIT. Keep the copyright notice, do what you like.
- **Using AOD's art** in your own project: CC-BY-SA 3.0. Attribute as above, and release
  your derived art under CC-BY-SA 3.0 too.
- **Shipping a fork of the whole game**: the code stays MIT, the art stays CC-BY-SA 3.0.
  They do not merge into one licence.
- **Re-skinning AOD with your own art**: your art is yours, under whatever licence you
  choose. This is a supported path — see [Docs/README.md](Docs/README.md#6-adding-assets-and-re-skinning)
  — because gameplay code never names an asset file.

## Third-party material with different terms

Not everything in or around this repo is covered by the two licences above:

| Item | Licence | Note |
|---|---|---|
| Godot Engine | MIT | Not distributed here; you install it |
| Kibyra UI packs (`UI_Sprites/`) | Free use, **redistribution forbidden** | Deliberately **not committed** — each developer downloads them. See [`UI_Sprites/README.md`](UI_Sprites/README.md) |
| [isobake](https://github.com/HermanRas/blender_3d_to_2d_isobake) | GPL-2.0-or-later | Separate repo, build-time only, ships nothing into the game |
| `blender_pyrogenesis_importer` | GPL-2.0 | Build-time only |

Every third-party item in use is recorded in [CREDITS.md](CREDITS.md). Per-asset
provenance will be tracked in `game/assets/LICENCES.md` and enforced by
`tools/licence_audit.py` — both land at phase 0.2c and do not exist yet.
