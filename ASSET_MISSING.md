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
| `vis.villager` | `idle`, `walk`, `walk_carry_wood`, `walk_carry_gold`, `walk_carry_food`, `work_chop`, `work_mine`, `work_hunt`, `work_build`, `die`, `decay` | 🟦 **BAKED (all 11)** | All 11 animations baked from `units/athenians/female_citizen.xml`, 960 frames (8 directions), 160×160 canvas. Recipe: `tools/recipes/villager.toml`. Variant props (axe, pick, mallet, dagger, wood/ore/grain shuttles, berry basket) import and attach correctly (PLAN.md §14). **Known issue:** in `work_mine` her dress mesh stretches oddly — a dress vertex is weighted 100% to `hand_L` in the source mesh and gets dragged when the mining clip's hand pose differs sharply from the citizen's native poses. Cosmetic, isolated to that one clip; **accepted for MVP**, tracked as PLAN.md §13.2 item 7 alongside the buried building skirts — both are source-mesh defects for one post-MVP art pass. **Second known issue, and this one is not cosmetic: she is 2.18 m tall.** `isobake inspect` measures the actor at 4.356 raw units, which is 2.178 m at the pipeline's 0.5 factor — 16 cm *taller than the stag* (2.020 m). She inherits 0 A.D.'s own proportions because the recipe declares no override. Fix is one `height_m` line on `villager.toml` plus a rebake of her 960 frames; the only open question is what height to pick. **Needs a rebake** — PLAN.md §13.2 item 9 has the measurements, and a correction: an earlier note here claimed a 2× pipeline bug, which was wrong |
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
| `vis.tree` | 3 size classes + stump/depleted | 🟦 **BAKED (1 of 4)** | Oak baked at 0.9 from `flora/trees/oak.xml`, 5 directions, ~10 m tall. Recipe: `tools/recipes/tree_oak.toml`. The actor has 6 variants (2 meshes × 3 textures + small) — the size classes come from those. A.4 |
| `vis.gold_mine` | 1 sprite (size is data-only, not visual) | 🟩 **BAKED** | Baked from `geology/metalmine_alpine.xml`, 5 directions, 2.80 × 3.87 × 1.21 m at the default tile-to-tile scale — a ~1.4 × 1.9 tile footprint, which agrees with 0 A.D.'s own 7×7-world-unit (1.75 tile) obstruction for the node. Recipe: `tools/recipes/gold_mine.toml`. Alpine, not the civ-matching `metalmine_granite_greek`, because that one's texture is olive-green and its veins vanish at sprite size; all the old-generation ore actors share the same lead mesh and differ only in texture, so this was purely which one reads as gold. The actor has 6 variants (3 formations + 3 boulders) — the three `size_class` visuals come from those if we ever want them non-data-only, but reaching past `formation-a` needs variant selection in `isobake`, which does not exist. A.4 |

### 1.4 Terrain

| Asset | Status | Notes |
|---|---|---|
| Grass / dirt / sand iso tiles | 🟦 **BAKED (grass)** | `terrain.grass` baked at 0.9 from `grass/grass1.xml` at exactly 64×32 (measured area 1024.00 px², against 1024.00 expected). Recipe: `tools/recipes/terrain_grass.toml` — dirt and sand are the same recipe with a different `terrain =` line. A.1 |
| Water shallow / deep | ⬜ TODO | Not needed for MVP (land domain only) but cheap alongside A.1 |
| Tile transitions / blending | ⬜ TODO | Post-MVP polish; hard edges are acceptable initially |

### 1.5 UI

| Asset | Status | Notes |
|---|---|---|
| Panel frames, buttons, bars | 🟨 SOURCED | itch.io dragon packs already in `UI_Sprites/`. A.5 |
| Fonts | 🟨 SOURCED | `uı-fonts` pack. Ships **inside the APK** |
| Resource icons (stone, gold, wood, food, villager) | ⬜ TODO | 5 icons. Check dragon pack coverage first, else simple originals |
| Unit/building portrait icons | ⬜ TODO | Needed for selection panel + control group slots. Can crop from unit sprites |
| Control-group slot frames (empty + filled) | 🟨 SOURCED | Dragon pack circular frames |
| Selection ring / health dot | ⬜ TODO | Trivial originals — draw in-engine |

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

Each needs `idle`, `walk`, `attack`, `die`, `decay` × 5 directions.

| Asset | Status | Notes |
|---|---|---|
| `vis.militia` | ⬜ TODO | A.8 |
| `vis.archer` | ⬜ TODO | A.8 |
| `vis.spearman` | ⬜ TODO | A.8 |
| `vis.knight` | ⬜ TODO | Mounted — more frames | 
| `vis.siege_ram` | ⬜ TODO | |
| `vis.trebuchet` | ⬜ TODO | Packed + unpacked states |
| `vis.monk` | ⬜ TODO | Plus relic-carrying variant |
| `vis.trade_cart` | ⬜ TODO | Loaded + empty variants |
| Projectiles (arrow, bolt, stone) | ⬜ TODO | Small; needed with `CombatSystem` |
| Attack/impact effects | ⬜ TODO | |

### 2.2 Buildings — full roster

All need foundation / construction / complete / damaged / rubble. **Complete state baked for 9 of 12** — mapped from `simulation/templates/structures/athen/*.xml`, which names the actor, footprint and rubble directly for every one of these, so none of it was guesswork. Foundation and rubble are the next pass; most reuse a size already baked or share one bake across several buildings, per §1.2's shared-by-footprint-size rule.

