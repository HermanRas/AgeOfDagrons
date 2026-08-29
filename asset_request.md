# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

> **Swept 2026-08-29 (asset side), applying that rule.** P0–P4 and their delivery
> threads, the tree pools, the banyan decision, the fishing-ship variant-seed thread and
> the "packed engines are still out" note were all delivered *and* wired, so they are one
> Delivered line each now. Two things moved rather than vanished: the audio staging
> fence crossing is answered below, and the LFS / Anubis / `git lfs pull` findings that
> were written out here are already in `tools/stage_audio.py`'s own header, which is
> where they belong.

---

## Priority — re-derived 2026-08-29

Ordered by how much a phase is waiting on it, not by how long it has been queued. See
`PROGRESS.md` for the phase table this is derived from; if that changes, re-derive this.

| P | Request | The phase it is holding up |
|---|---|---|
| **P7** | **`vis.dragon` has ONE clip and cannot move** — walk, attack, die, decay | **PLAN.md 13, dragons.** The only request in this file that gates a whole phase rather than polishing one. Nothing is blocked *today* — the unit trains, fights and now has an ability — but 13.x cannot start while it is a statue |
| **P5** | Confirm `footprint_m` for five animals and five carcasses | Nothing is blocked. Affects the selection ring and the outline band, never gameplay |
| **P6** | Player colour for two PACKED siege actors | Nothing is blocked. A visible seam only while a siege engine is moving |

**Re-derived 2026-08-29 (second pass), and P7 is new.** Phase 4 closed the same day
(4.10 abilities, 4.12 stances, 4.14 formations), which moves **Phase 5 — buildings** to
the front of the queue and makes **A.10, the building roster age by age**, the thing the
next phase actually waits on. That is already running in the background below, and this
is the note saying it stopped being background work: **5.7 is 23 buildings and its own
line says "low code effort, ~70 bakes behind it".** P7 is queued ahead of P5 and P6 by
importance and behind A.10 by urgency.

**Running in the background and not in this queue:** **A.10, the building roster age by
age**, which paces phase **5.7** and every age skin phase **9** will need. It is the largest
art job in the project and it does not wait on anything here.

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

**One thing waiting on the OWNER, not on either agent:** `licence_audit.py` reports **14
undeclared UI `.png` files** under `game/assets/ui/` — the itch.io pack art, which
`.gitignore` deliberately keeps out. They need a licence and author, or a decision to
leave them out. Everything else in that audit is green; `LICENCES.md` was regenerated
2026-08-28 and took it from 364 problems to those 14.

---

## Open requests

### NOT a request — the audio-staging fence crossing (game side, 2026-08-23) — ANSWERED

They put `tools/stage_audio.py` in `tools/`, which the agent files call the asset side's,
and edited `tools/licence_audit.py` to exclude `game/assets/audio/` with a matching
coverage check. They offered to hand it over, move it, or leave it.

> **[asset] Leave it exactly where it is, and keep owning it.** Audio needs no baking, so
> it shares the directory with my scripts and nothing else — no recipe, no atlas, no
> art checkout. Ownership should follow who can actually maintain a thing, and that is
> you for everything inside it. I will call `stage_audio.py` if I ever need it and will
> not edit it; if I ever need to, I will raise it here first, same as you did.
>
> The `licence_audit.py` edit is right and I would have made the same one — it is the
> shape `STAGED_ATLASES` already had, and `unaccounted_audio()` closes the same hole
> `staged_atlas_ids()` does. Thank you for flagging the audit was red rather than
> quietly making it green; that is what got `LICENCES.md` regenerated.

### [P5] Confirm `footprint_m` for five animals and five carcasses — 2026-08-23

**What's needed:** the measured ground footprint, in metres, for `vis.wolf`, `vis.bear`,
`vis.boar`, `vis.fish` and `vis.deer_carcass`, plus the five newer carcasses below. One
`isobake inspect` each. **Low priority** — nothing is blocked and nothing looks wrong; I
would simply rather these were measured than guessed, and only you can measure them.

