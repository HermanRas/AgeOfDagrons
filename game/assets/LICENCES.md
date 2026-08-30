# Per-asset provenance

Every asset this project ships must appear in this file. "Ships" means one of two
things:

1. **Inside the APK** — anything under `game/assets/`.
2. **Inside the downloadable art pack** — every atlas baked by a recipe in
   `tools/recipes/` (PLAN.md §3.2). The atlases are not committed, so the recipe is
   the durable record of what we ship and where it came from.

Checked by [`tools/licence_audit.py`](../../tools/licence_audit.py), which exits
non-zero on anything undeclared:

```
python tools/licence_audit.py
```

**Nothing runs that for you** — this repo has no CI (PLAN.md §1.2). Run it before a
release and whenever you add an asset. Attribution is a licence obligation, so an
undeclared asset is a licence violation, not untidiness.

Project-level credit lives in [`CREDITS.md`](../../CREDITS.md); this file is the
per-asset detail behind it.

---

## 0 A.D. — the required attribution

Everything in the generated table below derives from **0 A.D.** by rendering Wildfire
Games' 3D models to 2D isometric sprite atlases. Their `art/LICENSE.txt` requires three
things **verbatim**, and the audit fails if any of them is missing or shortened:

- Licence: **Creative Commons Attribution-ShareAlike 3.0** — http://creativecommons.org/licenses/by-sa/3.0/
- Original author: **Wildfire Games**
- Author link: http://www.wildfiregames.com/

**Modification made:** 3D meshes, textures and animations were rendered through a fixed
isometric orthographic camera and packed into trimmed texture atlases. CC-BY-SA 3.0 is
share-alike, so **our derived atlases are themselves CC-BY-SA 3.0** — see
[`LICENSE-ART.md`](../../LICENSE-ART.md). The game code is MIT; the two do not merge.

---

## Art pack — baked atlases

One row per recipe. Regenerate with `python tools/licence_audit.py --write`.

<!-- BEGIN GENERATED: recipes -->

<!-- Do not edit by hand. Regenerate with:
       python tools/licence_audit.py --write -->

