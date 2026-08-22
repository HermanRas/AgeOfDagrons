# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

---

## Open requests

### `vis.ballista_packed`, `vis.onager_packed`, `vis.trebuchet_packed` — requested 2026-08-22

**What's needed:** the PACKED half of all three siege engines. One bake each, same
treatment as their unpacked halves (which are staged and correct).

**Why:** 4.13's last item is the pack/unpack state machine — a siege engine travels
packed and cannot shoot, deploys to shoot and cannot move. It is scoped with 4.13 by
PLAN.md 9.2.1 item 5. The machine is sim-side work I can do; what it has no way to
show is the *packed* pose, because **every siege atlas staged today is the unpacked
one**. Without these three the state machine is invisible — a limbered trebuchet
would trundle across the map fully deployed, arm cocked, which reads as a bug rather
than as a state.

I would rather not build it against the magenta placeholder: the whole point of the
machine is that the two states look different, so a test can prove the transition
happened but only the art can show it is the right way round. Same class as the wall
art — *staged* and *wired* are different states — one size smaller.

**Candidate source:** all three resolve cleanly through the roster's own template
pair, and I checked each file is present in the checkout:

| id | packed actor | unpacked (already staged, for reference) |
|---|---|---|
| `vis.ballista_packed` | `units/carthaginians/siege_rock_packed.xml` | `units/carthaginians/siege_lithobolos_med.xml` |
| `vis.onager_packed` | `units/romans/siege_onager_packed.xml` | `units/romans/siege_onager_pivot.xml` |
| `vis.trebuchet_packed` | `units/han/siege_mangonel_pivot_packed.xml` | `units/han/siege_mangonel.xml` |

Two notes that may save you time. `tools/recipes/trebuchet_deployed.toml` already
says the packed half has no recipe and names the right actor in its header comment,
so that one is half-written. And the Carthaginian and Roman packed templates do
**not** follow the naming the roster implies — the roster's `siege_rock_packed` is a
template under `units/cart/siege_ballista_packed.xml`, and *its* actor is the one in
the table. I resolved all three through `<VisualActor><Actor>` rather than by
filename, per §9.2's rule.

**Colour:** all three unpacked halves except the ballista carry `"colours": true`.
Worth measuring rather than assuming — a limbered engine is a different silhouette
and may expose a different amount of tunic, exactly the way the onager's correct
seated pose did.

**Where it plugs in once baked:** three new `visuals.json` entries, dense four-age
maps pointing at the one bake (units do not re-skin per age). `SimUnit` carries the
deploy state and `UnitView` picks the id from it. Nothing else moves.

**Not blocking the rest of 4.13** — arrow projectiles and the hostile wolf need no
new art and I am doing both now. This is the only piece that waits on you.

---

### `vis.wolf` animated (your A.4a) + `vis.wolf_carcass` — requested 2026-08-22

**What's needed:** two things, and the first is already on your list.

1. **`vis.wolf`, animated** — idle / walk / attack / die / decay. This is A.4a, and
   `tools/recipes/wolf.toml` already reasons it through in full: every clip exists in
   `fauna/wolf.xml` (Idle ×3, Walk, Run, attack_melee ×2, death ×2), the quadruped
   `location_scale` bug that blocked it is fixed, and the recipe says the "still
   static" note is now a workaround for a problem that no longer exists. I am not
   adding anything to that analysis — only saying it now has a caller.
2. **`vis.wolf_carcass`** — new, and the deer already shows the shape: `vis.deer_carcass`
   is a separate bake of `fauna/deer.xml` carrying a single `carcass` anim. Same
   treatment on `fauna/wolf.xml`. `tools/recipes/deer_carcass.toml` is the template.

**Why:** 4.13's hostile wolf. The project owner picked the full version on 2026-08-22
— the wolf is a gaia-owned unit that roams, chases and bites, and killing it drops a
gatherable carcass worth 30 food. So the wolf now *moves*, which is what makes the
animation load-bearing rather than nice: **`vis.wolf` today has one `static` anim, and
this project's own convention is that anything without a walk clip carries `speed: 0`
precisely so a motionless sprite never slides across the map** (ships, dragon, and all
three siege engines all do). A hostile wolf cannot take that out, so it is the first
entity in the game that has to move without a walk clip.

**Not blocking me.** I am building the sim side now and the wolf will slide until A.4a
lands — a known, temporary, visibly-wrong state rather than a hidden one. Say if you
would rather I hold the wolf's `speed` at 0 until then and I will; it makes it
harmless and useless in equal measure.

**Where it plugs in once baked:** `vis.wolf` needs no wiring change, it re-skins in
place. `vis.wolf_carcass` becomes a `visuals.json` entry and the visual for a new
`res.wolf_carcass` node in `resources.json`.

---

### `vis.onager` still renders nose-up — **agent 2, 2026-08-16; FIXED 2026-08-17**

**Fixed and staged.** Both halves as diagnosed: isobake `e257ae8` stops the
all-anchored `subject_armature` branch ranking by bone count, so the clip lands on
the 8-bone arm rig instead of a 202-bone crew Biped, and the recipe now declares
`idle` / `attack` / `die` / `decay`. The engine sits flat on its base and the arm
lies along the frame. The full working is in `tools/recipes/onager.toml` and the
isobake commit message; nothing about it needs to live here.

**One thing to check on your side, and it is small.** The atlas shape changed the
way `vis.ballista`'s did when it stopped being static:

