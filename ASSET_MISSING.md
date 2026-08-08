# AOD — Missing Asset Tracker

Every asset the game needs and does not yet have. Companion to [PLAN.md](PLAN.md) §2 (art strategy) and §12A (art track).

**Rule:** nothing is "blocked" on an asset. Every entry below has a working procedural placeholder (PLAN.md §2.4), so gameplay proceeds and assets swap in behind the stable ID.

## Status legend

| Status | Meaning |
|---|---|
| ⬜ **TODO** | Needed, not sourced |
| 🟨 **SOURCED** | Candidate identified, not yet rendered/baked |
| 🟦 **BAKED** | In an atlas, in the project |
| ✅ **DONE** | Baked, verified in-game, licence recorded |
| 🎨 **BESPOKE** | No source exists; must be commissioned or drawn |

## Sources in use

| Source | Domain | Licence | Attribution |
|---|---|---|---|
| **0 A.D.** (Wildfire Games) | units, buildings, terrain, props, audio | CC-BY-SA 3.0 | Required — `CREDITS.md` + in-game Credits |
| **itch.io — `UI_dragon-huds`** | UI chrome | per-pack | Required |
| **itch.io — `uı-fonts`** | fonts | per-pack | Required |
| **itch.io — `Free_Medieval_Fantasy_UI_Pack`** (kibyra) | UI chrome | per-pack | Required |

> Any new source is added **only on an explicit note from the project owner**, and must be entered here plus `assets/LICENCES.md` plus `CREDITS.md` in the same change.

---

## 1. MVP-critical

Needed for the MVP defined in PLAN.md §10. All currently running on placeholders.

### 1.1 Units

| Asset | Animations needed | Status | Notes |
|---|---|---|---|
| `vis.villager` | `idle`, `walk`, `walk_carry_wood`, `walk_carry_gold`, `walk_carry_food`, `work_chop`, `work_mine`, `work_hunt`, `work_build`, `die`, `decay` | 🟦 **BAKED (all 11)** | All 11 animations baked from `units/athenians/female_citizen.xml`, 960 frames (8 directions), 160×160 canvas. Recipe: `tools/recipes/villager.toml`. Variant props (axe, pick, mallet, dagger, wood/ore/grain shuttles, berry basket) import and attach correctly (PLAN.md §14). **Known issue:** in `work_mine` her dress mesh stretches oddly — a dress vertex is weighted 100% to `hand_L` in the source mesh and gets dragged when the mining clip's hand pose differs sharply from the citizen's native poses. Cosmetic, isolated to that one clip; **accepted for MVP**, tracked as PLAN.md §13.2 item 7 alongside the buried building skirts — both are source-mesh defects for one post-MVP art pass. **Second known issue, and this one is not cosmetic: she is 2.18 m tall.** `isobake inspect` measures the actor at 4.356 raw units, which is 2.178 m at the pipeline's 0.5 factor — 16 cm *taller than the stag* (2.020 m). She inherits 0 A.D.'s own proportions because the recipe declares no override. Fix would be one `height_m` line on `villager.toml` plus a rebake of her 960 frames. **Deliberately deferred 2026-08-08:** tried a `height_m = 1.93` rebake, but the current 2.178 m bake is confirmed good on-device (phone testing looked right, existing frames are correct with no clipping) — not touching a working asset pre-MVP. Revisit as a polish pass once the game is otherwise working, not before. PLAN.md §13.2 item 9 has the measurements, and a correction: an earlier note here claimed a 2× pipeline bug, which was wrong |
| `vis.deer` | `idle`, `walk`, `die`, `decay` | 🟦 **BAKED (static only)** | Standing stag from `fauna/deer.xml`, 5 directions mirrored to 8, 128×128 canvas. Recipe: `tools/recipes/deer.toml`. **No animation:** the actor's clips transfer by bone name (36/37, 97%) but the animation files and the mesh file describe the same skeleton ~31× apart, so location curves overshoot and the mesh tears into spikes — PLAN.md §13.2 item 8 has the measurements and the two dead ends. Costs nothing on the MVP path (6.1a needs a huntable food node; roaming is 6.1b) **except the carcass**, which has no art and stays on its placeholder. A.4 |

### 1.2 Buildings

Buildings do not turn — `SimBuilding` has no facing and placement snaps to the grid without rotation — so every one of these is a **single frame at `directions = 1`**, and the state set is `SimBuilding.Phase`, not a separate "damaged" tier. There is no damaged-state art here because 0 A.D. has none either: its structures go straight from intact to rubble, and health is shown by the health dot (PLAN.md 5.6).

States are **separate visual IDs, not states inside one atlas**, because 0 A.D. models them as separate actors and because foundations and generic rubble are shared *by footprint size* — the same `vis.foundation_8x8` serves every 8×8 building added later. `buildings.json` (0.4) carries all three IDs per building.

| Asset | Used for | Status | Notes |
|---|---|---|---|
| `vis.town_center` | Phase.COMPLETE | 🟦 **BAKED** | `structures/athenians/civil_centre.xml`, 459×329 px, `yaw_offset_deg = 180` to show the domed tholos rather than the hall that masks it. Faction tint applies (`USE_PLAYERCOLOR`). Recipe: `tools/recipes/town_center.toml` |
| `vis.foundation_8x8` | Phase.FOUNDATION + UNDER_CONSTRUCTION | 🟦 **BAKED** | `structures/fndn_8x8.xml`, 520×287 px — 0 A.D.'s own pairing for the civic centre. Shared by every 8×8 building. Recipe: `tools/recipes/foundation_8x8.toml` |
| `vis.rubble_town_center` | Phase.DESTROYED | 🟦 **BAKED** | `structures/destruct_hele_cc.xml`, 562×313 px. Bespoke Hellenic ruin rather than generic rubble, following 0 A.D.'s own override. Recipe: `tools/recipes/rubble_town_center.toml` |
| `vis.house` | Phase.COMPLETE | 🟦 **BAKED** | `structures/hellenes/house.xml`, 273×194 px, also turned 180°. The actor is five houses (A–E) in one variant group; the importer picks one deterministically from the recipe id, so `variant_seed` buys village variety cheaply later. Recipe: `tools/recipes/house.toml` |
| `vis.foundation_4x4` | Phase.FOUNDATION + UNDER_CONSTRUCTION | 🟦 **BAKED** | `structures/fndn_4x4.xml`, 264×159 px. Shared by every 4×4 building. Recipe: `tools/recipes/foundation_4x4.toml` |
| `vis.rubble_3x3` | Phase.DESTROYED | 🟦 **BAKED** | `structures/destruct_stone_3x3.xml`, 300×146 px. Generic, shared by every small building. Recipe: `tools/recipes/rubble_3x3.toml` |

