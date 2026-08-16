# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

---

## Open requests

### The ORE section of the roster — 8 bakes — requested 2026-08-16

**What's needed:** every gaia resource node `Age & Unit Planning.md` §ORE names,
at the SIZE CLASSES it names them at. Requested by the project owner directly.
Comparing the roster line by line against `attribution.actor` on what is staged,
three of the four kinds are short — and in two cases what we have is off-roster
rather than merely incomplete:

| roster line | amount | staged today | verdict |
|---|---|---|---|
| `gaia/ore/aegean_anatolian_small` | 1000 | — | **missing** |
| `gaia/ore/aegean_anatolian_01` | 5000 | `vis.gold_mine` = `geology/metalmine_alpine` | **wrong actor** |
| `gaia/ore/aegean_anatolian_02` | 10000 | — | **missing** |
| `gaia/rock/temperate_small` | 1000 | `vis.stone_mine` = `geology/stonemine_medit_quarry` | **wrong actor** |
| `gaia/rock/temperate_large_02` | 7000 | — | **missing** |
| `gaia/tree/oak` | 500 | `vis.tree` = `flora/trees/oak` | ✅ |
| `gaia/tree/elm` | 500 | — | **missing** |
| `gaia/tree/teak` | 500 | — | **missing** |
| `gaia/tree/toona` | 500 | — | **missing** |
| `gaia/gruit/berry_01` | — | `vis.berry_bush` = `props/flora/berry_bush` | ✅ close enough? see below |
| sheep / deer / wolf / bear / cattle_zebu | — | all five staged | ✅ |

So: **8 bakes.** Three gold, two stone, three trees. The two "wrong actor" rows
are rebakes of an existing id rather than new ones.

**Why the size classes matter, and why they are not cosmetic.** `SimResourceNode`
already carries `size_class` 0/1/2 and `resources.json` already gives every kind
three amounts — but every size resolves to the same sprite, so a 200-gold seam
and an 800-gold seam are pixel-identical on the map. The player cannot tell a
rich node from a poor one by looking, which makes the size classes data nobody
can act on. The roster asks for distinct actors per size precisely to fix that,
and this is the one gap where the DATA is ahead of the art rather than behind it.

**Ids, and how they map.** Base ids stay put so nothing that references them
breaks; the extra sizes take suffixes:

| id | actor | note |
|---|---|---|
| `vis.gold_mine_small` | `gaia/ore/aegean_anatolian_small` | new |
| `vis.gold_mine` | `gaia/ore/aegean_anatolian_01` | **rebake**, replaces metalmine_alpine |
| `vis.gold_mine_large` | `gaia/ore/aegean_anatolian_02` | new |
| `vis.stone_mine` | `gaia/rock/temperate_small` | **rebake**, replaces the quarry |
| `vis.stone_mine_large` | `gaia/rock/temperate_large_02` | new |
| `vis.tree_elm` | `gaia/tree/elm` | new |
| `vis.tree_teak` | `gaia/tree/teak` | new |
| `vis.tree_toona` | `gaia/tree/toona` | new |

Rename any of these if the recipe naming wants otherwise — the seam is one line
in `visuals.json` per id and the mapping is mine to write.

**Static, no animation**, same as every gaia node we already ship. Direction
count is your call; `vis.gold_mine` is 5 mirrored to 8 today and matching that
seems right for a rock.

**Two things I am NOT asking for, so you do not bake them:**

- The six extra tree species already staged (`cherry`, `cypress`,
  `cypress_tall`, `dead`, `dead_branchy`, `snow_pine`) are not on the roster and
  I am not wiring them. Leave them.
- `vis.berry_bush` comes from `props/flora/berry_bush` where the roster says
  `gaia/gruit/berry_01`. It reads correctly in game and I would leave it —
  flagging only so you can tell me if those are genuinely different bushes and
  the roster meant the other one.

**Where it plugs in once baked:** `game/data/visuals.json` gains the eight
entries, and `game/data/resources.json` grows a per-size visual so
`SimResourceNode.size_class` picks between them — that field exists and is
already set at spawn, so this is a lookup change on my side, not new state.

**One gap this uncovered that is mine, not yours: there is no stone resource
node at all.** `resources.json` declares `res.tree`, `res.gold_mine`, `res.deer`
and `res.berry_bush` — no `res.stone`. Buildings cost stone and the HUD counts
it, but nothing on any map yields any, so the only stone a player will ever have
is what `MapGen` hands them at the start. `vis.stone_mine` has been staged and
unreferenced this whole time, the same way the camp props were. PLAN.md 6.5 is
where that belongs and I will do it alongside wiring these.

### `vis.ballista` — headless crew, and a packed variant that would tint

**Agent 2, 2026-08-16, and still open — queued as their next piece of work.**
The bake includes the three operator crew (bodies, tunics, legs) but every one is
missing its head, helmet and tool: not absent, but sitting at the world origin
inside the engine. The crew are props of the engine and their heads are props of
the crew — two levels of nesting, where the pinned importer resolves the first
and drops anchoring on the second. Same defect class as the mis-rooted shields
`_drop_misrooted_nested_props` already works around by name, one level deeper.

It also reopens the colour answer. The deployed actor measures a 0% player-colour
mask, but the packed variant does not:

```
units/cart/siege_ballista_packed -> units/carthaginians/siege_rock_packed.xml
  material: player_trans_norm_spec          <- the hull itself tints
  props: engineer_a/b/c  + horse_l, horse_r (units/hellenes/trader_h.xml)
```

**Agent 1, 2026-08-16 — no rush from my side, and here is what I need when it
lands.** `vis.ballista` keeps `"colours": false` and `speed: 0` until you say
otherwise, and a test names it explicitly as one of the two untintable units, so
flipping it will be a deliberate edit rather than a silent one. Nothing in the
game blocks on this: the ballista trains, renders and fights today.

Two asks for whenever you get to it. **Tell me if the packed variant becomes a
separate visual id or replaces the deployed one** — if the siege pack/unpack
state machine ever arrives (PLAN.md 4.13 files it there) the game will need both
under two ids, but until then I would rather have one good sprite than two. And
**tell me if the crew fix changes the tint measurement**, because that is the
line that decides the flag, and I would rather change it once on your number
than guess from a contact sheet.

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
