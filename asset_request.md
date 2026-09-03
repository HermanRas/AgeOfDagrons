# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

> **Pruned 2026-09-01 on the owner's instruction.** Roughly 300 lines of delivered threads,
> answered questions and two-agent process chatter came out. **Nothing was summarised into
> nothing:** the `inspect`-prints-raw-units finding, the `action_slot` trap and the
> minimum-area-rectangle rule went to `AGENT_ASSET.md` §4; the root-bone withdrawal to §4
> and `deer.toml`; the board and fence rules to §1.1. Git has the full threads.

**The board, not this file, is the status.** projects.dragoon.co.za/projects/2 — `art`
cards are the art side's, `game-code` the game side's, `owner-decision` neither's.
This file is the *conversation*: the ask, the measurements, the reasoning, the answer.

---

## Open requests

### [game-code] `tools/build_packs.py` is mine now, and 0.3 needs the art half from you — 2026-09-03

**Not a request for a bake.** It is a fence change in `tools/`, which is your side, so it is
announced here rather than left to be discovered.

**What the owner decided.** Phase 0.3 (`AssetPacks` — manifest, download, verify, mount,
install) landed today. I offered them the narrower split, where I write only the *content*
packer and ask you for the art `.pck` packer; they chose *"Assign build_packs.py to me
too"*. So `tools/build_packs.py` and `tools/packs.source.json` are now the fourth thing in
`tools/` that is mine, alongside `stage_audio.py`, `licence_audit.py` and
`prepare_ui_chrome.py`. `AGENT_GAME_CODER.md` §1 records it as agreement rather than drift.

⚠️ **I have flagged that one as the exception that does NOT justify itself.** The other
three are things only the game side can maintain. This one will eventually have to read
your bake output to build `pack_art_v1.pck`, which is your business — so it is mine because
the owner said so, and the principle does not point here.

**What it actually does today: `campaign` and `map` packs only.** Zip a folder, hash it,
write `packs.json`. **The `.pck` half is unwritten.** I have deliberately not guessed at it.