Two things to carry into 0.4 and 5.2:

- **Footprints come from the art, not from PLAN.md §9's sketch.** Measured at the pipeline's tile-to-tile scale, the civic centre is 15.5 × 15.0 m — a **7.75-tile** footprint, agreeing with 0 A.D.'s own 30×30-unit obstruction and with the `fndn_8x8` foundation its template pairs with. The house is 10 × 10 m, a **5-tile** footprint on a 4×4 foundation. `buildings.json`'s `footprint` should be `[8, 8]` and `[4, 4]`; the `[4, 4]` written for the town centre in PLAN.md §9 predates any measurement. Scaling the meshes down to fit a chosen footprint is not the alternative — it would break the one-global-`pixels_per_metre` rule (PLAN.md §2.2) and leave the villager taller than the doorway.
- **No separate under-construction art.** Foundation covers both phases. 5.2 can show progress by drawing the completed sprite clipped from the bottom over the foundation, which is a view-layer effect and needs no extra bake.

**Buried skirt — ✅ FIXED**, was PLAN.md §13.2 item 7. Three of the six carried geometry below `z = 0`: 0 A.D. models a wall skirt for the terrain to hide, and a baked sprite has no terrain to hide it, so it hung below the ground line. `isobake` grew `render.ground_clip`, which bisects every mesh at world `z = 0` and discards what is underneath; the three recipes set it and were re-baked.

It has to be a 3D cut before the render, not a crop of the finished sprite: the ground plane is seen at 30°, so `z = 0` projects to a diamond spanning most of the frame's height — the near corner of an 8-tile footprint sits 90 px *below* the anchor while its far corner sits 90 *above*. Any horizontal cut that removed the skirt would take the front of the building with it.

| Asset | Sprite before | Sprite after | Height before | Height after | Actually buried |
|---|---|---|---|---|---|
| `vis.town_center` | 459×383 px | 459×**329** px | 9.48 m | **6.70 m** | 2.78 m |
| `vis.rubble_3x3` | 303×194 px | 300×**146** px | 4.83 m | **2.05 m** | 2.78 m |
| `vis.house` | 273×221 px | 273×**194** px | 7.33 m | **4.80 m** | 2.53 m |
| `vis.foundation_8x8`, `vis.foundation_4x4`, `vis.rubble_town_center` | — | unchanged | — | — | none |

Widths are unchanged, which is the check that only buried geometry went: cutting anything visible would have narrowed the silhouette too.

Note the burial was **deeper than the pixel estimate suggested** — 2.53 m under the house, not the 0.7 m its below-anchor excess implied. Both figures were right: a skirt directly beneath the building projects higher on screen than the footprint's near corner, so most of it hid behind the ground diamond and only the overhang showed. The height column above is now measured off the clipped geometry rather than inferred, so ⚠️ **`game/data/visuals.json` must stop subtracting the skirt by hand** — it currently carries `vis.house` at 6.6 m (should be 4.80) and `vis.rubble_3x3` at 3.0 m (should be 2.05). `vis.town_center`'s 6.8 m was already within 0.1 m of correct.

### 1.3 Resource props

| Asset | Variants needed | Status | Notes |
|---|---|---|---|
| `vis.tree` | 3 size classes + stump/depleted | 🟦 **BAKED (1 of 4)** | Oak baked from `flora/trees/oak.xml`, 5 directions, ~10 m tall. Recipe: `tools/recipes/tree_oak.toml`. The actor has 6 variants (2 meshes × 3 textures + small) — the size classes come from those. A.4. **Clipping fixed 2026-08-08:** the canvas-edge check found the canopy touching the left/right/top edges of its 224×224 frame (bake since 0.9); rebaked at 320×320 with no clip warning |
| `vis.gold_mine` | 1 sprite (size is data-only, not visual) | 🟩 **BAKED** | Baked from `geology/metalmine_alpine.xml`, 5 directions, 2.80 × 3.87 × 1.21 m at the default tile-to-tile scale — a ~1.4 × 1.9 tile footprint, which agrees with 0 A.D.'s own 7×7-world-unit (1.75 tile) obstruction for the node. Recipe: `tools/recipes/gold_mine.toml`. Alpine, not the civ-matching `metalmine_granite_greek`, because that one's texture is olive-green and its veins vanish at sprite size; all the old-generation ore actors share the same lead mesh and differ only in texture, so this was purely which one reads as gold. The actor has 6 variants (3 formations + 3 boulders) — the three `size_class` visuals come from those if we ever want them non-data-only, but reaching past `formation-a` needs variant selection in `isobake`, which does not exist. A.4 |

### 1.4 Terrain

