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
| `vis.villager` | `idle`, `walk`, `walk_carry_wood`, `walk_carry_gold`, `walk_carry_food`, `work_chop`, `work_mine`, `work_hunt`, `work_build`, `die`, `decay` | 🟦 **BAKED (partial)** | 4 of 11 animations baked from `units/athenians/female_citizen.xml` — `idle`, `walk`, `work_chop`, `walk_carry_wood`, 384 frames (8 directions). Recipe: `tools/recipes/villager.toml`. Remaining 7 are A.3. Variant props (axe, carried wood) now import and attach correctly (PLAN.md §14) |
| `vis.deer` | `idle`, `walk`, `die`, `decay` | 🟨 SOURCED | Carcass state must read as gatherable. A.4 |

### 1.2 Buildings

| Asset | States needed | Status | Notes |
|---|---|---|---|
| `vis.town_center` | foundation, under-construction, complete, damaged, rubble | 🟨 SOURCED | 4×4 footprint. A.2 |
| `vis.house` | foundation, under-construction, complete, damaged, rubble | 🟨 SOURCED | A.2 |

### 1.3 Resource props

| Asset | Variants needed | Status | Notes |
|---|---|---|---|
| `vis.tree` | 3 size classes + stump/depleted | 🟦 **BAKED (1 of 4)** | Oak baked at 0.9 from `flora/trees/oak.xml`, 5 directions, ~10 m tall. Recipe: `tools/recipes/tree_oak.toml`. The actor has 6 variants (2 meshes × 3 textures + small) — the size classes come from those. A.4 |
| `vis.gold_mine` | 1 sprite (size is data-only, not visual) | 🟨 SOURCED | A.4 |

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