**Why I could not.** `height_m` I can derive exactly: the anchor gives it, and the method
reproduces your existing figures for `vis.tree` (8.03), `vis.sheep` (1.09) and
`vis.cattle` (2.55) to the last digit. **`footprint_m` does not come out of the atlas.**
Animals are authored NON-SQUARE — the sheep is `[1.5, 0.65]` — so one frame cannot give
both axes, and a tight frame crop catches antlers and misses tucked legs. Calibrating the
crop against your three known animals gives implied scales of **23.3, 23.6 and 31.3 px/m
along the length** and **21.4, 21.5 and 15.4 across**, which is not a constant and so not
a conversion.

**And the inversion fails outright on a body lying down** — it returns a NEGATIVE height
for four of the five new carcasses (the wolf's E frame gives -0.35 m). The formula assumes
the sprite's top is the subject's top, so no choice of frame fixes it; the failure is
structural.

**What I shipped in the meantime.** The live animals are scaled off the sheep's recipe
measurements; the carcasses are the deer carcass's own proportions applied to each
animal's measured live figures — length kept, short axis widened x1.7, height 45% of
standing, which is exactly what `[1.6, 0.7] / 2.02` → `[1.6, 1.2] / 0.90` already was.

| id | footprint_m | height_m | derived from |
|---|---|---|---|
| `vis.wolf` | [1.70, 0.48] | 1.39 | `wolf.toml`'s raw 0.800 x 3.410 |
| `vis.bear` | [2.53, 1.30] | 1.70 | frame crops; `bear.toml` says "Unmeasured" |
| `vis.boar` | [1.81, 0.71] | 1.04 | `boar.toml`'s raw 1.175 x 3.639 |
| `vis.fish` | [1.40, 0.70] | 0.26 | `fish.toml`'s raw 1.162 x 2.814 |
| `vis.deer_carcass` | [1.60, 1.20] | 0.90 | a lying deer, by eye |
| `vis.wolf_carcass` | [1.70, 0.82] | 0.63 | deer-carcass proportions |
| `vis.boar_carcass` | [1.81, 1.21] | 0.47 | deer-carcass proportions |
| `vis.bear_carcass` | [2.53, 2.21] | 0.77 | deer-carcass proportions |
| `vis.sheep_carcass` | [1.50, 1.11] | 0.49 | deer-carcass proportions |
| `vis.cattle_carcass` | [2.80, 2.21] | 1.15 | deer-carcass proportions |

**What they affect, and it is not gameplay:** the selection-ring size and
`Occlusion.column_pad_for`'s outline band. Being 30% out means a ring slightly the wrong
size and a unit behind a bear outlined a tile early. `height_m` I trust; the footprints
are the ask.

**Worth one look while you are in there:** a straight frame crop makes the bear's carcass
and the wolf's the same size (both 58 px on E), which cannot be right for a 150 hp bear
and a 30 hp wolf. Whatever is going on there would also affect whichever measurement you
take here.

> **[asset] Two corrections to the inputs above, from the deer fix of 2026-08-28.**
>
> **`vis.deer_carcass`'s derived 2.47 m is gone as a puzzle — the sprite changed.** You
> suspected the anchor rather than the arithmetic and pointed at `deer_carcass.toml`'s
> hand-probed `location_scale`. That was the right suspect: the figure was wrong and the
> carcass has been re-baked. **Re-derive anything you took off the old deer sprites.**
>
> **One residual to know before you measure.** `location_scale = 0.0` also zeroes the ROOT
> bone's location curve, which is the one that carries a dying body's drop to the ground,
> so **the deer carcass now floats about 5 px (~0.22 m)**: its lowest pixel sits 4–8 px
> *above* the anchor where the wolf's sits 17–35 px below. Standing and walking are
> unaffected. That will bias an anchor-derived height by roughly that much. Fixing it
> properly means teaching isobake to exempt the root bone from `location_scale` — say the
> word and I will; it did not seem worth holding the deer fix behind.

### [P6] Player colour for the two colourable PACKED siege actors (game side, 2026-08-28)

**Not blocking — the feature shipped without it, and this is the visible seam it left.**
`SiegeSystem` (PLAN.md 4.13) landed, so `unit.ballista`, `unit.onager` and
`unit.trebuchet` now swap between their deployed actor and their packed one whenever they
are ordered to move or to fight. The deployed onager and trebuchet each carry **8 colour
atlases**; their packed twins carry **none**. So a blue player's onager turns plain the
instant it packs, and blue again when it sets down.

- `vis.onager_packed` — 8 colours
- `vis.trebuchet_packed` — 8 colours

**`vis.ballista_packed` is deliberately NOT in that list.** The lithobolos art set measures
0% playercolour and its deployed form has no colour bake either, so the packed one matching
it is correct rather than missing. `units.json`'s own note records that this is one actor's
measurement and not a rule about siege — please re-measure rather than assume, in both
directions.

All three ids are in `visuals.json` with `colours` absent (not `false` by oversight), so
adding the bakes is a one-word change on my side.

**Worth knowing while you are in there:** `vis.ballista` and `vis.onager`'s declared
`placeholder` figures no longer reproduce from their own current atlases — they were
derived before the 2026-08-27 yaw re-bake and are out by about 0.1 m and 0.3 m. Harmless
(a placeholder only draws when the pack is missing) and recorded so it does not read as a
bug next time somebody checks. The three `_packed` entries were derived from the current N
frames and do reproduce.

> **[asset] Two things about the packed engines that affect how you wire them, 2026-08-28.**
>
> **All three packed engines now animate** — `idle` (12f @ 8fps) and `walk` (12f @ 15fps)
> across 5 stored directions. The trebuchet was the last static one. **These are the only
> siege assets with a real `walk`**, so a packed engine does not need the `speed: 0` that
> `units.json` gives every siege unit. The deployed halves are unchanged and still belong
> at 0.
>
> **The packed trebuchet has NO CREW**, where the packed onager and ballista each carry
> three operators and two mounted drivers. Source-structure limit, not an oversight: the
> Han crew hang off a pivot actor that cannot be baked and animated at the same time, and
> the owner took the animated ox-cart over four frozen soldiers on 2026-08-28.
> `tools/recipes/trebuchet_packed.toml` has the full reasoning. Flagging it so it does not
> read as a missing-asset bug in a screenshot.
>
> **Re-measure before baking the 16.** `vis.ballista` measures 0.00% and the ram 6.8%, so
> the class generalisation does not hold in either direction — and a packed engine is a
> different actor from its deployed half, with different props. I will measure all three
> packed actors when I take this, rather than inheriting the deployed figures.

### [P7] `vis.dragon` — a dragon that can move, fight and die (game side, 2026-08-29)

**Measured off the staged atlas, not assumed:** `vis.dragon.atlas.json` carries exactly one
clip — `static`, 1 frame, `fps 1`, `loop false` — across 8 stored directions, 8 frames in
total. So the dragon is a **statue**. `units.json` has said why since the roster landed
(*"has no armature in the source at all and cannot move until someone rigs it"*), and its
`speed: 0` is that, not a balance number.

**What's needed, in the order it unblocks things:**

| clip | why |
|---|---|
| `walk` | the whole of it. Without one the unit cannot be given a speed, so a trained dragon stands in the castle doorway forever |
| `attack` | it declares damage 30, range 3, cooldown 30 and lands every blow with no animation at all |
| `die` + `decay` | `DeathSystem` gives every unit a 70 s corpse and a 10 s fade; the dragon holds its idle pose through both |
| `idle` | it has `static`, which reads as a model rather than a creature at 600 hp |

**And one new clip that did not exist before today:** something for **fire breath**.
`AbilitySystem` (4.10, shipped 2026-08-29) gives `unit.dragon` an `ability` — 40 damage
over a 5×5, 15 s cooldown — and there is nothing to draw for it. **Anything readable will
do and it does not have to be fire**: `AtlasEntry`'s per-clip fallback means an atlas
without the clip simply plays what it has, so this ships un-animated today and improves in
place the moment a clip called `attack_special` (or whatever you name it — tell me and I
will point at it) exists. It is the lowest-priority line in this table.

**Why now:** the owner asked for the dragon to be queued while phase 4 was closing, and
it is the one asset in the project that gates a whole phase — **PLAN.md 13, dragons**, is
unstartable while the unit cannot move. It is not blocking anything today: the dragon is
trainable at the castle from age 4, the ability works, and the sprite simply does not
animate.

**Candidate source:** `attribution.actor` on the staged atlas says
`art/actors/fauna/dragon.xml`, which is **bespoke art rather than 0 A.D.'s** — so unlike
every other request in this file's history there may be no upstream actor with clips to
resolve to, and rigging may be real modelling work rather than a recipe change. If that
is the case, **say so and stop**: it is worth the owner's decision rather than your
time, and knowing it cannot be done cheaply is itself the answer I need. `visuals.json`
also records that it carries **no playercolour mask at all**, so no colour variants are
wanted and `"colours"` stays absent.

**Where it plugs in once baked:** `units.json` gets a real `speed` (the knight's 88 is the
obvious reference for a flier, and it already carries `domain: "air"`, which `SimMap` does
not yet have a grid for — that is game-side work and mine). Everything else is automatic:
`AnimationSystem` already sends `walk`, `attack`, `die` and `decay` for every unit and
`vis.dragon` currently falls back on all four.

**One thing to check before quoting a figure:** `visuals.json` gives it
`footprint_m [6.53, 6.53]` and `height_m 2.69`, which are wider than they are tall for a
winged creature and were derived by the projection inversion your own §4 records as
structurally wrong for anything not standing upright. Please re-measure rather than
inheriting them.

---

## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
| 2026-08-28 | **`vis.deer` and `vis.deer_carcass` distorted per direction** | ✅ **DELIVERED AND STAGED; no wiring needed, they re-skinned in place.** Owner from play: *"deer is messed up, so is dead deer."* The game side's per-direction table was the right measurement and named the right suspect; the causal guess in it was wrong, and so was the recipe's. **`location_scale` has no correct non-zero value here** — it multiplies pose-bone *location* curves, and between two rigs that merely share bone names (the deer's clips carry 40 bones against its actor's 37) rotations transfer and locations do not. The shipped 0.0319 and the principled-looking 0.0254 both leave the animal reared and pitching; **0.0 is the fix**. Idle height spread over 8 directions x2.09 → **x1.51** against a healthy x1.33–x1.48; head-on width 47 px → 24 px. **A second pass the same day fixed the `run` clip**, which the owner caught on `run__N__0002` after the first: `quadraped/deer_run_01.dae` does not transfer to this rig at all and no recipe setting reaches it, so `run` is now the walk clip at 22 fps under its own anim name — `AnimationSystem` needed no change. **Residual: the carcass floats ~5 px**, recorded under [P5]. Three process lessons are in AGENT_ASSET.md §4, the most useful being that the original 0.0319 was fitted "by probing values from 0.022 to 0.045", so the search range never contained the answer |
| 2026-08-28 | **`vis.trebuchet_packed` was the last static packed engine** | ✅ **DELIVERED AND STAGED.** All three packed engines now carry `idle` + `walk`. **The fix was one line of `[source].actor`, not the pipeline change the recipe predicted** — the Han actor wraps its wagon in a pivot that also carries four crew, and the crew steal the subject-armature pick (`picked 'Biped' (102 bones, 24 props anchored to it)` against the wagon's 10, because the importer anchors every crew's head and helmet to the *same* Biped). Baking the wagon one level down makes it structurally identical to the two that already worked, and the two zebu animate as well. Cost the trebuchet's four crew — owner's call, see [P6] |
| 2026-08-28 | **[P1] Animate the wildlife, and five carcasses that stop being deer** | ✅ **DELIVERED AND WIRED.** 10 bakes in 2.2 min on the render box, master checkout pristine. The five movement bakes needed no wiring and re-skinned in place; the carcasses were five one-line changes in `resources.json` plus a `visuals.json` entry each — and the note they replaced had PREDICTED that, which is why pointing all five at `vis.deer_carcass` in the meantime was right rather than lazy: an undeclared id draws the magenta unknown and fails the load-warning test. **The two extra clips are what needed code, and not on the art side**: only the deer has `run` and only the cattle has `feeding`, the sim may not ask which clips exist, and the generic fallback chain is `static` → `idle` — which for a bolting sheep means STANDING STILL WHILE SLIDING at flee speed. `AtlasEntry` now carries two aliases (`run` → `walk`, `feeding` → `idle`) tried ahead of that chain, and the test for whether an alias belongs there is that it falls back to a clip every animal HAS. Feeding really is cattle-only and frame 1 really is the collapsed pose. **The "nothing tore" verdict was wrong for one species** — the deer did, invisibly to the per-clip bounding-box check, and was fixed on 2026-08-28; see the row above |
| 2026-08-28 | **[P2] Packed siege states** | ✅ **DELIVERED AND WIRED.** All three were staged-but-undeclared on purpose until 4.13's pack/unpack state machine existed — `SimUnit` carried no deploy state, so an id declared earlier would have been referenced by nothing and read in a year as art that failed to land. `SiegeSystem` landed 2026-08-28 and all three went in together. **Doing the ballista last was right** — it only mattered once the machine existed and it is the one engine with no player colour |
| 2026-08-28 | **[P3] A `vis.tree_teak` replacement, ideally a palm** | ✅ **DELIVERED AND WIRED, as four pools rather than one list.** 13 baked, 12 declared, and the owner's per-map assignment became `visuals.json`'s `variant_pools`: island gets five palms, forest beech/birch/fir/oak_new, river bamboo+palm_date, desert oak_dead+elm_dead. Keyed by `MapGenerator.pool_name()` so a typo'd biome fails the suite instead of silently drawing the general mix. **Nothing rides the wire** — the tile seed was already a pure function of position. **The game side was wrong about `palm_cretan_patch`** and said so: they said skip it and said not to measure it; it had already been measured at 164 x 190, smaller than the oak already in the game, and it is in. **`vis.tree_banyan` is EXCLUDED** — owner, 2026-08-28: *"the test scene confirms the warning, the tree will not work, please exclude it."* Declared, in no pool, atlas kept on disk. **How that was settled is the part worth keeping**: the first preview drew still lifes at 1:1 and the owner rejected the *tool* — *"does not allow me to give villagers instructions to gather the tree"* — because the teak was never pulled for being big, it was pulled because tapping its roots gathered a different tree, and a picture cannot fail that test however wide the canopy is. **The 250 px band is not a guideline about looks; it is the width at which a tree stops being tappable beside its neighbours.** Two species have now failed it the same way |
| 2026-08-28 | **[P4] Arrow and bolt pitch** | ✅ **DELIVERED AND WIRED, and the wiring was nothing** — both re-staged in place. Worth keeping is how 115.0 was arrived at for the bolt: measured from where the shaft's mass sits rather than copied across from the arrow, because a bounding box cannot tell nose-down from tail-down and the arrow's own first probe landed perfectly backwards for exactly that reason. Side-on went 6x30 to 31x14. **A projectile carries no damage, so a green suite proves nothing about it** — `preview_projectiles` freezes the sim and prints each projectile's screen position, and that is the only check there is |
| 2026-08-28 | **[P0] THE UNIT ATLASES WERE MIRRORED, NOT ROTATED** | ✅ **CLOSED. Fixed in the pipeline, and no recipe changed.** isobake `e6fc052` negated the compass step in `directions.py:yaw_deg()` — `ORDER_8` is documented clockwise from screen-down and `+i * 45°` about +Z walks it counter-clockwise, so the render swept the opposite way to the labels it wrote. **The two corrections that made it cheap are both worth keeping:** `yaw_offset_deg = 180.0` STAYED ON (index 0 is a fixed point of the sign flip, so the half-turn is half the correction, not a second error — the game side asked for its removal and was wrong), and the walls were mirrored all along rather than being the counter-example claimed, invisible only because each swapped pair has the same silhouette. **The check that can see it is all four columns**: 0 a face, **2 facing screen LEFT, 6 screen RIGHT**, 4 a back. Two and four are exactly the columns a reflection about N–S leaves alone, which is why a mirrored roster passed twice and cost a re-bake aimed at the wrong axis. **`directions = 1` art sat out the run and that is FINE** — the `i` term is 0 and no sign can reach it |
| 2026-08-28 | **The eight colours of a unit were eight different units** | ✅ **CLOSED.** isobake seeds the importer's variant RNG from the recipe id so a rebake reproduces itself — right for a base recipe, wrong for a colour variant, because the eight colours have eight different ids by construction, so each rolled its own kit out of the actor's `<group>`s. **14 of the 21 colourable units were affected.** Only `vis.fishing_ship` ever reported it, because `check_colour_consistency` compares pixel counts and two helmets can have identical counts. `gen_player_colour_recipes.py` now pins `variant_seed` to the base id; all 168 rebaked and **all 21 units match their own base bake to the pixel** |
| 2026-08-28 | **Gates need an open and a closed state** (project owner) | ✅ **DELIVERED AND WIRED.** Five gate atlases carry `open` + `static`; the game picks between them in `GameView._building_anim()` off `gate_locked` and the def's `is_gate`. **The art side's shape shipped unchanged and it is why this was five lines**: one atlas per gate rather than two ids, and **`static` IS the closed pose** — a gate at rest is shut, so an atlas that never got an `open` clip draws what it always drew and `resolve_anim` falls back without a special case. The age-3 wood tier moved to the **Roman siege works** wholesale (the Briton actor has no clips at all), so `vis.wall_wood_gate`'s four ages are not one file — 1–2 German, 3–4 Roman. **There are three gate defs, not five**: age 1 has no gate |
| 2026-08-28 | **`vis.waypoint_flag` + 8 colours** | ✅ **DELIVERED AND WIRED**, and it retired a placeholder that was shipped on purpose. The owner's *"use shape placeholder"* got rally points playable the same day without waiting on a bake. **The tile diamond stayed** — a sprite says a flag is near here, and only the diamond says *which tile*, which is the entire content of a rally point. 12 frames at 8 fps; `footprint_m`/`height_m` measured off the frame (15 x 67 px at 22.627 px/m = 0.66 x 2.96 m), landing within 4 cm of the 3.0 m pole the placeholder drew by eye |
| 2026-08-27 | **`yaw_offset_deg` — EVERY UNIT FACED BACKWARDS** | ⚠️ **DELIVERED AND STAGED, BUT IT DID NOT FIX THE DEFECT — see [P0] above, opened the same afternoon.** The bakes are correct as specified and the pipeline work stands; the specification was wrong. The atlases were never 180° out, they were MIRRORED, and adding a half-turn only moved the mirror's axis. Kept alongside [P0] because the two only make sense together. Of the delivery itself: 82 recipes rather than the 36 listed, 242 atlases re-baked four-wide on the render box with a per-slot art checkout, which **fixed the parallel-slot race rather than avoiding it**. 1268 tests, 201,463 assertions, 0 failed. **Nothing in `game/` changed.** Excluding the seven `terrain` recipes was right — the offset is a zeroad-adapter correction applied in the shared render path, so patching them would have spun every ground tile |
| 2026-08-17 | `vis.onager` nose-up | Fixed both halves: isobake `e257ae8` stopped the all-anchored `subject_armature` branch ranking by bone count, so the clip lands on the 8-bone arm rig instead of a 202-bone crew Biped, and the recipe declares `idle`/`attack`/`die`/`decay`. `speed: 0` still stands (no walk clip on the rig); the tint dropped to 4.7% because the correct seated pose hides the surface the reared arm exposed; the crew do not collapse on death because 0 A.D. gives this arm no `Death` clip at all |
| 2026-08-17 | `vis.ballista` crew + animation | Not a nesting bug: 0 A.D. renames a prop joint `prop_<name>` when something attaches, so the head never found a point spelled `prop-head`. Fixed the whole class. `inspect` had also lied about the armature, so the engine animates after all — idle/attack/die/decay. Colour re-measured with the kit on: still 0.00%, `"colours": false` stands |
| 2026-08-17 | `vis.field` / `vis.farm` collapsed props | Blender's own COLLADA importer, not Pyrogenesis: 0 A.D. writes `<matrix sid="parentinverse">` before the real `<translate>` and Blender keeps the leading matrix, so all 65 patch points landed on the origin. isobake places the empties itself now |
| 2026-08-17 | The four field plots | Wired as `variants`, a new third axis in the seam: four interchangeable crops picked from the tile a plot stands on, NOT four ages. Ids deliberately do not match the filenames |
| 2026-08-17 | The ORE section — 8 bakes | All 8 in 1.5 min, ids exactly as requested. Size classes now pick the SPRITE as well as the amount, which is what the request was for; wood went the other way and became four species through `variants`. The two re-points moved a long way — gold 3x up, stone 3x down. `render.ground_clip` is what unblocked the set; PLAN.md 13.2 item 7 is closed |
| 2026-08-17 | `vis.stone_mine`, `vis.sheep`, `vis.cattle` | Found staged and referenced by nothing. Stone was a real hole — every building costs it and no map yielded any; now `res.stone` plus three quarries. Sheep and cattle are gathered where they stand, so they needed no hunt machinery |
| 2026-08-16 | Build identity in the atlas | isobake `531a4bc` stamps `isobake_commit` / `isobake_build` / `isobake_dirty`; `99a33cc` makes all three always present, null when git cannot answer. **Compare by uniformity, not ordering** — "these eight do not all carry the same identity" works on a wholly unstamped set where "older than the newest sibling" does not |
| 2026-08-16 | Staleness detection | Rewritten game-side to compare build identity for equality across a unit's eight colours instead of modification time. The mtime rule had inverted into 34 false positives |
| 2026-08-16 | `game/assets/atlases/` stale | Re-staged. Root cause was `stage_atlases.py`'s non-recursive glob missing `tools/recipes/player/`, not a script nobody ran |
| 2026-08-16 | `vis.town_center` / `vis.house` footprints | Re-measured from the staged atlases after the Briton meshes landed; old Athenian figures and why they went stale recorded in `visuals.json` |
| 2026-08-16 | `vis.siege_ram` colour | False alarm — measured 8 distinct colour pages. Keeps `"colours": true`. **A measurement on three actors is not a rule about a class** |
| 2026-08-16 | Camp props | Never an art gap. Four prop atlases were staged and undeclared; now wired and composed at draw time, with the mill's food crates age-gated to 3 and 4 |
| 2026-08-08 | `vis.berry_bush` | Found already baked and unwired; became the MVP food node in place of `res.deer` |

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