| Asset | Status | Notes |
|---|---|---|
| Grass / dirt / sand iso tiles | 🟦 **BAKED (all 3)** | `terrain.grass` baked at 0.9 from `grass/grass1.xml` at exactly 64×32. Recipe: `tools/recipes/terrain_grass.toml`. **Dirt and sand baked 2026-08-08**, same recipe shape with a different `terrain =` line — `dirt/dirta.xml` (`tools/recipes/terrain_dirt.toml`) and `sand/sand.xml` (`tools/recipes/terrain_sand.toml`). A.1 |
| Water shallow / deep | 🟦 **BAKED (both)** | `terrain.water_shallow` (`water/water_1.xml`) and `terrain.water_deep` (`water/water_3.xml`) baked 2026-08-08, same recipe shape as `terrain_grass.toml`. Picked by 0 A.D.'s own minimap colour for each texture (lightest → shallow, darkest → deep) for maximum visual contrast. Recipes: `tools/recipes/terrain_water_{shallow,deep}.toml`. Still not needed for MVP (land domain only) |
| Tile transitions / blending | ⬜ TODO | Post-MVP polish; hard edges are acceptable initially |

### 1.5 UI

| Asset | Status | Notes |
|---|---|---|
| Panel frames, buttons, bars | ✅ **DONE** | Kibyra dragon-pack art integrated: main menu (`game/assets/ui/menu/`), selection/HUD panels (`game/assets/ui/hud/`) -- panel background, portrait frame, health bar, toast banner. All gitignored per-developer copies, see `game/assets/LICENCES.md`. Minimap frame still a plain drawn rectangle -- no dedicated minimap frame exists in the pack |
| Fonts | 🟨 SOURCED | `uı-fonts` pack. Ships **inside the APK** |
| Resource icons (stone, gold, wood, food, villager) | ✅ **DONE** | Stale line, corrected 2026-08-08 — all 5 already exist at `game/assets/ui/icons/res_{stone,gold,wood,food,villagers}.png`, delivered as part of the AI-generated icon sheet (PLAN.md §13.2 item 4), just never reflected here |
| Unit/building portrait icons | 🟦 **BAKED (control groups + selection panel)** | `EntityPortrait.frame_for()` (`src/view/entity_portrait.gd`) crops the S-facing static/idle frame straight out of the unit's own baked atlas -- shared by `ControlGroupSlot` (10.1/10.4) and `EntityPortraitView` (8.1a/8.1c), so no separate portrait art is needed |
| Control-group slot frames (empty + filled) | ✅ **DONE** | Kibyra dragon-pack ring, copied to `game/assets/ui/control_groups/group_slot_ring.png` (see `game/assets/LICENCES.md`). One ring art for both states; empty vs. filled is a placeholder-grey vs. real-icon fill, not two separate ring textures |
| Selection ring / health dot | ✅ **DONE** | Drawn in-engine: `EntityView._draw_selection_ring()` (4.3) and `EntityView._draw_health_dot()` (4.6) |

### 1.6 Audio — MVP

Deferred: `AudioManager` is a no-op in MVP (PLAN.md §7.5). Listed so the vocabulary is fixed early.

| ID | Status | Notes |
|---|---|---|
| `villager.chop` | ⬜ TODO | 0 A.D. candidate |
| `villager.mine` | ⬜ TODO | 0 A.D. candidate |
| `villager.build` | ⬜ TODO | 0 A.D. candidate |
| `villager.die` | ⬜ TODO | 0 A.D. candidate |
| `building.complete` | ⬜ TODO | |
| `building.destroyed` | ⬜ TODO | |
| `ui.click`, `ui.error` | ⬜ TODO | itch.io or CC0 |
| Menu music | ⬜ TODO | 0 A.D. soundtrack candidate |

---

## 2. Post-MVP

### 2.1 Military units

Each needs `idle`, `walk`, `attack`, `die`, `decay`. 5 directions where the
subject is laterally symmetric; 8 where a one-sided weapon/shield would flip
hands under mirroring, same reasoning as the villager's axe (PLAN.md 2.5) —
both units baked so far need 8.

**New pipeline defects found and fixed/worked around baking this section,
2026-08-08 — both worth knowing before baking the rest of the roster:**

1. **A whole mesh family imports with a bone-less armature.** Several
   Athenian actors use `skeletal/new/m_armor_tunic_short.dae`
   (spearman/javelinist _a/_c/_e, cavalry_swordsman _a_r/_e_r, slinger _a/_e,
   oxybeles, ballista) — `isobake inspect` reports `armature Biped (0 bones)`
   for every one of them, despite the raw COLLADA import log showing every
   joint imported correctly; something in the pinned Pyrogenesis importer's
   armature-building step drops all bones for this one mesh file. Every clip
   attach then silently fails and the bake aborts with "Available: []".
   `skeletal/new/m_tunic_short.dae` and `m_dress.dae` are unaffected (102
   bones, confirmed on archer/healer). **Not fixed in isobake** — picking a
   variant of the same unit that uses the working mesh was cheaper than
   debugging the importer's armature builder. `infantry_spearman_b.xml`
   (`m_tunic_short.dae`) is otherwise identical to `_a` (same clips, same
   spear+shield) and was used instead.
2. **A shield renders twice, once at the character's feet.** The Athenian
   hoplite shield (`aspis_athen_{a,b,c,d}.xml`) declares a nested
   `attachpoint="root"` back-plate prop *before* its own `<mesh>` group in
   file order. The pinned importer resolves a nested `root` attachpoint
   against whatever mesh it last imported at that call depth; since none has
   been imported yet, it falls through to the character's own root instead
   of the shield's — the back-plate ends up glued to the character's feet
   instead of riding on the shield arm. **Fixed in isobake** (not a recipe
   workaround): `zeroad.py` gained `_drop_misrooted_nested_props`, a narrow,
   name-based post-import step that deletes known-affected objects (currently
   just `Aspis_Back`) rather than patching the importer's ~300-line,
   group-order-dependent root-propagation logic in place — deliberately
   scoped to this one case rather than a general fix, given the size and
   regression risk of touching a pinned third-party dependency PLAN.md 1.3
   says not to fork. Add to `_KNOWN_MISROOTED_PROP_OBJECTS` if another prop
   actor turns up with the same ordering quirk.