| Asset ID | Source file | Origin | Licence |
|---|---|---|---|
| `vis.archer` | `archer.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archery_range` | `archery_range.toml` | `art/actors/structures/hellenes/range.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archery_range_age2` | `archery_range_age2.toml` | `art/actors/structures/gauls/range.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archery_range_age3` | `archery_range_age3.toml` | `art/actors/structures/iberians/range.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archery_range_age4` | `archery_range_age4.toml` | `art/actors/structures/romans/range.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.ballista` | `ballista.toml` | `art/actors/units/carthaginians/siege_lithobolos_med.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.ballista_packed` | `ballista_packed.toml` | `art/actors/units/carthaginians/siege_rock_packed.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.barracks` | `barracks.toml` | `art/actors/structures/athenians/barracks.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.barracks_age2` | `barracks_age2.toml` | `art/actors/structures/celts/barracks.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.barracks_age3` | `barracks_age3.toml` | `art/actors/structures/iberians/barracks.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.barracks_age4` | `barracks_age4.toml` | `art/actors/structures/romans/barracks.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.bear` | `bear.toml` | `art/actors/fauna/bear_brown.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.bear_carcass` | `bear_carcass.toml` | `art/actors/fauna/bear_brown.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.berry_bush` | `berry_bush.toml` | `art/actors/props/flora/berry_bush.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.blacksmith` | `blacksmith.toml` | `art/actors/structures/hellenes/blacksmith.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.blacksmith_age2` | `blacksmith_age2.toml` | `art/actors/structures/gauls/blacksmith.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.blacksmith_age3` | `blacksmith_age3.toml` | `art/actors/structures/achaemenids/blacksmith.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.blacksmith_age4` | `blacksmith_age4.toml` | `art/actors/structures/romans/blacksmith.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.boar` | `boar.toml` | `art/actors/fauna/boar.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.boar_carcass` | `boar_carcass.toml` | `art/actors/fauna/boar.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.castle` | `castle.toml` | `art/actors/structures/athenians/fortress.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.castle_age3` | `castle_age3.toml` | `art/actors/structures/iberians/fortress.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.castle_age4` | `castle_age4.toml` | `art/actors/structures/romans/fortress.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cattle` | `cattle.toml` | `art/actors/fauna/zebu_wild.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cattle_carcass` | `cattle_carcass.toml` | `art/actors/fauna/zebu_wild.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer` | `cavalry_archer.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman` | `crossbowman.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.deer` | `deer.toml` | `art/actors/fauna/deer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.deer_carcass` | `deer_carcass.toml` | `art/actors/fauna/deer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.dock_age2` | `dock_age2.toml` | `art/actors/structures/celts/dock.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.dock_age3` | `dock_age3.toml` | `art/actors/structures/achaemenids/dock.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.dock_age4` | `dock_age4.toml` | `art/actors/structures/romans/dock.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.dragon` | `dragon.toml` | `art/actors/fauna/dragon.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman` | `elite_swordsman.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.farm` | `farm.toml` | `art/actors/structures/plot_field_medit.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.field_age2` | `field_age2.toml` | `art/actors/structures/plot_field_temp.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.field_age3` | `field_age3.toml` | `art/actors/structures/plot_field_temp.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.field_age4` | `field_age4.toml` | `art/actors/structures/plot_field_temp.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fish` | `fish.toml` | `art/actors/fauna/tuna.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship` | `fishing_ship.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_3x3` | `foundation_3x3.toml` | `art/actors/structures/fndn_3x3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_3x3_tower` | `foundation_3x3_tower.toml` | `art/actors/structures/fndn_3x3_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_3x3_wall` | `foundation_3x3_wall.toml` | `art/actors/structures/fndn_3x3_wall.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_4x4` | `foundation_4x4.toml` | `art/actors/structures/fndn_4x4.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_5x4` | `foundation_5x4.toml` | `art/actors/structures/fndn_5x4.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_5x5` | `foundation_5x5.toml` | `art/actors/structures/fndn_5x5.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_6x3_wall` | `foundation_6x3_wall.toml` | `art/actors/structures/fndn_6x3_wall.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_6x6` | `foundation_6x6.toml` | `art/actors/structures/fndn_6x6.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_7x15_hele` | `foundation_7x15_hele.toml` | `art/actors/structures/fndn_7x15_hele.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_7x7` | `foundation_7x7.toml` | `art/actors/structures/fndn_7x7.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_8x8` | `foundation_8x8.toml` | `art/actors/structures/fndn_8x8.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.foundation_9x3_wall` | `foundation_9x3_wall.toml` | `art/actors/structures/fndn_9x3_wall.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon` | `galleon.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley` | `galley.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.gold_mine` | `gold_mine.toml` | `art/actors/geology/metal_aegean_round.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.gold_mine_large` | `gold_mine_large.toml` | `art/actors/geology/metal_aegean_square.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.gold_mine_small` | `gold_mine_small.toml` | `art/actors/geology/metal_aegean_small.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.guard_tower_age3` | `guard_tower_age3.toml` | `art/actors/structures/achaemenids/wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.guard_tower_age4` | `guard_tower_age4.toml` | `art/actors/structures/romans/wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.house` | `house.toml` | `art/actors/structures/britons/house.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.house_age2` | `house_age2.toml` | `art/actors/structures/gauls/house.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.house_age3` | `house_age3.toml` | `art/actors/structures/achaemenids/house.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.house_age4` | `house_age4.toml` | `art/actors/structures/romans/house.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight` | `knight.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.lumber_camp` | `lumber_camp.toml` | `art/actors/structures/britons/kennel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.lumber_camp_age2` | `lumber_camp_age2.toml` | `art/actors/structures/celts/longhouse.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.lumber_camp_age3` | `lumber_camp_age3.toml` | `art/actors/structures/iberians/corral.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.lumber_camp_age4` | `lumber_camp_age4.toml` | `art/actors/structures/romans/corral.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.market` | `market.toml` | `art/actors/structures/hellenes/market.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.market_age2` | `market_age2.toml` | `art/actors/structures/gauls/market.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.market_age3` | `market_age3.toml` | `art/actors/structures/mauryas/market.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.market_age4` | `market_age4.toml` | `art/actors/structures/romans/market.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia` | `militia.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mill` | `mill.toml` | `art/actors/structures/britons/special.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mill_age2` | `mill_age2.toml` | `art/actors/structures/celts/special.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mill_age3` | `mill_age3.toml` | `art/actors/structures/achaemenids/storehouse.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mill_age4` | `mill_age4.toml` | `art/actors/structures/romans/farmstead.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mining_camp` | `mining_camp.toml` | `art/actors/structures/britons/plot_corral.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mining_camp_age2` | `mining_camp_age2.toml` | `art/actors/structures/celts/plot_corral.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mining_camp_age3` | `mining_camp_age3.toml` | `art/actors/structures/iberians/storehouse.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.mining_camp_age4` | `mining_camp_age4.toml` | `art/actors/structures/romans/storehouse.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monastery_age3` | `monastery_age3.toml` | `art/actors/structures/achaemenids/temple.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monastery_age4` | `monastery_age4.toml` | `art/actors/structures/romans/temple.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk` | `monk.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager` | `onager.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager_packed` | `onager_packed.toml` | `art/actors/units/romans/siege_onager_packed.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.projectile_arrow` | `projectile_arrow.toml` | `art/actors/props/units/weapons/arrow_front.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.projectile_bolt` | `projectile_bolt.toml` | `art/actors/props/units/weapons/bolt.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.projectile_stone` | `projectile_stone.toml` | `art/actors/props/units/siege_artillery/stone_projectile_large.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_food_big` | `prop_food_big.toml` | `art/actors/props/special/eyecandy/treasure_achaemenid_food_big.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_food_small` | `prop_food_small.toml` | `art/actors/props/special/eyecandy/treasure_achaemenid_food_small.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_nest_bush` | `prop_nest_bush.toml` | `art/actors/flora/trees/temperate_bush_biome.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_shrine_celtic` | `prop_shrine_celtic.toml` | `art/actors/structures/celts/small_stone_monument.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_standing_stone` | `prop_standing_stone.toml` | `art/actors/props/special/eyecandy/standing_stones.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_stone_pile_granite` | `prop_stone_pile_granite.toml` | `art/actors/props/special/eyecandy/stone_pile.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.prop_wood_lumber` | `prop_wood_lumber.toml` | `art/actors/props/special/eyecandy/wood_pile.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_3x3` | `rubble_3x3.toml` | `art/actors/structures/destruct_stone_3x3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_4x2` | `rubble_4x2.toml` | `art/actors/structures/destruct_stone_4x2.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_4x4` | `rubble_4x4.toml` | `art/actors/structures/destruct_stone_4x4.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_5x5` | `rubble_5x5.toml` | `art/actors/structures/destruct_stone_5x5.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_6x6` | `rubble_6x6.toml` | `art/actors/structures/destruct_stone_6x6.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_town_center` | `rubble_town_center.toml` | `art/actors/structures/destruct_hele_cc.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_wall_long` | `rubble_wall_long.toml` | `art/actors/structures/destruct_stone_wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_wall_medium` | `rubble_wall_medium.toml` | `art/actors/structures/destruct_stone_wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_wall_short` | `rubble_wall_short.toml` | `art/actors/structures/destruct_stone_wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.rubble_wall_tower` | `rubble_wall_tower.toml` | `art/actors/structures/destruct_stone_wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry` | `scout_cavalry.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sheep` | `sheep.toml` | `art/actors/fauna/sheep3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sheep_carcass` | `sheep_carcass.toml` | `art/actors/fauna/sheep3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram` | `siege_ram.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_workshop_age3` | `siege_workshop_age3.toml` | `art/actors/structures/achaemenids/workshop.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_workshop_age4` | `siege_workshop_age4.toml` | `art/actors/structures/romans/workshop.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman` | `spearman.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stable` | `stable.toml` | `art/actors/structures/hellenes/stable.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stable_age2` | `stable_age2.toml` | `art/actors/structures/gauls/stable.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stable_age3` | `stable_age3.toml` | `art/actors/structures/achaemenids/stable.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stable_age4` | `stable_age4.toml` | `art/actors/structures/romans/stable.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stone_mine` | `stone_mine.toml` | `art/actors/geology/stonemine_granite.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.stone_mine_large` | `stone_mine_large.toml` | `art/actors/geology/stonemine_temperate_quarry_01.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry` | `sword_cavalry.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman` | `swordsman.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cliff` | `terrain_cliff.toml` | `art/actors/geology/stone_mediterranean_greek_furrowed_cliff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.dirt` | `terrain_dirt.toml` | `dirt/dirta.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.forest_floor` | `terrain_forestfloor.toml` | `art/terrains/forestfloor/forestfloor_pine.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.grass` | `terrain_grass.toml` | `grass/grass1.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.rock` | `terrain_rock.toml` | `art/terrains/biome-mediterranean/medit_rocks.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.sand` | `terrain_sand.toml` | `sand/sand.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.water_deep` | `terrain_water_deep.toml` | `art/terrains/water/water_3.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `terrain.water_shallow` | `terrain_water_shallow.toml` | `art/terrains/water/water_1.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tower` | `tower.toml` | `art/actors/structures/athenians/wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.town_center` | `town_center.toml` | `art/actors/structures/britons/civic_centre.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.town_center_age2` | `town_center_age2.toml` | `art/actors/structures/gauls/civic_centre.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.town_center_age3` | `town_center_age3.toml` | `art/actors/structures/iberians/civic_center.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.town_center_age4` | `town_center_age4.toml` | `art/actors/structures/romans/civic_centre.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart` | `trade_cart.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship` | `transport_ship.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet` | `trebuchet_deployed.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet_packed` | `trebuchet_packed.toml` | `art/actors/units/han/siege_mangonel_pivot_packed.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_bamboo` | `tree_bamboo.toml` | `art/actors/flora/trees/bamboo.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_banyan` | `tree_banyan.toml` | `art/actors/flora/trees/banyan.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_beech` | `tree_beech.toml` | `art/actors/flora/trees/european_beech.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_birch` | `tree_birch.toml` | `art/actors/flora/trees/euro_birch_tree.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_cherry` | `tree_cherry.toml` | `art/actors/flora/trees/cherry_small.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_cypress` | `tree_cypress.toml` | `art/actors/flora/trees/cypress_test.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_cypress_tall` | `tree_cypress_tall.toml` | `art/actors/flora/trees/mediterranean_cypress_tall.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_dead` | `tree_dead.toml` | `art/actors/flora/trees/dead_a_2.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_dead_branchy` | `tree_dead_branchy.toml` | `art/actors/flora/trees/dead_a_1.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_elm` | `tree_elm.toml` | `art/actors/flora/trees/elm.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_elm_dead` | `tree_elm_dead.toml` | `art/actors/flora/trees/elm_dead.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_fir` | `tree_fir.toml` | `art/actors/flora/trees/fir_tree.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree` | `tree_oak.toml` | `art/actors/flora/trees/oak.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_oak_dead` | `tree_oak_dead.toml` | `art/actors/flora/trees/oak_dead.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_oak_new` | `tree_oak_new.toml` | `art/actors/flora/trees/oak_new.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_palm_cretan_patch` | `tree_palm_cretan_patch.toml` | `art/actors/flora/trees/palm_cretan_date_patch.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_palm_date` | `tree_palm_date.toml` | `art/actors/flora/trees/palm_date.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_palm_fan` | `tree_palm_fan.toml` | `art/actors/flora/trees/palm_medit_fan_palm.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_palm_tropical` | `tree_palm_tropical.toml` | `art/actors/flora/trees/palm_tropical.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_palm_tropical_tall` | `tree_palm_tropical_tall.toml` | `art/actors/flora/trees/palm_tropical_tall.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_snow_pine` | `tree_snow_pine.toml` | `art/actors/flora/trees/snow_pine2.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_teak` | `tree_teak.toml` | `art/actors/flora/trees/teak.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.tree_toona` | `tree_toona.toml` | `art/actors/flora/trees/tree_tropic.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.university_age3` | `university_age3.toml` | `art/actors/structures/iberians/temple.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.university_age4` | `university_age4.toml` | `art/actors/structures/macedonians/temple.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager` | `villager.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_gate` | `wall_gate.toml` | `art/actors/structures/athenians/wall_gate_door.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_long` | `wall_long.toml` | `art/actors/structures/athenians/wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_medium` | `wall_medium.toml` | `art/actors/structures/athenians/wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_reinforced_gate_age4` | `wall_reinforced_gate_age4.toml` | `art/actors/structures/romans/wall_gate.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_reinforced_long_age4` | `wall_reinforced_long_age4.toml` | `art/actors/structures/romans/wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_reinforced_medium_age4` | `wall_reinforced_medium_age4.toml` | `art/actors/structures/romans/wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_reinforced_short_age4` | `wall_reinforced_short_age4.toml` | `art/actors/structures/romans/wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_short` | `wall_short.toml` | `art/actors/structures/athenians/wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_stone_gate_age3` | `wall_stone_gate_age3.toml` | `art/actors/structures/achaemenids/wall_gate.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_stone_long_age3` | `wall_stone_long_age3.toml` | `art/actors/structures/achaemenids/wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_stone_medium_age3` | `wall_stone_medium_age3.toml` | `art/actors/structures/achaemenids/wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_stone_short_age3` | `wall_stone_short_age3.toml` | `art/actors/structures/achaemenids/wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_gate_age2` | `wall_wood_gate_age2.toml` | `art/actors/structures/germans/wooden_wall_gate.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_gate_age3` | `wall_wood_gate_age3.toml` | `art/actors/structures/romans/siege_wall_gate.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_long_age2` | `wall_wood_long_age2.toml` | `art/actors/structures/germans/wooden_wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_long_age3` | `wall_wood_long_age3.toml` | `art/actors/structures/romans/siege_wall_long.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_medium_age2` | `wall_wood_medium_age2.toml` | `art/actors/structures/germans/wooden_wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_medium_age3` | `wall_wood_medium_age3.toml` | `art/actors/structures/romans/siege_wall_medium.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_short_age2` | `wall_wood_short_age2.toml` | `art/actors/structures/germans/wooden_wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_short_age3` | `wall_wood_short_age3.toml` | `art/actors/structures/romans/siege_wall_short.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_tower_age2` | `wall_wood_tower_age2.toml` | `art/actors/structures/germans/wooden_wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wall_wood_tower_age3` | `wall_wood_tower_age3.toml` | `art/actors/structures/romans/siege_wall_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.watch_tower_age2` | `watch_tower_age2.toml` | `art/actors/structures/gauls/wooden_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.watch_tower_age3` | `watch_tower_age3.toml` | `art/actors/structures/achaemenids/wooden_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.watch_tower_age4` | `watch_tower_age4.toml` | `art/actors/structures/romans/scout_tower.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag` | `waypoint_flag.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wolf` | `wolf.toml` | `art/actors/fauna/wolf.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wolf_carcass` | `wolf_carcass.toml` | `art/actors/fauna/wolf.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.wonder` | `wonder.toml` | `art/actors/structures/hellenes/temple_epic.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.blue` | `archer__blue.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.cyan` | `archer__cyan.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.green` | `archer__green.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.orange` | `archer__orange.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.red` | `archer__red.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.violet` | `archer__violet.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.white` | `archer__white.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.archer.yellow` | `archer__yellow.toml` | `art/actors/units/carthaginians/infantry_archer_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.blue` | `cavalry_archer__blue.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.cyan` | `cavalry_archer__cyan.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.green` | `cavalry_archer__green.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.orange` | `cavalry_archer__orange.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.red` | `cavalry_archer__red.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.violet` | `cavalry_archer__violet.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.white` | `cavalry_archer__white.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.cavalry_archer.yellow` | `cavalry_archer__yellow.toml` | `art/actors/units/achaemenids/cavalry_archer_b_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.blue` | `crossbowman__blue.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.cyan` | `crossbowman__cyan.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.green` | `crossbowman__green.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.orange` | `crossbowman__orange.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.red` | `crossbowman__red.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.violet` | `crossbowman__violet.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.white` | `crossbowman__white.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.crossbowman.yellow` | `crossbowman__yellow.toml` | `art/actors/units/han/infantry_crossbowman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.blue` | `elite_swordsman__blue.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.cyan` | `elite_swordsman__cyan.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.green` | `elite_swordsman__green.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.orange` | `elite_swordsman__orange.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.red` | `elite_swordsman__red.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.violet` | `elite_swordsman__violet.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.white` | `elite_swordsman__white.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.elite_swordsman.yellow` | `elite_swordsman__yellow.toml` | `art/actors/units/athenians/infantry_swordsman_c.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.blue` | `fishing_ship__blue.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.cyan` | `fishing_ship__cyan.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.green` | `fishing_ship__green.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.orange` | `fishing_ship__orange.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.red` | `fishing_ship__red.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.violet` | `fishing_ship__violet.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.white` | `fishing_ship__white.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.fishing_ship.yellow` | `fishing_ship__yellow.toml` | `art/actors/structures/celts/fishing_boat.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.blue` | `galleon__blue.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.cyan` | `galleon__cyan.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.green` | `galleon__green.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.orange` | `galleon__orange.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.red` | `galleon__red.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.violet` | `galleon__violet.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.white` | `galleon__white.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galleon.yellow` | `galleon__yellow.toml` | `art/actors/structures/ptolemies/quinquereme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.blue` | `galley__blue.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.cyan` | `galley__cyan.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.green` | `galley__green.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.orange` | `galley__orange.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.red` | `galley__red.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.violet` | `galley__violet.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.white` | `galley__white.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.galley.yellow` | `galley__yellow.toml` | `art/actors/structures/athenians/trireme.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.blue` | `knight__blue.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.cyan` | `knight__cyan.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.green` | `knight__green.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.orange` | `knight__orange.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.red` | `knight__red.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.violet` | `knight__violet.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.white` | `knight__white.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.knight.yellow` | `knight__yellow.toml` | `art/actors/units/germans/cavalry_swordsman_c_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.blue` | `militia__blue.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.cyan` | `militia__cyan.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.green` | `militia__green.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.orange` | `militia__orange.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.red` | `militia__red.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.violet` | `militia__violet.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.white` | `militia__white.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.militia.yellow` | `militia__yellow.toml` | `art/actors/units/britons/infantry_slinger_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.blue` | `monk__blue.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.cyan` | `monk__cyan.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.green` | `monk__green.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.orange` | `monk__orange.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.red` | `monk__red.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.violet` | `monk__violet.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.white` | `monk__white.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.monk.yellow` | `monk__yellow.toml` | `art/actors/units/athenians/healer.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.blue` | `onager__blue.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.cyan` | `onager__cyan.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.green` | `onager__green.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.orange` | `onager__orange.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.red` | `onager__red.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.violet` | `onager__violet.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.white` | `onager__white.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.onager.yellow` | `onager__yellow.toml` | `art/actors/units/romans/siege_onager_pivot.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.blue` | `scout_cavalry__blue.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.cyan` | `scout_cavalry__cyan.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.green` | `scout_cavalry__green.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.orange` | `scout_cavalry__orange.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.red` | `scout_cavalry__red.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.violet` | `scout_cavalry__violet.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.white` | `scout_cavalry__white.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.scout_cavalry.yellow` | `scout_cavalry__yellow.toml` | `art/actors/units/mauryas/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.blue` | `siege_ram__blue.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.cyan` | `siege_ram__cyan.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.green` | `siege_ram__green.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.orange` | `siege_ram__orange.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.red` | `siege_ram__red.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.violet` | `siege_ram__violet.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.white` | `siege_ram__white.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.siege_ram.yellow` | `siege_ram__yellow.toml` | `art/actors/structures/iberians/siege_ram.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.blue` | `spearman__blue.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.cyan` | `spearman__cyan.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.green` | `spearman__green.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.orange` | `spearman__orange.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.red` | `spearman__red.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.violet` | `spearman__violet.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.white` | `spearman__white.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.spearman.yellow` | `spearman__yellow.toml` | `art/actors/units/gauls/infantry_spearman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.blue` | `sword_cavalry__blue.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.cyan` | `sword_cavalry__cyan.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.green` | `sword_cavalry__green.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.orange` | `sword_cavalry__orange.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.red` | `sword_cavalry__red.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.violet` | `sword_cavalry__violet.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.white` | `sword_cavalry__white.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.sword_cavalry.yellow` | `sword_cavalry__yellow.toml` | `art/actors/units/gauls/cavalry_swordsman_a_m.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.blue` | `swordsman__blue.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.cyan` | `swordsman__cyan.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.green` | `swordsman__green.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.orange` | `swordsman__orange.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.red` | `swordsman__red.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.violet` | `swordsman__violet.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.white` | `swordsman__white.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.swordsman.yellow` | `swordsman__yellow.toml` | `art/actors/units/gauls/infantry_swordsman_a.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.blue` | `trade_cart__blue.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.cyan` | `trade_cart__cyan.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.green` | `trade_cart__green.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.orange` | `trade_cart__orange.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.red` | `trade_cart__red.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.violet` | `trade_cart__violet.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.white` | `trade_cart__white.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trade_cart.yellow` | `trade_cart__yellow.toml` | `art/actors/units/athenians/trader.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.blue` | `transport_ship__blue.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.cyan` | `transport_ship__cyan.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.green` | `transport_ship__green.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.orange` | `transport_ship__orange.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.red` | `transport_ship__red.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.violet` | `transport_ship__violet.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.white` | `transport_ship__white.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.transport_ship.yellow` | `transport_ship__yellow.toml` | `art/actors/structures/celts/skiff.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.blue` | `trebuchet_deployed__blue.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.cyan` | `trebuchet_deployed__cyan.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.green` | `trebuchet_deployed__green.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.orange` | `trebuchet_deployed__orange.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.red` | `trebuchet_deployed__red.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.violet` | `trebuchet_deployed__violet.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.white` | `trebuchet_deployed__white.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.trebuchet.yellow` | `trebuchet_deployed__yellow.toml` | `art/actors/units/han/siege_mangonel.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.blue` | `villager__blue.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.cyan` | `villager__cyan.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.green` | `villager__green.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.orange` | `villager__orange.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.red` | `villager__red.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.violet` | `villager__violet.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.white` | `villager__white.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.villager.yellow` | `villager__yellow.toml` | `art/actors/units/celts/female_citizen.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.blue` | `waypoint_flag__blue.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.cyan` | `waypoint_flag__cyan.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.green` | `waypoint_flag__green.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.orange` | `waypoint_flag__orange.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.red` | `waypoint_flag__red.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.violet` | `waypoint_flag__violet.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.white` | `waypoint_flag__white.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| `vis.waypoint_flag.yellow` | `waypoint_flag__yellow.toml` | `art/actors/props/special/common/waypoint_flag_0ad.xml` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |

<!-- END GENERATED: recipes -->

---

## Audio pack — 0 A.D. sound groups

**Everything under `game/assets/audio/` is 0 A.D. audio, used unmodified.** The
attribution above applies to it in full and is the same obligation: 0 A.D.'s
`audio/LICENSE.txt` carries the same **CC-BY-SA 3.0** terms as `art/LICENSE.txt`,
naming **Wildfire Games** as author with the author link
http://www.wildfiregames.com/ and the licence deed
http://creativecommons.org/licenses/by-sa/3.0/.

**Modification made: none.** Unlike the atlases, nothing is rendered, re-encoded
or re-packed — the `.ogg` files are byte-identical to 0 A.D.'s, verified by
sha256 against the git-LFS oid at fetch time (`tools/stage_audio.py`). What this
project adds is the *selection*: which sound group answers which game event.

**Declared by population, not by filename**, exactly as the atlases above are.
`game/assets/audio/` is gitignored build output; the durable record is
[`game/data/audio.json`](../data/audio.json), which is committed and carries a
`source_group` per sound id naming the 0 A.D. group it came from — and the
mapping's *reasoning* is in `tools/stage_audio.py`. `licence_audit.py` checks
nothing sits in the staged directory that no sound id accounts for, which is the
same coverage check `staged_atlas_ids()` performs for the bakes.

