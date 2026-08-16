# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked — see `ASSET_MISSING.md` for the full tracker and status legend this mirrors.

## Open requests

### `vis.{scout_cavalry,sword_cavalry,cavalry_archer,knight,trebuchet}.<colour>` — requested 2026-08-16 — **agent 2: it is 90 bakes, not 30**

Your 30 are right and they are queued. But `missing_colour_atlases()` cannot see
the other 60, because those files exist and are **stale**, not absent.

Three pipeline defects were fixed after the 8-colour batch of 2026-08-15 ran:

1. `decay` sampled its clip from t=0, so the first decay frame was the unit
   still STANDING. Every corpse sprang upright for a frame before collapsing.
2. `swordsman` and `elite_swordsman` baked as two overlapping bodies.
3. player colour never reached actors whose ROOT is opaque — which is why the
   five you listed had no tint at all, and why `transport_ship` had none either.

Only `red` and `yellow` have been rebaked since. So of the 152 colour atlases:

| | count | state |
|---|---|---|
| red + yellow, all 19 units | 30 | correct, rebaked 2026-08-16 |
| galley, galleon, fishing_ship, trade_cart × 8 | 32 | correct — static or no decay, untouched by all three fixes |
| the other 6 colours × 9 units with a `decay` clip | 54 | **stale** — corpses stand up |
| `transport_ship` × 6 | 6 | **stale** — baked before it could take a tint at all |
| your 30 | 30 | not baked yet |

**What this means for you:** develop against **red and yellow only**. They are the
two the project owner picked for exactly this reason. The other six are present
and will resolve, so nothing errors — they are just wrong, and wrong silently,
which is the same failure mode `missing_colour_atlases()` exists to prevent. If
it is cheap to do, consider having it flag atlases older than the newest bake of
the same unit rather than only absent ones.

All 90 go in one overnight run at 3-wide (~6.8 h). Nothing is needed from you.

### `vis.ballista` and `vis.onager` — requested 2026-08-16 — **agent 2: accepted, with one caveat**

Both templates resolve, so the picks are good:

```
units/cart/siege_ballista_unpacked -> units/carthaginians/siege_lithobolos_med.xml
units/rome/siege_onager_unpacked   -> units/romans/siege_onager_pivot.xml
```

Measured: lithobolos 8.56 × 13.89 × 7.82 m (153 px tall), onager 10.36 × 14.67 ×
5.64 m (110 px). Both import cleanly, 16 and 14 meshes.

**The caveat is animation.** `isobake inspect` reports `Biped (0 bones)` for both
— the bone-less armature defect documented in `tools/recipes/spearman.toml`.
Clip attach scores zero against an empty bone set, so `idle`/`walk`/`attack`/
`die`/`decay` as specified is very unlikely; the bake would abort rather than
silently drop them. Expect **static, 5 directions**, in the shape of the ships.

You already answered this: you said the deployed pose is the useful one and that
the trebuchet's reduced set was enough. So I will bake them static unless you say
a motionless siege engine is worse than no siege engine. They will get all eight
colours in the same pass.

Not started yet — the colour backlog above is ahead of it.

### ~~`game/assets/atlases/` is stale — please re-run `tools/stage_atlases.py`~~ — **DONE 2026-08-16**

Staged: **283 of 313 declared atlases, 609 files, 197 MB.** The 30 not staged are
the 30 colour variants above.

You were right that it was stale, and right about the cause of the colour half —
but re-running the script would not have fixed it. `stage_atlases.py` built its id
list from `tools/recipes/*.toml` with a **non-recursive** glob, and the colour
variants live in `tools/recipes/player/` (kept out of the top level so
`bake_batch.ps1` does not sweep 152 extra recipes into every ordinary batch).
So no `vis.<unit>.<colour>` could ever have staged, no matter how often it ran.
Fixed by having `recipe_ids()` read `player/` explicitly.

Confirmed staged now, against your table:

| id | actor now staged |
|---|---|
| `vis.town_center` | `structures/britons/civic_centre.xml` |
| `vis.house` | `structures/britons/house.xml` |
| `vis.mill` | `structures/britons/special.xml` |
| `vis.villager` | `units/celts/female_citizen.xml` + 8 colour variants |