| | before | after |
|---|---|---|
| anims | `static`, 1 frame | `idle` 12, `attack` 12, `die` 2, `decay` 2 |
| frame0 | 118×107, anchor (55.0, 53.6) | 115×108, anchor (60.0, 57.6) |

The sprite is the same size to within 3 px, so unlike the gold and stone re-points
I do **not** think `footprint_m` / `height_m` want re-measuring — the old figures
were taken off this same actor, only in a wrong pose. Worth one look, not a
re-derivation. `speed: 0` still stands: there is no walk clip on this rig, only
`Idle` and `attack_ranged`.

**It also tints less than it used to, and that is a consequence of the fix, not a
regression.** The reared arm was exposing a big player-coloured surface that the
correct seated pose hides. Measured across the five stored directions: **4.7% of
the sprite, ranging 1.7% from due N/S to 7.9% from the side** — where the old
figure was 7.1%, sampled from one direction. It still separates cleanly (closest
pair of the eight, orange vs yellow, is ΔRGB 49 over the mask) and `"colours":
true` stands. But if a player has to tell whose onager that is at a glance, from
head-on it is now about 100 px of tunic. Worth knowing when you decide what leans
on baked-in colour and what leans on the selection ring or the control-group HUD.

**Known cosmetic limit, deliberate.** The three crew do not collapse on death the
way the ballista's and the ram's do. 0 A.D. gives this arm no `Death` animation at
all, so `die`/`decay` freeze the idle pose, and because a clip's identity here has
to be its animation *file* (the pivot actor the recipe names declares no
animations, so clip names cannot resolve), `die` cannot carry an identity separate
from `idle`'s and so cannot hand the crew a death clip of their own. A still crew
around a still engine reads as stopped, not as broken. Say so if you disagree and
I will look at giving a recipe a way to name rider clips directly.

---

## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
| 2026-08-08 | `vis.berry_bush` | Found already baked and unwired; became the MVP food node in place of `res.deer` |
| 2026-08-08 | `vis.deer_carcass` | Baked; prompted the per-clip `location_scale` fix that unblocked animated fauna. Not wired — nothing hunts deer since the berry-bush switch |
| 2026-08-16 | `game/assets/atlases/` stale | Re-staged. Root cause was `stage_atlases.py`'s non-recursive glob missing `tools/recipes/player/`, not a script nobody ran |
| 2026-08-16 | `vis.town_center` / `vis.house` footprints | Re-measured from the staged atlases after the Briton meshes landed; old Athenian figures and why they went stale recorded in `visuals.json` |
| 2026-08-16 | `vis.ballista`, `vis.onager` | Both baked static (0-bone armatures) and wired at `age_required` 3, `speed: 0`. Onager tints, ballista does not |
| 2026-08-16 | `vis.siege_ram` colour | False alarm — measured 8 distinct colour pages. Keeps `"colours": true` |
| 2026-08-16 | 90 colour bakes | 90/90 in 5.1 h. **All 8 colours correct for all 20 units**, 325/325 staged. Ended the red-and-yellow-only period |
| 2026-08-16 | Build identity in the atlas | isobake `531a4bc` stamps `isobake_commit` / `isobake_build` / `isobake_dirty`; `99a33cc` makes all three always present, null when git cannot answer |
| 2026-08-16 | Staleness detection | Rewritten game-side to compare build identity for equality across a unit's eight colours instead of modification time. Reports 0; the mtime rule had inverted into 34 false positives |
| 2026-08-16 | Camp props | Never an art gap. Four prop atlases were staged and undeclared; now wired and composed at draw time, with the mill's food crates age-gated to 3 and 4 |
| 2026-08-16 | Dead `ASSET_MISSING.md` citations in `game/` | Acknowledged, left as history — a large diff over careful comments to fix a cosmetic dead link |
| 2026-08-17 | `vis.ballista` crew + animation | Not a nesting bug: 0 A.D. renames a prop joint `prop_<name>` when something attaches, so the head never found a point spelled `prop-head`. Fixed the whole class. `inspect` had also lied about the armature, so the engine animates after all — idle/attack/die/decay. Colour re-measured with the kit on: still 0.00%, `"colours": false` stands |
| 2026-08-17 | `vis.stone_mine`, `vis.sheep`, `vis.cattle` | Found staged and referenced by nothing. Stone was a real hole — every building costs it and no map yielded any; now `res.stone` plus three quarries. Sheep and cattle are gathered where they stand, so they needed no hunt machinery |
| 2026-08-17 | `vis.field` / `vis.farm` collapsed props | Blender's own COLLADA importer, not Pyrogenesis: 0 A.D. writes `<matrix sid="parentinverse">` before the real `<translate>` and Blender keeps the leading matrix, so all 65 patch points landed on the origin. isobake places the empties itself now. Delivered `vis.farm` at the same time, as predicted |
| 2026-08-17 | The four field plots | Wired as `variants`, a new third axis in the seam: four interchangeable crops picked from the tile a plot stands on, NOT four ages. Ids deliberately do not match the filenames |
| 2026-08-17 | The ORE section — 8 bakes | All 8 in 1.5 min, 331/331 staged, ids exactly as requested. Size classes now pick the SPRITE as well as the amount (`resources.json` `visuals`), which is what the request was for; wood went the other way and became four species through `variants`. The two re-points moved a long way — gold 3x up, stone 3x down — and both placeholders were re-derived. `render.ground_clip` is what unblocked the set; PLAN.md 13.2 item 7 is closed |

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