| Asset | Status | Notes |
|---|---|---|
| `vis.militia` | 🟦 **BAKED** | `units/athenians/infantry_slinger_b.xml`, not the research pick (`infantry_javelinist_a.xml`) — every Athenian/Hellenic javelinist and slinger except this one uses the bone-less `m_armor_tunic_short.dae` (defect 1 above); `infantry_slinger_b.xml` is the only basic-ranged-skirmisher actor in either civ on the working `m_tunic_short.dae` mesh. 8 directions, 192×192 canvas, clean bake. Sling + slingrock props attach correctly (declared inside `base_slinger_ready.xml`'s own `<props>`, same "prop lives in the animation-variant file" pattern as the villager's gather tools). Idle/Walk/attack_ranged/Death clips from `base_slinger_ready.xml`/`attack_ranged_slinger.xml`/`death_infantry.xml`. Recipe: `tools/recipes/militia.toml` |
| `vis.archer` | 🟦 **BAKED** | `units/athenians/infantry_archer_a.xml`, `skeletal/new/m_tunic_short.dae` (102 bones, unaffected by defect 1 above). 8 directions, 192×192 canvas, clean bake. Its shield (`pelte_cretan_bronze_01.xml`) does **not** hit defect 2 — mesh comes before nested props in file order, and the nested piece uses a named attach point (`back`), not `root`. Idle/Walk/attack_ranged/Death clips from `base_archer_relax.xml`/`attack_ranged_archer.xml`/`death_infantry.xml`. One harmless note: the armature has no `prop_loaded-projectile` attach point, so the nocked-arrow visual variant doesn't show (base arrow/quiver still attach fine). Recipe: `tools/recipes/archer.toml` |
| `vis.spearman` | 🟦 **BAKED** | `units/athenians/infantry_spearman_b.xml` — the mesh-1 substitute for defect 1 above (`_a` blocked, `_b` is otherwise identical: same `base_hoplite.xml` clips, same spear+shield). 8 directions, 224×224 canvas, clean bake once defect 2's shield fix landed. Idle/Walk/Attack_melee/Death clips from `base_hoplite.xml`/`death_infantry.xml`. Recipe: `tools/recipes/spearman.toml` |
| `vis.knight` | 🟦 **BAKED (static only)** | `units/athenians/cavalry_swordsman_b_m.xml` (mount, carrying `cavalry_swordsman_b_r.xml` as a nested rider prop) — `_b` substitutes for the research-recommended `_a` variants, which use the bone-less `m_armor_tunic_short.dae` (defect 1, see the section note above). **Static, for a third reason distinct from the wildlife's animation-transfer bug:** confirmed via `isobake inspect -v` that horse and rider are two fully separate skeletons (the horse's own `Horse_Armature`, distinct from the rider's `Biped`), and isobake's clip-resolution (`_declared_animations`) only walks `<variant file>` references, never `<prop actor>` ones — so it cannot see the rider's own animations at all when `source.actor` points at the mount. Animating the rider on a pinned-static horse would need a real isobake feature (clip-resolution against a specific nested prop actor), not attempted this pass. Geometry/prop attachment is unaffected by that limitation (happens entirely during the base import), so this composes correctly at the actor level. **Known cosmetic issue, accepted as-is (project owner, 2026-08-08):** the rider reads as standing on the horse's back rather than seated in it — the `rider` attach point sits slightly high/forward for this camera angle. Good enough for placeholder art; not reworked this pass. 8 directions, 384×448 canvas, clean bake (no clip/canvas warnings — the pose issue is a rig-attachment offset, not a bake defect). Recipe: `tools/recipes/knight.toml` | 
| `vis.siege_ram` | 🟦 **BAKED** | `units/romans/siege_ram.xml` — **no Athenian/Hellenic ram exists in 0 A.D.'s roster**, breaking the civ consistency kept everywhere else (flagged, not fixed; revisit later, doesn't touch gameplay). Mechanical rig (`SixWheeler`, 10 bones), animations declared inline in the actor's own top group. 5 directions mirrored to 8 (symmetric shields left/right), 384×384 canvas, clean bake. Idle/Walk/attack_melee clips read straight from the actor XML. **No death clip exists** — 0 A.D. only plays a destruction-dust particle on this actor's death, no posed animation — so `die`/`decay` reuse the frozen Idle pose, same non-issue as buildings having no damaged tier. Recipe: `tools/recipes/siege_ram.toml` |
| `vis.trebuchet` | ⚠️ **BLOCKED (deployed state)** | `units/hellenes/siege_lithobolos.xml` — a torsion stone-thrower, not a true counterweight trebuchet (0 A.D. has none), closest analog. **Diagnosed, not a quick fix, same treatment as `vis.farm`:** the engine has its own real mechanical rig (`Lithobolos_Armature`, 37 bones) and its clips resolve correctly from the actor XML, but isobake's armature-picking (`next(o for o in imported if o.type == "ARMATURE")`) grabs the FIRST armature object it finds, and for this actor that's one of the five crew operators' armatures (nested props), not the engine's own — the crew import *before* `Lithobolos_Armature` appears, the opposite of what other multi-armature actors seemed to do. Tried "prefer first armature with any bones" as a general fix; still failed, because a different crew member's armature datablock reports 202 bones (more than the engine's genuine 37) — Blender appears to reuse/extend an existing armature datablock across repeated similar crew imports, so bone count isn't a reliable ranking either. Reverted; a real fix needs to identify "the top-level subject's own armature" structurally, not by count or order — bigger than this pass's scope. Recipe `tools/recipes/trebuchet_deployed.toml` documents the dead end. **Packed state not attempted** — pending the same fix, since its draft horses are additional nested-prop armatures on top of the wagon's own rig |
| `vis.monk` | 🟦 **BAKED** | `units/athenians/healer.xml` — 0 A.D. has no monks; a robed staff-carrying healer is the closest analog, consistent with the Hellenic/Athenian civ picked for buildings and the other units. `skeletal/new/m_dress.dae` (102 bones, unaffected by defect 1 above), no shield (defect 2 moot). 8 directions, 192×192 canvas, clean bake. Idle/Walk/Heal/Death clips from `base_healer_male.xml`/`death_infantry.xml` — `Heal` stands in for `attack` since 0 A.D. gives this actor no combat animation and PLAN.md's vocabulary has no dedicated heal slot yet. **No relic-carrying variant exists to map to** — 0 A.D. has no relic prop for this actor, only a cosmetic hooded-priest head skin. Recipe: `tools/recipes/monk.toml` |
| `vis.trade_cart` | ⚠️ **BLOCKED** | `units/athenians/trader.xml` ("Trader Cart" variant) — same root cause as `vis.trebuchet`, confirmed systemic rather than one-off: the cart carries a horse + rider as nested props, each with its own armature, and isobake grabs one of theirs instead of the cart's own mechanical rig. Not re-attempting the armature-picking fix here (already tried and reverted for the trebuchet). Recipe `tools/recipes/trade_cart.toml` documents the dead end. The crate/barrel goods props that would have been the loaded/empty lever are moot until this unblocks |
| Projectiles (arrow, bolt, stone) | 🟦 **BAKED (all 3)** | `vis.projectile_arrow` (`props/units/weapons/arrow_front.xml`), `vis.projectile_bolt` (`props/units/weapons/bolt.xml`), `vis.projectile_stone` (`props/units/siege_artillery/stone_projectile_large.xml`, the same prop the lithobolos loads). All simple static single-mesh props with no armature — none of the composite/nested-prop defects hit the mounted/crewed units apply here. 5 directions mirrored to 8 (free-flying, not handed, so mirroring is safe unlike every weapon-holding unit baked so far), small canvases (64–128 px), clean bakes. Recipes: `tools/recipes/projectile_{arrow,bolt,stone}.toml` |
| Attack/impact effects | ⬜ TODO | |

