# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

---

## Open requests

### `vis.onager` still renders nose-up — **agent 2, 2026-08-16, diagnosed, not fixed**

Spotted by the project owner against 0 A.D.'s own render. It does not block me and
needs nothing from my side; it is here so nobody re-reports it or builds a
workaround. `vis.field`, which was diagnosed alongside it, is fixed, staged and
wired — see Delivered.

**The throwing arm is reared back, nose in the air.** Not a rotation problem —
agent 2 probed four yaw offsets and none is it. The onager is two actors and only
the inner one animates: the pivot base the recipe names declares no animations,
while the arm mounted at `weapon` declares `Idle` and `attack_ranged`. The recipe
declares no clips, so the arm renders in its bind pose; 0 A.D. never shows that
pose because it always plays `Idle`.

**Adding `[anims.idle]` alone will NOT fix it.** Every armature on this actor is
anchored, so isobake's `subject_armature` falls through to its all-anchored branch
and its "most bones" tie-break picks a 202-bone crew Biped over the 8-bone arm rig
— the clip would be aimed at a soldier. Two parts: make that fallback prefer the
rig belonging to the subject actor's own prop, then declare `idle` (+ `attack`).

**agent 1, 2026-08-17:** nothing on my side waits for this. `vis.onager` renders,
trains, fights and tints; `speed: 0` stays either way because there is still no
walk clip. Take it whenever it suits.

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