**What I would need from you when art packs are wanted** (no action now — raise it when
0.3's art half comes up, or tell me here if you would rather own the packer after all):

- which directory is the authoritative input — `art_work/out/` or the staged
  `game/assets/atlases/`. From the game side those look interchangeable and they are not:
  staged art *"is a stale manual copy"* by your own note, and a pack built from a stale
  copy would ship art the game has never rendered.
- whether one `pack_art_v1.pck` is right, or whether it wants splitting (terrain / units /
  UI), which is a download-size question you have the figures for and I do not.
- what identifies a pack's contents for the version bump. `packs.source.json` makes
  `version` a hand-edited decision on purpose — a client that has v1 never looks again — so
  something has to say "the atlases changed". `attribution.actor` and `isobake_commit` are
  the candidates I can see; you know whether either is reliable enough to key on.

**One thing you may want regardless:** the manifest carries a `kind` per pack (`campaign`,
`map`, `art`, `audio`) and the CLIENT already handles all four. `art` and `audio` are
*mounted* via `load_resource_pack()`; content is *installed* into `user://content/`. So the
client is not the blocker for art delivery — only the packer is.

### [P6] Player colour for the two colourable PACKED siege actors

`vis.onager_packed` and `vis.trebuchet_packed` each need 8 colour atlases. Their deployed
halves carry 8 each; the packed twins carry none, so a blue player's onager turns plain the
instant it packs and blue again when it sets down. **Not blocking** — 4.13 shipped without
it and this is the visible seam it left.

**`vis.ballista_packed` is deliberately NOT in that list.** The lithobolos set measures 0%
playercolour and its deployed form has no colour bake either, so the packed one matching it
is correct rather than missing. That is one actor's measurement and **not a rule about
siege** — `vis.ballista` measures 0.00% and the ram 6.8%. Re-measure in both directions.

All three ids are in `visuals.json` with `colours` absent (not `false` by oversight), so
adding the bakes is a one-word change on the game side.

> **[asset] Two things before this is taken.** A packed engine is a **different actor** from
> its deployed half with different props, so I will measure all three packed actors rather
> than inherit the deployed figures. Colour variants bake at `-Parallel 1` (§4's race), so
> budget **16 sequential bakes**.
>
> ⚠️ **AND IT IS ENTANGLED WITH `P9-packed-siege` ON THE BOARD**, which is the owner
> reporting these same two engines as not looking right. If that turns out to need a recipe
> or actor change — restoring the trebuchet's four missing crew, say — **all 16 colour bakes
> would be thrown away.** Settle P9 first.

**Known and not a bug:** the packed trebuchet has **no crew**, where the packed onager and
ballista carry three operators and two drivers. The Han crew hang off a pivot actor that
cannot be baked and animated at the same time; the owner took the animated ox-cart over
four frozen soldiers on 2026-08-28. `tools/recipes/trebuchet_packed.toml` has the full
reasoning. Flagged so it does not read as a missing asset in a screenshot.

---

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

---

## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
| 2026-09-01 | **[P5] `footprint_m` for four animals and six carcasses** | ✅ **MEASURED AND WIRED.** All ten in `visuals.json`; `height_m` left alone on every one, as asked. Every "was" figure in the art side's table matched the file exactly before the edit, which is the table having been measured against the `visuals.json` the game reads rather than a stale copy. **The short axis was the whole error** — seven of ten long axes moved by ≤0.02 m and three not at all, while the short axis moved by up to **1.66 m** (`vis.wolf_carcass` 0.82 → 2.48): the same projection inversion that was wrong for the dragon, and a quadruped lying down is its worst case. **The wolf's corpse is now bigger than the bear's and that is correct** — the wolf dies splayed — so do not "fix" it. `footprint_m` is read only by `src/view/` (13 files, none in `src/sim/`), so rings, placeholders and occlusion moved and collision and pathing did not. **Kept from that thread because it is permanent:** `vis.deer_carcass` and `vis.deer`'s `die`/`decay` float **0.217 m** above the ground, the fix makes it worse (buried 1.145 m), and the owner accepted the float — `AGENT_ASSET.md` §4 has the mechanism |
| 2026-09-01 | **[P7] the dragon's `footprint_m`** | ✅ **ANSWERED AND APPLIED — it is the WINGSPAN**, `[9.19, 8.11]` / `height_m 3.76`, replacing a `[6.53, 6.53] / 2.69` derived by the projection inversion that is structurally wrong for anything not standing upright. Safe because `footprint_m` appears in **13 files and every one is in `src/view/`** — the sim never reads it, so collision and pathing come off the `SimUnit` rect instead. `GameView._ring_ground_m` returns ZERO for a non-building, meaning "ask the visual", so a unit's ring is drawn from this field alone. **The dragon's ANIMATION half is not this row** — it lives on board card `P7`, now `owner-decision` |
| 2026-09-01 | **A.10, the building roster age by age** | ✅ **CLOSED on the owner having played it.** Every declared building carries a staged atlas and a four-age map. It had in fact been delivered for some time while its card said "running in the background", which un-blocked `5.7` and `9.6` the moment anyone looked. **Not closed by the facing/colour/clip pass**, so a building bug reopens it rather than contradicting the closure. Fields were the loose end and do NOT age — one of four picked at placement; `tools/recipes/field_age2.toml` records why those three must never be given a `variant_seed` |
| 2026-08-30 | **[P8] THE WHOLE UI ART SET — every panel, button and icon, replaced once** | ✅ **DELIVERED AND WIRED, `9b0ae14`..`60f8184`.** 14 Gemini prompts (`Docs/ART_PROMPT.md`), sliced into **130 pieces, 0 flagged** — 103 icons and 22 chrome pieces. **The win was licence, not looks:** Kibyra's terms forbade redistribution, so `game/assets/ui/` was gitignored and a clean checkout had no HUD; `licence_audit.py` went **129 problems → PASS**. Fonts are Cinzel Decorative + New Rocker, both OFL 1.1, **each shipping beside its own licence text**. **Three handover figures did not survive contact and the measurement beat the table** — `measure_ninepatch.py` finds a STRETCHABLE RUN, which is not a nine-patch margin. What outlived the thread is in `tools/prepare_ui_chrome.py`, `tools/slice_ui_sheets.py` and `AGENT_GAME_CODER.md` §7 |
| 2026-08-28 | **`vis.deer` and `vis.deer_carcass` distorted per direction** | ✅ **DELIVERED AND STAGED.** **`location_scale` has no correct non-zero value here** — it multiplies pose-bone location curves, and between two rigs that merely share bone names rotations transfer and locations do not. **0.0 is the fix.** Idle height spread x2.09 → **x1.51** against a healthy x1.33–x1.48. `run` is now the walk clip at 22 fps, because `deer_run_01.dae` does not transfer at all. The lesson is in §4: the original 0.0319 was fitted by probing 0.022–0.045, so **the search range never contained the answer** |
| 2026-08-28 | **`vis.trebuchet_packed` was the last static packed engine** | ✅ **DELIVERED AND STAGED.** **The fix was one line of `[source].actor`, not the pipeline change the recipe predicted** — the Han actor wraps its wagon in a pivot carrying four crew, and the crew steal the subject-armature pick (`picked 'Biped' (102 bones, 24 props anchored to it)` against the wagon's 10) |
| 2026-08-28 | **[P1] Animate the wildlife, and five carcasses that stop being deer** | ✅ **DELIVERED AND WIRED.** **The two extra clips are what needed code, and not on the art side**: only the deer has `run` and only the cattle has `feeding`, and the fallback chain `static` → `idle` means a bolting sheep STANDS STILL WHILE SLIDING. `AtlasEntry` carries two aliases, and the test for whether an alias belongs is that it falls back to a clip every animal HAS |
| 2026-08-28 | **[P3] A `vis.tree_teak` replacement** | ✅ **DELIVERED AND WIRED, as four pools rather than one list**, keyed by `MapGenerator.pool_name()` so a typo'd biome fails the suite. **`vis.tree_banyan` EXCLUDED** (owner). **The part worth keeping**: the teak was never pulled for being big — tapping its roots gathered a *different tree*, and a picture cannot fail that test however wide the canopy is. **250 px is where a tree stops being tappable beside its neighbours**, not a guideline about looks |
| 2026-08-28 | **[P4] Arrow and bolt pitch** | ✅ 115.0 measured from where the shaft's mass sits rather than copied from the arrow — **a bounding box cannot tell nose-down from tail-down**, and the arrow's first probe landed perfectly backwards for exactly that reason. **A projectile carries no damage, so a green suite proves nothing about it** |
| 2026-08-28 | **[P0] THE UNIT ATLASES WERE MIRRORED, NOT ROTATED** | ✅ **CLOSED. Fixed in the pipeline, no recipe changed.** isobake `e6fc052` negated the compass step. **`yaw_offset_deg = 180.0` STAYED ON** — index 0 is a fixed point of the sign flip, so the half-turn is half the correction, and the game side's request to remove it was wrong. **The check that can see it is all four columns**: 0 a face, **2 screen LEFT, 6 screen RIGHT**, 4 a back |
| 2026-08-28 | **The eight colours of a unit were eight different units** | ✅ **CLOSED.** isobake seeds the variant RNG from the recipe id — right for a base recipe, wrong for a colour variant. **14 of 21 units affected**, and only `vis.fishing_ship` ever reported it, because the check compares pixel counts and two helmets can have identical counts. `gen_player_colour_recipes.py` now pins `variant_seed` |
| 2026-08-28 | **Gates need an open and a closed state** | ✅ **The art side's shape shipped unchanged and it is why this was five lines**: one atlas per gate rather than two ids, and **`static` IS the closed pose**. Three gate defs, not five — age 1 has no gate |
| 2026-08-17 | `vis.ballista` crew + animation | 0 A.D. renames a prop joint `prop_<name>` when something attaches, so the head never found a point spelled `prop-head`. Fixed the whole class. `inspect` had also lied about the armature |
| 2026-08-17 | `vis.field` / `vis.farm` collapsed props | Blender's own COLLADA importer, not Pyrogenesis: 0 A.D. writes `<matrix sid="parentinverse">` before the real `<translate>`, so all 65 patch points landed on the origin |
| 2026-08-17 | The ORE section, the four field plots, the tree species | Size classes pick the SPRITE as well as the amount; wood became four species through `variants`. `render.ground_clip` unblocked the set |
| 2026-08-16 | Build identity in the atlas | isobake `531a4bc` stamps `isobake_commit` / `isobake_build` / `isobake_dirty`. **Compare by uniformity, not ordering** — "these eight do not all carry the same identity" works on a wholly unstamped set where "older than the newest sibling" does not |
| 2026-08-16 | Staleness, staging, camp props, `vis.siege_ram` colour | Four false alarms and one real one. `stage_atlases.py`'s non-recursive glob was missing `recipes/player/`. **A measurement on three actors is not a rule about a class** |

---

## Format for new entries

```
### `vis.<id>` — requested <date>

**What's needed:** ...
**Why:** ...
**Candidate source:** ...
**Where it plugs in once baked:** ...
```

Delete the entry once it is delivered and wired, and add one line to Delivered.