122 colour atlases and the full four-age building set are in place, so
`visuals.json`'s age map and your eight-atlas selection should both light up.
Re-read the stale-colour table above before trusting anything but red and yellow.

Your note on `footprint_m`/`height_m` for `vis.town_center`, `vis.house` and
`vis.mill` being Athenian-derived is correct and now live — the Briton meshes are
mounted, so those three figures are wrong as of this staging. Re-measure from the
staged atlases; the geometry is in each `.atlas.json` (`pixels_per_metre` plus the
frame rects). Flagging rather than editing: `game/data/` is yours.



**What's needed:** a re-run of `tools/stage_atlases.py`. Nothing to bake.

**Why:** the staged copy is the **phase-0.4 set** — 43 atlases, all Athenian/Hellenic, no age variants and no colour variants. `art_work\out` has 283. Checked by reading `attribution.actor` out of the staged files:

| staged id | staged actor | current bake |
|---|---|---|
| `vis.town_center` | `structures/athenians/civil_centre.xml` | `structures/britons/civic_centre.xml` |
| `vis.house` | `structures/hellenes/house.xml` | `structures/britons/house.xml` |
| `vis.mill` | `structures/hellenes/farmstead.xml` | `structures/britons/special.xml` |
| `vis.villager` | `structures/…/female_citizen.xml` | same actor, but no `.<colour>` variants staged |

Two consequences on the game side, both live now:

1. **Player colour does not work at all**, because no `vis.<unit>.<colour>` file is staged — every player resolves to the same untinted bake. The eight-atlas selection is built and tested (`game/tests/view/test_skins.gd`), and `GameDataRegistry.missing_colour_atlases()` enumerates the gap, but the test that compares two players' pages has to skip itself until the files are there.
2. **The age skins never appear.** `visuals.json` now carries a dense four-age map for all 17 age-skinned buildings and every path in it was cross-checked against `art_work\out`, so this should light up the moment staging runs — no further game-side work expected.

**Also worth knowing:** `visuals.json`'s `footprint_m`/`height_m` for `vis.town_center`, `vis.house` and `vis.mill` are still the 0.4 figures measured off the **Athenian** meshes, and the Briton age-1 bakes are visibly smaller (Briton town centre projects 315 px wide against the Athenian 459). They are deliberately left alone because they are correct for what is mounted *today*; they need re-measuring in the same change that stages the new bakes. Every other placeholder in the file was derived from its own baked atlas geometry and needs nothing.

### `vis.{scout_cavalry,sword_cavalry,cavalry_archer,knight,trebuchet}.<colour>` — requested 2026-08-16

**What's needed:** the six remaining player colours — `blue`, `cyan`, `green`, `violet`, `orange`, `white` — for five units. 30 bakes. `red` and `yellow` already exist for all five; the other fourteen units already have all eight.

**Why:** colour is the only thing distinguishing players (PLAN.md §1), so a unit with two colours is a unit six players cannot own legibly. Resolution falls back to the untinted bake rather than failing, which means the failure is *silent* — hence `missing_colour_atlases()`, which currently returns exactly these 30.

**Candidate source:** whatever produced their `red`/`yellow` — no new actor, just the remaining tint passes.

**Where it plugs in once baked:** nowhere. `visuals.json` marks these five with `"colours": true` and the path is derived (`vis.knight.blue.atlas.json`), so they are picked up with no game-side edit at all.

### `vis.ballista` and `vis.onager` — requested 2026-08-16

**What's needed:** two siege engines, same treatment as `vis.siege_ram` (5 directions, `idle`/`walk`/`attack`/`die`/`decay`), with the eight player colours.

**Why:** they are the age-3/4 Siege Workshop's other two units in the roster (Age & Unit Planning.md), and they are the only roster entries with no bake at all. `units.json` deliberately does **not** define them — a def with no art resolves to the magenta unknown and puts two dead buttons in the train row — so the Siege Workshop currently offers only the Battering Ram in age 3 and the Trebuchet in age 4.

**Candidate source:** the roster names the templates directly — `units/cart/siege_ballista_packed` + `siege_ballista_unpacked`, and `rome/siege_onager_packed` + `siege_onager_unpacked`. Same packed/unpacked pair the trebuchet came from, so if only one pose is practical the **unpacked** (deployed) one is the useful one; the trebuchet shipped `idle`+`attack` only and that was enough.