| Asset | Status | Notes |
|---|---|---|
| `vis.barracks` | 🟦 **BAKED** | `structures/athenians/barracks.xml`, 334×231 px. Rubble shares `rubble_stone_5x5` with range/stable/market; foundation needs `fndn_6x6` (not yet baked). Recipe: `tools/recipes/barracks.toml` |
| `vis.archery_range` | 🟦 **BAKED** | `structures/hellenes/range.xml` (Athenians declare no override), 384×267 px. Rubble shares `rubble_stone_5x5`; foundation needs `fndn_7x7` (not yet baked, shared with stable). Recipe: `tools/recipes/archery_range.toml` |
| `vis.stable` | 🟦 **BAKED** | `structures/hellenes/stable.xml`, 336×218 px. Ships a horse mesh with its own armature purely as static dressing — caught a real bug in `render.ground_clip`'s new safety check, which refused any skinned subject; fixed to key off whether a clip is actually played (isobake, this session), since a static recipe never assigns one and the rest pose is exactly as safe to cut as any frozen mesh. Rubble shares `rubble_stone_5x5`; foundation needs `fndn_7x7`. Recipe: `tools/recipes/stable.toml` |
| `vis.blacksmith` | 🟦 **BAKED** | `structures/hellenes/blacksmith.xml` (the sim template calls this a "forge"; kept as `vis.blacksmith` for readability), 255×156 px. Rubble needs `rubble_stone_4x4` (not yet baked); foundation needs `fndn_5x5` (not yet baked). Recipe: `tools/recipes/blacksmith.toml` |
| `vis.market` | 🟦 **BAKED** | `structures/hellenes/market.xml`, 342×210 px. Rubble shares `rubble_stone_5x5`; foundation shares `vis.foundation_8x8` (already baked). Recipe: `tools/recipes/market.toml` |
| `vis.mill` | 🟦 **BAKED** | `structures/hellenes/farmstead.xml` — 0 A.D. has no separate mill, the farmstead is the nearest food-processing building in its roster, 247×139 px. Rubble needs `rubble_stone_4x2`; foundation needs `fndn_5x4` (neither baked yet). Recipe: `tools/recipes/mill.toml` |
| `vis.lumber_camp` | 🟦 **BAKED** | `structures/hellenes/storehouse.xml`, 284×152 px. Rubble shares `vis.rubble_3x3` (already baked); foundation needs `fndn_3x3` (not yet baked). Recipe: `tools/recipes/lumber_camp.toml` |
| `vis.mining_camp` | ⚠️ **NEEDS A DECISION** | 0 A.D. has exactly one generic resource storehouse, already used for `vis.lumber_camp` above — there is no second actor to distinguish a wood store from a stone/gold store. Not baked separately rather than silently duplicating: pick either (a) reuse `vis.lumber_camp`'s atlas for both IDs, or (b) source a visually distinct building (a different storehouse variant, or a non-0-A.D. asset) |
| `vis.tower` | 🟦 **BAKED** | `structures/athenians/wall_tower.xml`, 124×240 px — the tallest, narrowest building baked so far (14.8 m on a 4 m footprint). Rubble needs `rubble_stone_wall_tower`; foundation needs `fndn_3x3_tower` (neither baked yet). Recipe: `tools/recipes/tower.toml` |
| `vis.castle` | 🟦 **BAKED** | `structures/athenians/fortress.xml`, 383×322 px. Rubble needs `rubble_stone_6x6`; foundation shares `vis.foundation_8x8` (already baked). Recipe: `tools/recipes/castle.toml` |
| `vis.wall` + gate | ⬜ TODO | Needs segment/corner tiling set — a different shape of problem from the single-sprite buildings above (`wall_long`/`wall_medium`/`wall_short`/`wall_gate` in `structures/athenians/`), deliberately not attempted alongside them |
| `vis.wonder` | 🟦 **BAKED** | `structures/hellenes/temple_epic.xml` — the Parthenon, and by far the largest asset in the project: 651×506 px, a 14×29 m footprint (nearly 4× the town centre's). If wonder victory is implemented. Rubble needs `rubble_stone_6x6` (shared with the castle) — though whether a wonder should have a rubble state at all is a game-design call, not an art one. Foundation shares nothing existing (`fndn_7x15_hele`, not baked). Recipe: `tools/recipes/wonder.toml` |
| Per-age visual variants | ⬜ TODO | Ages I–V change building appearance |

### 2.3 Resources & wildlife — full set

| Asset | Status | Notes |
|---|---|---|
| `vis.stone_mine` | ⬜ TODO | |
| `vis.berry_bush` | ⬜ TODO | Full + depleted |
| `vis.farm` | ⬜ TODO | Growth stages + depleted |
| `vis.boar` | ⬜ TODO | Aggressive wildlife |
| `vis.sheep` | ⬜ TODO | Herdable |
| `vis.fish` | ⬜ TODO | Water resource |
| `vis.wolf` | ⬜ TODO | Hostile wildlife |
| Tree species variants | ⬜ TODO | Pine/palm/oak for biome variety |

### 2.4 Terrain — full set

| Asset | Status | Notes |
|---|---|---|
| Rock / mountain (impassable) | ⬜ TODO | |
| Forest floor | ⬜ TODO | |
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
