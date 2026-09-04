# Art & audio licence

The AOD repository is under **two** licences, plus a third category that is not a licence
at all. This file covers the second, and explains the third.

| What | Licence | Where |
|---|---|---|
| **Software** — GDScript, scenes, `project.godot`, `tools/`, documentation | **MIT** | [`LICENSE`](LICENSE) |
| **Art & audio** — sprites, atlases, terrain, animations, sound effects, music | **CC-BY-SA 3.0** | this file |
| **AI-generated UI art** — launcher icon, boot splash, HUD icon set, the HOW TO PLAY pages | **probably no copyright at all** — see below | [`GeminiCopyRight.md`](GeminiCopyRight.md) |

The split is deliberate. See [PLAN.md](PLAN.md) §2.3: only the art is copyleft.

⚠️ **THE THIRD ROW IS NOT A THIRD LICENCE AND MUST NOT BE WRITTEN AS ONE.** Google's
[Terms of Service](https://policies.google.com/terms) (effective 30 July 2026) do not claim
ownership of what its services generate, and commercial use is permitted — so these files
are ours to ship. But US law (Copyright Office registration guidance, **88 Fed. Reg.
16,190**; *Thaler v. Perlmutter*) holds that purely AI-generated material is not
registrable, because copyright wants a human author. **You cannot licence what you may not
own**, so the honest description is *effectively unprotectable*, not "MIT". The full
citation, with dates and the tier that applies, is [`GeminiCopyRight.md`](GeminiCopyRight.md);
the per-file list is [`game/assets/LICENCES.md`](game/assets/LICENCES.md).

**One exception inside that row:** the six HOW TO PLAY pages are screen captures of this
game with instructions painted over them, so the layer *under* the annotation is our own
rendering of 0 A.D. art and **is CC-BY-SA 3.0 like everything else in row two.** The AI
question applies to the annotation only.

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
- **Using AOD's AI-generated UI art** (icons, splash, launcher icon): we make no claim
  either way, because we may have none to make. Nothing is owed to us and nothing is owed
  to Google, whose terms permit commercial use; Google also reserves the right to generate
  the same or similar output for anybody else, so it was never exclusive to us. Read
  [`GeminiCopyRight.md`](GeminiCopyRight.md) and satisfy yourself, rather than treating
  this paragraph as advice.
- **Re-skinning AOD with your own art**: your art is yours, under whatever licence you
  choose. This is a supported path — see [Docs/README.md](Docs/README.md#6-adding-assets-and-re-skinning)
  — because gameplay code never names an asset file.

## Third-party material with different terms

Not everything in or around this repo is covered by the two licences above:

| Item | Licence | Note |
|---|---|---|
| Godot Engine | MIT | Not distributed here; you install it |
| ~~Kibyra UI packs~~ | Free use, **redistribution forbidden** | **RETIRED 2026-08-30.** Replaced by project-owned art; nothing in the game loads one, and a clean clone no longer needs a download to have a HUD. See [CREDITS.md](CREDITS.md) |
| New Rocker, Cinzel Decorative (`game/assets/ui/fonts/`) | [SIL OFL 1.1](https://openfontlicense.org/) | **Committed**, which is the difference from the row above — the OFL permits redistribution provided its own text ships with the fonts, and it does |
| [isobake](https://github.com/HermanRas/blender_3d_to_2d_isobake) | GPL-2.0-or-later | Separate repo, build-time only, ships nothing into the game |
| `blender_pyrogenesis_importer` | GPL-2.0 | Build-time only |
| AI-generated UI art (`game/assets/ui/`, `game/assets/icons/`) | **Not third-party, and probably not copyrightable** | Generated by the project owner with Google Gemini. Nothing is owed to Google — its [ToS](https://policies.google.com/terms) disclaim ownership and permit commercial use — but see the header of this file: it is the one category here that is neither MIT nor CC-BY-SA. [`GeminiCopyRight.md`](GeminiCopyRight.md) |

Every third-party item in use is recorded in [CREDITS.md](CREDITS.md). Per-asset provenance
is tracked in [`game/assets/LICENCES.md`](game/assets/LICENCES.md) and checked by
`tools/licence_audit.py` — **both landed at phase 0.2c and are live.** The audit verifies
the 0 A.D. attribution elements and regenerates the recipe table; it does **not** check the
generated-art rows or anything in `GeminiCopyRight.md`, which are maintained by hand. Per
PLAN.md §1.2 there is no CI, so somebody has to run it — attribution is a licence
obligation, not a merge gate.