**Where it plugs in once baked:** `game/data/visuals.json` (two entries with `"colours": true`), `game/data/units.json` (two defs, `age_required` 3, `trainable_at` `building.siege_workshop`), and `building.siege_workshop`'s `trains` list. All three are a few lines — nothing is blocked structurally, only the art is missing.

## Baked

### `vis.berry_bush` — delivered, wired 2026-08-08

Not a request that went through this file — the user pointed at an existing bake sitting unwired at `art_work\out\vis.berry_bush\` (atlas + PNG, real 0 A.D. `props/flora/berry_bush.xml`, CC-BY-SA 3.0). Copied into `game/assets/atlases/` and wired into `visuals.json`/`resources.json` as `res.berry_bush`, which now replaces `res.deer` as the MVP's active food node (session decision — no hunt/kill/carcass state machine needed, it gathers like a tree). `res.deer`/`vis.deer` stay defined but unused.

### `vis.deer_carcass` — requested 2026-08-08, baked 2026-08-08

**What's needed:** a static (no animation needed) sprite for a dead/downed deer, to show once `res.deer` (PLAN.md 6.1a/6.2, the huntable food node) is fully gathered. Same treatment as `vis.deer` itself, which is already baked static-only (`tools/recipes/deer.toml`, `fauna/deer.xml`, 5 directions mirrored to 8, 128×128 canvas) — no animation is expected or wanted here either.

**Why:** `game/data/resources.json` calls this out explicitly: *"The carcass still has no art and stays on its placeholder."* `res.deer`'s node itself is fully implemented and baked; only the depleted/carcass visual state is missing. Not currently blocking — the game falls back to the standard placeholder — but it's a known, named gap on the path to a complete MVP gather loop (chop wood / mine gold / hunt a deer).

**Candidate source:** 0 A.D.'s asset set may have a dead/carcass variant near `fauna/deer.xml` (worth checking sibling fauna actors, e.g. boar/sheep/wolf equivalents, for a `_dead` or corpse mesh) — same CC-BY-SA 3.0 source already in use for every other fauna bake (`vis.deer`, `vis.boar`, `vis.sheep`, `vis.fish`, `vis.wolf`). If no dedicated corpse mesh exists in 0 A.D.'s set, a static downed-deer pose (or even the standing stag mesh laid on its side) would be an acceptable substitute — readability at sprite scale matters more than anatomical accuracy, same call already made for `vis.fish` (tuna over the true fish mesh) and `vis.stone_mine` (quarried rock over a civ-matched but less legible pick).

**Where it plugs in once baked:** `game/data/visuals.json` (new `vis.deer_carcass` entry, same shape as `vis.deer`'s) and `game/data/resources.json`'s `res.deer` entry (a depleted-state visual field, once the sim side reads one — not implemented yet, tracked separately under PLAN.md 6.1a/6.2).

**Baked 2026-08-08:** `vis.deer_carcass`, 5 directions mirrored to 8, 192×192 canvas, `tools/recipes/deer_carcass.toml`. Turned out not to need a substitute pose — the death clip's own collapsed frame now bakes correctly, since this request prompted a real fix for the animation-transfer bug that had kept `vis.deer` static (`isobake` gained a per-clip `location_scale` correction; see ASSET_MISSING.md §1.1 for detail). One cosmetic caveat: a small tear at the neck/antler seam in the collapsed pose, accepted as placeholder-quality. Wiring into `visuals.json`/`resources.json` is on your side of the fence.

**Not wired in, on purpose:** the game swapped its MVP food node to `res.berry_bush` this same session (see above), so nothing currently gathers a deer to leave this carcass behind. The fix is real and worth keeping — it also means `vis.deer` itself could regain proper walk/idle animation instead of staying static-only, which was not attempted here. Revisit if wildlife hunting comes back.

---

## Format for new entries

```
### `vis.<id>` — requested <date>

**What's needed:** ...
**Why:** ...
**Candidate source:** ...
**Where it plugs in once baked:** ...
```

Move an entry to a "Baked" section (or just delete it) once agent 2 confirms it's done and it's wired in.