### 2.2 Buildings — full roster

All need foundation / construction / complete / damaged / rubble. **Complete state baked for all 12 roster entries as of 2026-08-08**, including the wall/gate set, which turned out not to need special treatment (see its row below) — mapped from `simulation/templates/structures/athen/*.xml`, which names the actor, footprint and rubble directly for every one of these, so none of it was guesswork. **Foundation and rubble are also done for every entry** — the 9-building batch's 12 recipes plus the wall set's 6 more (3 foundations, 3 rubble, one shared with the gate), all baked with no canvas-edge clip warnings; see the per-row notes below. Per-age visual variants and the damaged tier remain untouched (0 A.D. has no damaged tier either, per §1.2).

Two pipeline gaps this batch found and closed, both worth knowing before baking the next one:

- **`directions = 1` shows the back of the building by default**, because that mode suppresses the base yaw entirely and the mesh stays exactly as 0 A.D. authored it — which does not face this camera. All nine went out with `yaw_offset_deg = 180.0` and a visual check (front vs. back) before being called done; the first pass at `yaw_offset_deg = 0` on all nine had every single one showing a blank rear wall.
- **`isobake bake` could not tell a canvas was too small.** It trims each frame toward its content and never checked whether that content already reached the canvas edge, so a cropped sprite produced no warning anywhere — `isobake verify`'s checks only ever look at the atlas *after* packing, by which point the missing pixels are simply gone. Found by eye on the castle (its roof peak cut flat), then fixed properly: `isobake bake` now checks the untrimmed frame against `render.canvas` and reports exactly which frame clipped. Running it against the other eight caught two more — the archery range's yard walls (touching both left and right edges) and the stable's chimney finial — that had looked fine in the turntable.

