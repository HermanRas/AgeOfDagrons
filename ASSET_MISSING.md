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
| `vis.villager` | `idle`, `walk`, `walk_carry_wood`, `walk_carry_gold`, `walk_carry_food`, `work_chop`, `work_mine`, `work_hunt`, `work_build`, `die`, `decay` | 🟨 SOURCED | **~825 frames** (11 anims × 15 frames × 5 directions). Most expensive single asset in the project. Art track A.3 |
| `vis.deer` | `idle`, `walk`, `die`, `decay` | 🟨 SOURCED | Carcass state must read as gatherable. A.4 |

### 1.2 Buildings

| Asset | States needed | Status | Notes |
|---|---|---|---|
| `vis.town_center` | foundation, under-construction, complete, damaged, rubble | 🟨 SOURCED | 4×4 footprint. A.2 |
| `vis.house` | foundation, under-construction, complete, damaged, rubble | 🟨 SOURCED | A.2 |

### 1.3 Resource props

| Asset | Variants needed | Status | Notes |
|---|---|---|---|
| `vis.tree` | 3 size classes + stump/depleted | 🟨 SOURCED | A.4 |
| `vis.gold_mine` | 1 sprite (size is data-only, not visual) | 🟨 SOURCED | A.4 |

### 1.4 Terrain

| Asset | Status | Notes |
|---|---|---|
| Grass / dirt / sand iso tiles | 🟨 SOURCED | From 0 A.D. tileable ground textures via `bake_terrain.py`. **Art track A.1 — do this first**, biggest visual payoff, validates the render pipeline |
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

All need foundation / construction / complete / damaged / rubble.

| Asset | Status |
|---|---|
| `vis.barracks` | ⬜ TODO |
| `vis.archery_range` | ⬜ TODO |
| `vis.stable` | ⬜ TODO |
| `vis.blacksmith` | ⬜ TODO |
| `vis.market` | ⬜ TODO |
| `vis.mill` | ⬜ TODO |
| `vis.lumber_camp` | ⬜ TODO |
| `vis.mining_camp` | ⬜ TODO |
| `vis.tower` | ⬜ TODO |
| `vis.castle` | ⬜ TODO |
| `vis.wall` + gate | ⬜ TODO | Needs segment/corner tiling set |
| `vis.wonder` | ⬜ TODO | If wonder victory is implemented |
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

| Category | Status | Notes |
|---|---|---|
| Per-unit selection/acknowledge voices | ⬜ TODO | Large volume. 0 A.D. voices are civ-specific — may not fit |
| Combat sfx (melee, ranged, siege) | ⬜ TODO | 0 A.D. candidate |
| Building sfx per type | ⬜ TODO | |
| Ambient loops (birds, wind, water) | ⬜ TODO | |
| Age advancement sting | ⬜ TODO | |
| Victory / defeat music | ⬜ TODO | |
| In-game music tracks | ⬜ TODO | 0 A.D. soundtrack |

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

1. **0 A.D. render pipeline** — can `render_3d_to_iso.py` produce clean 8-direction sheets? Validate on one unit (phase 0.9) before committing to the villager. If it fails, **Widelands** (already 2D isometric, licence-compatible) is the fallback for units and buildings.
2. **0 A.D. audio coverage** — how much is usable for a dragon-fantasy setting vs how much needs CC0 sourcing (`freesound.org`) or commissioning.
3. **Icon volume** — tech and unit icons are individually trivial but numerous. Decide whether to crop from sprites, generate, or commission a set.