| What | Source | Licence |
|---|---|---|
| Sound effects — `audio/{actor,attack,resource,interface,ambient}` | 0 A.D. `binaries/data/mods/public/audio/` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| Unit voices — `audio/voice/latin` only | 0 A.D. `binaries/data/mods/public/audio/voice/latin/` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| Music — 8 of the 62 tracks | 0 A.D. `binaries/data/mods/public/audio/music/` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |
| UI button click | 0 A.D. `binaries/data/mods/mod/audio/interface/ui/` | [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) |

0 A.D.'s music is credited per-composer in its own `audio/music/` metadata; the
eight tracks taken are named in `MUSIC` in `tools/stage_audio.py`, and
[`../../CREDITS.md`](../../CREDITS.md) carries the project-level credit.

---

## Shipped inside the APK

Assets committed under `game/assets/`. These are **not** from 0 A.D. and each needs its
own provenance.

| File | What | Origin | Licence |
|---|---|---|---|
| `icons/icon_16x16.png`, `icons/icon_32x32.png`, `icons/icon_48x48.png`, `icons/icon_64x64.png`, `icons/icon_128x128.png`, `icons/icon_256x256.png`, `icons/icon_1024x1024.png`, `icons/icon.ico` | Application launcher icon, all sizes | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/boot_splash.png` | The title card (phase 1.3), and the repo-root `Splash.jpg` the README banner uses. Both are `assets/UI_Gen/splash_screen_c.jpg`, one of three candidates the owner generated on 2026-08-30; the game's copy is PNG so the art takes no second JPEG round trip. Replaced `Splash_h.jpg` and its `boot_splash.png`, retired the same day | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/help/age_up.jpg`, `ui/help/control_groups.jpg`, `ui/help/drag_select.jpg`, `ui/help/minimap_and_panels.jpg`, `ui/help/move_and_gather.jpg`, `ui/help/zoom_and_pan.jpg` | The six pages of HOW TO PLAY (phase 1.8), staged from `assets/HELP_Gen/` on 2026-08-30. **A hybrid, and the only one in this table:** each is a real screen capture of this game — 0 A.D.-derived sprites and all — with touch instructions painted over it by the owner in Gemini. JPEG rather than PNG because they are photographs; the largest is 1476×720 | Captures of this project's own screen, annotated by the project owner using **Google Gemini** (paid account) | The annotation is a project asset (see the note below); what is UNDER it is this game's rendering of 0 A.D. art and stays CC-BY-SA 3.0, already attributed above |
| `ui/icons/res_food.png`, `ui/icons/res_gold.png`, `ui/icons/res_idle.png`, `ui/icons/res_stone.png`, `ui/icons/res_villagers.png`, `ui/icons/res_wood.png` | The four resource counters, the population row and the idle-villager glyph, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/act_attack.png`, `ui/icons/act_build.png`, `ui/icons/act_destroy.png`, `ui/icons/act_enter.png`, `ui/icons/act_exit.png`, `ui/icons/act_garrison.png`, `ui/icons/act_harvest.png`, `ui/icons/act_leave.png`, `ui/icons/act_move.png`, `ui/icons/act_pack.png`, `ui/icons/act_repair.png`, `ui/icons/act_research.png`, `ui/icons/act_stance.png`, `ui/icons/act_stop.png`, `ui/icons/act_unpack.png`, `ui/icons/act_upgrade.png` | Action-panel verbs — move, stop, attack, build, harvest, repair, destroy, garrison, enter/exit/leave, upgrade, research, stance, pack/unpack, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/hud_alert.png`, `ui/icons/hud_chat.png`, `ui/icons/hud_menu.png`, `ui/icons/hud_pause.png`, `ui/icons/hud_score.png`, `ui/icons/hud_settings.png`, `ui/icons/hud_techtree.png`, `ui/icons/hud_trade.png`, `ui/icons/hud_volume.png` | The four buttons around the minimap, plus score, menu, pause, alert and volume, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/tech_ballistics.png`, `ui/icons/tech_blast_furnace.png`, `ui/icons/tech_bodkin_arrow.png`, `ui/icons/tech_bow_saw.png`, `ui/icons/tech_bracer.png`, `ui/icons/tech_chain_mail.png`, `ui/icons/tech_chemistry.png`, `ui/icons/tech_crop_rotation.png`, `ui/icons/tech_double_bit_axe.png`, `ui/icons/tech_fervour.png`, `ui/icons/tech_fletching.png`, `ui/icons/tech_forging.png`, `ui/icons/tech_generic.png`, `ui/icons/tech_gold_mining.png`, `ui/icons/tech_gold_shaft_mining.png`, `ui/icons/tech_hand_cart.png`, `ui/icons/tech_heavy_plough.png`, `ui/icons/tech_horse_collar.png`, `ui/icons/tech_iron_casting.png`, `ui/icons/tech_leather_armour.png`, `ui/icons/tech_padded_armour.png`, `ui/icons/tech_plate_mail.png`, `ui/icons/tech_ring_armour.png`, `ui/icons/tech_sanctity.png`, `ui/icons/tech_scale_mail.png`, `ui/icons/tech_stone_mining.png`, `ui/icons/tech_stone_shaft_mining.png`, `ui/icons/tech_wheelbarrow.png` | One per technology in `data/techs.json`, plus `tech_generic.png` as the fallback a 28th would draw, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/form_box.png`, `ui/icons/form_grid.png`, `ui/icons/form_line.png`, `ui/icons/form_vee.png` | The four formations, drawn as the shapes themselves rather than as symbols for them, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/stance_aggressive.png`, `ui/icons/stance_defensive.png`, `ui/icons/stance_passive.png`, `ui/icons/stance_stand_ground.png` | The four stances, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/abil_fire_breath.png`, `ui/icons/abil_heal.png` | The two special abilities, keyed by `UnitDef.ability_id`, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/age_1.png`, `ui/icons/age_2.png`, `ui/icons/age_3.png`, `ui/icons/age_4.png`, `ui/icons/age_advance.png` | Age markers I–IV and the advance chevron, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/mic_muted.png`, `ui/icons/mic_on.png` | Voice chat. **Drawn for a feature that does not exist** — see the note below, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/voice_muted.png`, `ui/icons/voice_on.png` | Voice chat. Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/chat_clear.png`, `ui/icons/chat_send.png` | Text chat send/clear (8.6). The buttons exist and are deliberately disabled, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/net_filter.png`, `ui/icons/net_host.png`, `ui/icons/net_join.png`, `ui/icons/net_refresh.png` | Server browser (12.1b). Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/lobby_faction.png`, `ui/icons/lobby_gametype.png`, `ui/icons/lobby_mapsize.png`, `ui/icons/lobby_team.png`, `ui/icons/lobby_victory.png` | Lobby controls. Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/file_delete.png`, `ui/icons/file_load.png`, `ui/icons/file_save.png` | Save/load/delete (12.4). Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/replay_pause.png`, `ui/icons/replay_play.png`, `ui/icons/replay_step.png` | Replay transport (12.4). Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/pack_download.png`, `ui/icons/pack_retry.png` | Asset-pack download and retry (0.3). Not wired, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/victory_regicide.png`, `ui/icons/victory_trophy.png` | Victory modes (11.2), declared and inert, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/transport_load.png`, `ui/icons/transport_unload.png` | Naval load/unload. No UI for it yet, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/icons/ui_close.png`, `ui/icons/ui_confirm.png` | Close and confirm, 100×100 RGBA | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/chrome/arrow_down.png`, `ui/chrome/arrow_left.png`, `ui/chrome/arrow_right.png`, `ui/chrome/arrow_up.png`, `ui/chrome/badge_round.png`, `ui/chrome/banner_age.png`, `ui/chrome/banner_alert.png`, `ui/chrome/bar_fill_health.png`, `ui/chrome/bar_fill_progress.png`, `ui/chrome/bar_groove.png`, `ui/chrome/button_disabled.png`, `ui/chrome/button_normal.png`, `ui/chrome/button_pressed.png`, `ui/chrome/checkbox_off.png`, `ui/chrome/checkbox_on.png`, `ui/chrome/field_input.png`, `ui/chrome/frame_minimap.png`, `ui/chrome/group_slot_ring.png`, `ui/chrome/panel_hud.png`, `ui/chrome/panel_ornate.png`, `ui/chrome/panel_ornate_small.png`, `ui/chrome/portrait_frame.png`, `ui/chrome/radio_off.png`, `ui/chrome/tab_plate_small.png`, `ui/chrome/radio_on.png`, `ui/chrome/tab_plate.png`, `ui/chrome/tile_frame.png`, `ui/chrome/tile_frame_disabled.png`, `ui/chrome/tile_frame_selected.png` | Panels, frames, bars, buttons and widgets — the whole UI chrome set, replacing the Kibyra pack on 2026-08-30. **Derived**, not copied: `tools/prepare_ui_chrome.py` rewrites `assets/UI_Gen/sliced/chrome/` into this directory at the size that makes each painted border draw at the thickness its widget wants | **AI-generated** by the project owner using **Google Gemini** (paid account) | Project asset — see the note below |
| `ui/fonts/NewRocker-Regular.ttf`, `ui/fonts/OFL-NewRocker.txt` | The body typeface, on every label in the game via `gui/theme/custom_font`. Chosen on its DIGITS — see `src/view/ui_font.gd` | **New Rocker** by Vernon Adams / Cyreal | [SIL Open Font License 1.1](https://openfontlicense.org/) — redistributable; the licence text ships beside the font, which the OFL requires |
| `ui/fonts/CinzelDecorative-Regular.ttf`, `ui/fonts/CinzelDecorative-Bold.ttf`, `ui/fonts/CinzelDecorative-Black.ttf`, `ui/fonts/OFL-CinzelDecorative.txt` | The display typeface, for names rather than sentences (`UiFont.title`) | **Cinzel Decorative** by Natanael Gama | [SIL Open Font License 1.1](https://openfontlicense.org/) — redistributable; the licence text ships beside the fonts |

> ### On the AI-generated assets
>
> All of the above were generated by the project owner with Google Gemini on a paid
> account — the launcher icon, the boot splash and the HUD icon set. Recorded
> explicitly rather than left as "ours", because generated assets carry a different set of
> facts from drawn ones and the difference is invisible in the file itself.
>
> **Why this is fine to ship.** Google's generative-AI terms do not claim ownership of
> output; what the service produces for you is yours to use, including commercially. No
> third party's rights are being relied on here, so nothing needs crediting to anyone else
> and there is no copyleft to propagate. These are **not** 0 A.D. material and carry none
> of its CC-BY-SA obligations.
>
> **The one caveat worth writing down.** In several jurisdictions — the US most clearly —
> purely AI-generated images may attract no copyright at all, because copyright wants a
> human author. That does not stop us shipping them; it means they may not be *ours to
> restrict*, so treat them as effectively unprotectable rather than as MIT-licensed
> project code. Practically this only matters if someone else reuses the icon and we would
> want to object. If that ever matters, replace them with drawn originals.
>
> **If they are regenerated or replaced,** update this row in the same change. Note also
> that Gemini output carries Google's SynthID watermark, so these files are detectable as
> AI-generated regardless of what this file says.

---

## Not shipped, and why

Recording these matters as much as recording what does ship — the reason they are absent
is a licence constraint, and someone will otherwise "fix" it by committing them.

| What | Where | Why it is not committed |
|---|---|---|
| HUD icon source sheets | `assets/Icons/Icons_sheet_500x500.png`, `assets/Icons/MapIcons_500x100.png` (moved from repo-root `Icons/` 2026-08-08) | The sheets the ORIGINAL twenty 100×100 icons were cut from, plus `Icons/icons.txt` and `Icons/map_icons.txt` describing them. **Superseded 2026-08-30** — the icon set is now the 103 in `assets/UI_Gen/` and nothing is cut from these any more. Kept because they are still the provenance of the launcher icon |
| The [P8] UI masters | `assets/UI_Gen/` — fourteen 1024×1024 Gemini sheets, the two font archives, and `sliced/` | The sheets ARE committed (they are the project's own and the durable record of what the icons were cut from); `sliced/` is derived and gitignored — regenerate with `tools/slice_ui_sheets.py` then `tools/prepare_ui_chrome.py`. What ships is `game/assets/ui/`, and that is declared above |
| The HOW TO PLAY originals | `assets/HELP_Gen/` — six annotated captures the owner delivered on 2026-08-30 | **Untracked, and deliberately, because the shipped copies ARE the originals.** Unlike the [P8] sheets nothing is cut or derived from these: `game/assets/ui/help/` holds the same six files byte for byte, renamed to snake_case, and that copy is committed and declared above. Committing both would be 2.3 MB of duplicate. The mapping from delivered name to staged name is in `src/view/help_screen.gd`'s `PAGES` |
| Kibyra UI packs | `assets/UI_Sprites/` | **RETIRED 2026-08-30 and this row is now about nothing shipping FROM here rather than about a constraint.** Free for personal and commercial use, redistribution of the originals forbidden — which is why `game/assets/ui/` was gitignored for the whole life of the project until the art was replaced. Nothing in the game loads one; the directory is a local download and the whole of it is gitignored |
| 0 A.D. source art | `art_source/` (outside the repo) | ~11 GB shallow clone; a build input, never redistributed |
| Baked atlases | `art_work/out/` (outside the repo) | Build output. Reproducible from the committed recipes plus `isobake` |
| Gemini working-source drops | `assets/*.png`, `assets/*.jpg` (e.g. `MainMenu.png`, `Age_and_Upgrade_bar.png`) | Same convention as the HUD icon source sheets above: the project owner drops raw generated art at the `assets/` root; whatever is actually used gets cut/copied into `game/assets/ui/` and only that copy ships. Not recursive -- a real subfolder like `UI_Sprites/` has its own row |

---

## Adding an asset

Add it here **in the same change that introduces it**, per PLAN.md §13.1: credit only
what is actually used, and only use licences compatible with an open-source CC-BY-SA art
release. For a new baked atlas, fill in the recipe's `[attribution]` block and run
`--write`; the table above is generated from exactly that.