| Asset | Status | Notes |
|---|---|---|
| `vis.barracks` | 🟦 **BAKED** | `structures/athenians/barracks.xml`, 334×258 px. Rubble: `vis.rubble_5x5` (shared with range/stable/market, baked 2026-08-08). Foundation: `vis.foundation_6x6` (baked 2026-08-08). Recipe: `tools/recipes/barracks.toml` |
| `vis.archery_range` | 🟦 **BAKED** | `structures/hellenes/range.xml` (Athenians declare no override), 435×281 px. Rubble: `vis.rubble_5x5`. Foundation: `vis.foundation_7x7` (shared with stable, baked 2026-08-08). Recipe: `tools/recipes/archery_range.toml` |
| `vis.stable` | 🟦 **BAKED** | `structures/hellenes/stable.xml`, 336×257 px. Ships a horse mesh with its own armature purely as static dressing — caught a real bug in `render.ground_clip`'s safety check, which refused any skinned subject; fixed to key off whether a clip is actually played (isobake, this session), since a static recipe never assigns one and the rest pose is exactly as safe to cut as any frozen mesh. Rubble: `vis.rubble_5x5`. Foundation: `vis.foundation_7x7`. Recipe: `tools/recipes/stable.toml` |
| `vis.blacksmith` | 🟦 **BAKED** | `structures/hellenes/blacksmith.xml` (the sim template calls this a "forge"; kept as `vis.blacksmith` for readability), 255×212 px. Rubble: `vis.rubble_4x4` (baked 2026-08-08). Foundation: `vis.foundation_5x5` (baked 2026-08-08). Recipe: `tools/recipes/blacksmith.toml` |
| `vis.market` | 🟦 **BAKED** | `structures/hellenes/market.xml`, 342×213 px. Rubble: `vis.rubble_5x5`. Foundation shares `vis.foundation_8x8` (already baked). Recipe: `tools/recipes/market.toml` |
| `vis.mill` | 🟦 **BAKED** | `structures/hellenes/farmstead.xml` — 0 A.D. has no separate mill, the farmstead is the nearest food-processing building in its roster, 254×187 px. Rubble: `vis.rubble_4x2` (baked 2026-08-08). Foundation: `vis.foundation_5x4` (baked 2026-08-08). Recipe: `tools/recipes/mill.toml` |
| `vis.lumber_camp` | 🟦 **BAKED** | `structures/hellenes/storehouse.xml`, 284×202 px. Rubble shares `vis.rubble_3x3` (already baked). Foundation: `vis.foundation_3x3` (baked 2026-08-08). Recipe: `tools/recipes/lumber_camp.toml` |
| `vis.mining_camp` | 🟦 **BAKED** | **Decided 2026-08-08** (project owner): option (b), a visually distinct building rather than reusing `vis.lumber_camp`'s atlas. `structures/britons/storehouse.xml` — a different civ's storehouse, which carries its own `storehouse_ore` prop and so reads as a stone/metal store rather than the hellenes wood store. Foundation shares `vis.foundation_4x4`; rubble shares `vis.rubble_3x3` (both already baked — `template_structure_economic_storehouse` pairs this actor with the same generic 4x4/3x3 pair as `vis.lumber_camp`). Recipe: `tools/recipes/mining_camp.toml` |
| `vis.tower` | 🟦 **BAKED** | `structures/athenians/wall_tower.xml`, 124×241 px — the tallest, narrowest building baked so far (14.8 m on a 4 m footprint). Rubble: `vis.rubble_wall_tower` (baked 2026-08-08). Foundation: `vis.foundation_3x3_tower` (baked 2026-08-08). Recipe: `tools/recipes/tower.toml` |
| `vis.castle` | 🟦 **BAKED** | `structures/athenians/fortress.xml`, 384×365 px. The corner tower's roof peak clipped at the original canvas [448,384]/0.4: `height*cos(30)*ppm` alone missed that the tallest point also sits toward the far corner, whose depth adds its own upward screen offset on top of the height term. Raised to [448,480]/0.32. Rubble: `vis.rubble_6x6` (baked 2026-08-08). Foundation shares `vis.foundation_8x8` (already baked). Recipe: `tools/recipes/castle.toml` |
| `vis.wall_short` / `vis.wall_medium` / `vis.wall_long` | 🟦 **BAKED** | **Turned out not to be a different shape of problem, 2026-08-08.** 0 A.D.'s own `WallPiece` component (`simulation/components/WallPiece.js`) places a fixed catalog of rigid straight segments end-to-end — no dynamic mesh tiling to reproduce — so each is an ordinary single-sprite `directions = 1` bake, same as every other building here. `structures/athenians/wall_{short,medium,long}.xml`, 6.5/12.5/18.5 m footprints, all ~11.5 m tall. Foundations: `vis.foundation_3x3_wall`, `vis.foundation_6x3_wall`, `vis.foundation_9x3_wall` (the last shared with the gate). Rubble: `vis.rubble_wall_short`, `vis.rubble_wall_medium`, `vis.rubble_wall_long`. Canvas sizing needed a real jump past the footprint-box estimate — the wall mesh overhangs its plain footprint (coping/crenellations) — see `tools/recipes/wall_medium.toml`'s comment. Recipes: `tools/recipes/wall_{short,medium,long}.toml` |
| `vis.wall_gate` | 🟦 **BAKED** | `structures/athenians/wall_gate_door.xml` (an animated door armature, `gate_closed`/`gate_opening`/`gate_open`/`gate_closing`) + static `wall_gate_struct.xml` frame prop. Baked at rest pose (closed) — no recipe animation assigned, same treatment as `vis.stable`'s static horse mesh. Open/closing states are a gameplay-animation feature, not an art gap; not attempted. Foundation shares `vis.foundation_9x3_wall` (0 A.D.'s own pairing, same as `vis.wall_long`); rubble shares `vis.rubble_wall_long` since the actor declares no distinct `SpawnEntityOnDeath`, deferring to the wall base. Recipe: `tools/recipes/wall_gate.toml` |
| Wall corner | 🟦 **BAKED (reused)** | No new bake needed — 0 A.D. has no distinct angled/L-shaped corner mesh; the square `wall_tower.xml` (already baked as `vis.tower`) doubles as the corner by placement convention |
| `vis.wonder` | 🟦 **BAKED** | `structures/hellenes/temple_epic.xml` — the Parthenon, and by far the largest asset in the project: 651×505 px, a 14×29 m footprint (nearly 4× the town centre's). If wonder victory is implemented. Rubble shares `vis.rubble_6x6` (with the castle, baked 2026-08-08) — though whether a wonder should have a rubble state at all is a game-design call, not an art one. Foundation: `vis.foundation_7x15_hele` (baked 2026-08-08, its own bespoke size — no other building shares it). Recipe: `tools/recipes/wonder.toml` |

| Per-age visual variants | ⬜ TODO | Ages I–V change building appearance |

**Bonus finding from the previous pass, fixed this session:** the same canvas-edge check run against the existing MVP set found `vis.tree` clipping its canopy on the left, right and top edges of its 224×224 canvas since the 0.9 bake. Rebaked 2026-08-08 at 320×320 with no clip warning — see §1.3.

### 2.3 Resources & wildlife — full set

| Asset | Status | Notes |
|---|---|---|
| `vis.stone_mine` | 🟦 **BAKED** | `geology/stonemine_medit_quarry.xml`, declared directly by `simulation/templates/gaia/rock/mediterranean_large.xml`. 5 directions, 9.74×9.32×6.74 m, clean bake with no clip warning and no buried geometry (`ground_clip` cut 0 meshes). Mediterranean, civ-matching — unlike `vis.gold_mine`'s alpine pick, there was no readability problem here to reject it for ("quarried rock" is unambiguous at sprite size). Recipe: `tools/recipes/stone_mine.toml` |
| `vis.berry_bush` | 🟦 **BAKED (full only)** | `props/flora/berry_bush.xml`, the gaia fruit template's own VisualActor (no building-style wrapper). 5 directions, 5.22×5.0×3.40 m. Recipe: `tools/recipes/berry_bush.toml`. **No depleted state exists to bake** — `template_gaia_fruit.xml` uses `Regrowth` with `KillBeforeGather=false`, so 0 A.D. never shows a picked/empty bush, and the actor has no such variant (only random mesh/texture variety). "Depleted" stays TODO with nothing to map to |
| `vis.farm` | ⚠️ **BLOCKED** | **Found and diagnosed 2026-08-08, not a quick fix.** `structures/athen/field.xml` → `structures/plot_field_medit.xml`, a mesh with 64 plain (non-bone) scatter attachpoints each meant to hold a `foliagebush` prop — confirmed genuinely present in the mesh, not a 0 A.D. content bug. Baking it renders only **one** visible foliage clump instead of 64 spread across the field, plus a stray mesh far below ground. Not isobake's own code either: `_attach_prop` only runs for animation-variant props via a bone constraint, and this mesh has no armature at all — attaching base-actor props to non-bone scatter nodes is the first-party Pyrogenesis Blender importer's job, and something there collapses many instances into one. Every other field variant (temp/desert/tropic/chin/3D_8x8/...) scatters the same way, so no substitute actor sidesteps it. Fixing it means patching the Pyrogenesis importer or teaching isobake to scatter props onto non-armature nodes itself — bigger than one asset bake. Foundation (`structures/plot_field_found.xml`) and rubble (`structures/plot_field_fallow.xml`) are both flat decals with no scattered props and would bake fine on their own; only the complete state is blocked. Recipe `tools/recipes/farm.toml` documents the dead end, same treatment as `deer.toml` |
| `vis.boar` | 🟦 **BAKED (static only)** | `fauna/boar.xml`, 5 directions, 128×128 canvas, clean bake. **Static, same reasoning as `vis.deer`:** a quadruped with its own armature (28 bones) — no clip attached, so PLAN.md 13.2 item 8's animation-transfer bug (clip file and mesh file describe the same skeleton ~31× apart) never triggers. Recipe: `tools/recipes/boar.toml` |
| `vis.sheep` | 🟦 **BAKED (static only)** | `fauna/sheep1.xml`, 5 directions, 128×128 canvas, clean bake. Static, same reasoning as `vis.boar`/`vis.deer` (23-bone armature, no clip attached). Note: actor's alpha role is `playercolor`, so it may pick up faction tint on-screen — worth a look before treating it as neutral gaia wildlife. Recipe: `tools/recipes/sheep.toml` |
| `vis.fish` | 🟦 **BAKED (static only)** | `fauna/tuna.xml`, 5 directions, 128×96 canvas, clean bake. **Two rejected picks before this one, in order:** `fauna/fish.xml` baked as an untextured, wireframe-looking mesh floating well off its own ground anchor (isobake's own anchor-outside-bounds check flagged it) — not a usable sprite, not investigated further. `fauna/fish_single.xml` baked clean but at true scale (0.277 m raw height, ~14 cm once scaled) it is imperceptible, a handful of pixels. Tuna is the readability pick (2.814 m raw) — same principle as `vis.gold_mine` choosing the alpine ore mesh over the civ-matching one for legibility at sprite size. Recipe: `tools/recipes/fish.toml` |
| `vis.wolf` | 🟦 **BAKED (static only)** | `fauna/wolf.xml`, 5 directions, 128×128 canvas, clean bake. Static, same reasoning as `vis.boar`/`vis.deer` (32-bone armature, no clip attached). Recipe: `tools/recipes/wolf.toml` |
| Tree species variants | 🟦 **BAKED (6 of 6 deterministic candidates)** | Every genuinely standalone, single-`<variant>` (fully deterministic) 0 A.D. tree actor now has a recipe and a clean bake, all 5 directions, no clip warnings, all baked 2026-08-08: `vis.tree_snow_pine` (`flora/trees/snow_pine2.xml`, snowy conifer, 640×640 canvas), `vis.tree_cypress` (`flora/trees/cypress_test.xml`, columnar non-snowy conifer, 384×384), `vis.tree_cypress_tall` (`flora/trees/mediterranean_cypress_tall.xml`, a narrower/shorter giant cypress — reads as a distinct size class of the same species, 320×320), `vis.tree_dead` (`flora/trees/dead_a_2.xml`, bare sprawling dead tree, 448×448 with `ground_clip = true`), `vis.tree_dead_branchy` (`flora/trees/dead_a_1.xml`, a second bare-tree look with an attached single dead-branch prop — one prop instance attaches fine, unlike `vis.farm`'s blocked 64-instance scatter case; also 448×448 with `ground_clip = true`). Both dead-tree meshes turned out to be buried below world z = 0 by nearly a third of their height (15.0 m → 10.5 m and 13.1 m → 8.9 m once clipped) — the same buried-geometry pattern as the building skirts (§1.2), not an undersized canvas: the warning was the trunk clipping at the *bottom* of the frame, not the canopy at the top, and raising canvas alone (tried up to 2048×2048) never fixed it since the buried geometry scales with the frame. `ground_clip` (already used on `stone_mine.toml`, so proven safe on a `directions = 5` non-building) fixed both at a normal canvas size. `vis.tree_cherry` (`flora/trees/cherry_small.xml`, trunk + attached blossom-canopy prop, short-and-wide rather than tall, 384×320). Recipes: `tools/recipes/tree_{snow_pine,cypress,cypress_tall,dead,dead_branchy,cherry}.toml`. **Deliberately not baked:** `deci_1`/`deci_100percent`/`deci_50percent.xml` (share oak's mesh family + `oak-trees.dds` texture — redundant look, no new variety); all palm actors (every one uses 2–3 random `<group>`s, same combinatorial-variant structure as oak — no deterministic palm exists in 0 A.D.'s asset set, so a palm needs the same variant-selection isobake feature that oak's extra size classes need, not attempted this pass); `baobab_new_sapling.xml` (looked single-variant at a glance but its leaf prop randomizes over 3 textures — same oak-style case, not the deterministic pipeline). None of the 6 are wired into `game/data/visuals.json` yet — that edit is outside this agent's `./game` lane |

### 2.4 Terrain — full set

| Asset | Status | Notes |
|---|---|---|
| Rock / mountain (impassable) | 🟦 **BAKED** | `terrain.rock` baked 2026-08-08 from `biome-mediterranean/medit_rocks.xml`, civ-matching with grass1/dirta/sand and `vis.stone_mine`. Same recipe shape as `terrain_grass.toml` — 64×32 exact, no fitting needed. Recipe: `tools/recipes/terrain_rock.toml` |
| Forest floor | 🟦 **BAKED** | `terrain.forest_floor` baked 2026-08-08 from `forestfloor/forestfloor_pine.xml`. Same recipe shape as `terrain_grass.toml`. Recipe: `tools/recipes/terrain_forestfloor.toml` |
| Snow / desert biomes | ⬜ TODO | Only if biomes are implemented |
| Cliffs | ⬜ TODO | |
| Shoreline transitions | ⬜ TODO | Needed with water domain |
| Fog-of-war overlay texture | ⬜ TODO | Needed for 2.5 |

### 2.5 UI — full set

| Asset | Status | Notes |
|---|---|---|
| Age header banner + roman numerals I–V | ⬜ TODO | Phase 9.1 |
| Tech tree screen chrome | ⬜ TODO | Reference: `insperation_pictures/techtree.png` |
| Tech/upgrade icons | ⬜ TODO | **Large volume** — one per tech |
| Market/trade screen chrome | ⬜ TODO | Reference: `insperation_pictures/Market.png` |
| Chat/voice overlay | ⬜ TODO | Reference: `UI_Design_Chat_Voice.jpg` |
| Victory / defeat screens | ⬜ TODO | |
| Minimap frame (circular, 4 corner buttons) | 🟨 SOURCED | Dragon pack |
| Faction emblems | ⬜ TODO | One per faction |

### 2.6 Audio — full set

0 A.D. audio is confirmed available and licence-clean: `binaries/data/mods/public/audio/` holds `.ogg` files plus XML descriptors under CC-BY-SA 3.0, in `actor`, `ambient`, `attack`, `groups`, `interface`, `music`, `resource` and `voice` subtrees.

| Category | 0 A.D. path | Status | Notes |
|---|---|---|---|
| Combat sfx (melee, ranged, siege) | `audio/attack/` | 🟨 SOURCED | Direct reuse likely |
| Resource-gathering sfx | `audio/resource/` | 🟨 SOURCED | Maps onto `work_chop` / `work_mine` |
| Building sfx per type | `audio/actor/` | 🟨 SOURCED | |
| Ambient loops (birds, wind, water) | `audio/ambient/` | 🟨 SOURCED | |
| UI sfx | `audio/interface/` | 🟨 SOURCED | |
| In-game + menu music | `audio/music/` | 🟨 SOURCED | Ancient-warfare orchestral; check fantasy fit |
| Per-unit selection/acknowledge voices | `audio/voice/{greek,latin,napatan,persian}/` | ⬜ TODO | **Civilisation- and language-specific** — spoken Greek/Latin will not suit a medieval-fantasy setting. Either use `voice/global/` only, or source/record fresh |
| Age advancement sting | — | ⬜ TODO | |
| Victory / defeat music | — | ⬜ TODO | |
| Dragon roar / fire breath | — | 🎨 BESPOKE | No source exists |

---

## 3. Bespoke — no source exists

These cannot come from any pack and must be commissioned or hand-drawn. Budget explicitly.

| Asset | Needs | Status |
|---|---|---|
| `vis.dragon` | `idle` (hover), `fly`, `attack`, `fire_breath` (AoE special), `die`, `decay` × 5 directions. Air domain, so it renders above everything | 🎨 BESPOKE |
| `vis.dragon_baby` | Same animation set, smaller | 🎨 BESPOKE |
| `vis.dragon_nest` | Neutral / claimed / damaged / destroyed states | 🎨 BESPOKE |
| Fire-breath VFX | Area effect animation | 🎨 BESPOKE |
| Game logo / icon / splash | App icon, store art | 🎨 BESPOKE |
| Dragon-themed UI accents | If the itch.io packs don't cover a needed element | 🎨 BESPOKE |

**Note:** the dragon is the game's differentiator (IDEA.md phase 13). It is also the one asset with zero free-source coverage. Worth commissioning properly rather than approximating.

---

## 4. Open sourcing questions

Tracked in PLAN.md §13:

1. ~~**0 A.D. render pipeline**~~ — ✅ **ANSWERED at 0.9: yes.** Built as [`isobake`](https://github.com/HermanRas/blender_3d_to_2d_isobake) and proven on a grass tile, an oak and a 240-frame animated citizen. The Widelands / Unknown Horizons fallbacks are not needed. One gap remains: props declared by an animation variant are not imported, so the villager chops without her axe.
2. **Actor→entity mapping** — 0 A.D.'s roster is ancient warfare (hoplites, war elephants, Persian cavalry); ours is medieval fantasy. Needs a hand-picked mapping from their actor XML to our `vis.*` IDs, and some entities will have no good match. Three chosen at 0.9; the mapping now lives in `tools/recipes/*.toml`, one file per asset.
3. **Voice audio** — 0 A.D.'s unit voices are civilisation-specific spoken language. Decide between `voice/global/` only, fresh sourcing, or no unit voices at all.
4. **Icon volume** — tech and unit icons are individually trivial but numerous. Decide whether to crop from sprites, generate, or commission a set.
