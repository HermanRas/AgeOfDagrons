# Age Planning.

there is only 1 civilization, using the diffrint civ's found in 0 A.D, we will take the Civs that visualy look older to news and map them to tha ages we need for our game.

> **Decided 2026-08-14 — read the `### Units` sections as unit TYPES, not as actor paths.**
> Buildings carry the age progression, using the civ named on each line. **Units do not**: every
> unit is sourced from a Celtic actor (`britons/`, `gauls/`, `celts/`) in all four ages, so a
> player can recognise a unit type instantly and its silhouette never changes underneath them.
> The civ prefixes on the unit lines below therefore record *which kind of unit is wanted* — the
> Celtic actor that fills each slot is in PLAN.md §9.2, with paths verified against the checkout.
> Where the Celts have no equivalent, the closest Celtic match is used; siege engines are the one
> exception, since the Celts have none at all.

## Age1 - Dark Age:

### Building

Brit/house (House +5 Population)
Brit/Cicil_centre (TownCenter +10 Population)
Brit/Rotarymill (Farm\[Mill], Place to drop food, in age2 add field for farming)
Brit/Corral + x3 gaia/tresure/stone_pile_granite (Mining Camp)
Brit/kennel + x3 gaia/treasure/wood_lumber (Lumber Camp)

### Units

Brit/infantry_slinger_a (Militia:TownCentre, Spawn x0)
maur/Cavalry_swordman_a (Scout Cavalry:spawn not buildable)
Brit/support_civilian (Villager:TownCentre, Spawn x5)

## Age2 - Feudal Age:

### Building

Gaul/House (House +5 Population)
Gaul/Cicil_centre (TownCentre +10 Population)
Gual/Rotarymill (Farm\[Mill], Place to drop food, can add up to 2 field farming food +1 per field per tic)
Gual/Field (needs to be adjacent to a Farm)
Gual/Barracks (Build Solders)
Gual/Market (unlock allied trading, marker buy / sell)
Gual/Corral + x3 gaia/tresure/stone_pile_granite (Mining Camp)
Celt/longhouse + x3 gaia/treasure/wood_lumber (Lumber Camp)
Gual/Sentry_Tower (watch Tower-stone throwing)
Germ/wall_short,Germ/Wall_Medium,Germ/Wall_Long (wall Lumber)
Germ/Wall_Gate (Gate Lumber)
Gual/Range (Archery Range)
Gual/Stable (Stable)
Gual/Forge (Blacksmith)
Gual/Dock (Dock)

### Units

Gaul/infantry_slinger_a (Militia:TownCentre)
Gual/infantry_sworsman_gual_a (SwardMan:barracks)
maur/Cavalry_swordman_a (Scout Cavalry:stable)
Gaul/support_civilian (Villager:TownCentre)
cart/infantry_archer_a (Archers: Archery Range)
Gaul/infantry_spearman_a (Spearmen: Barracks)
Gaul/ship_fishing (Fishing Ship: Dock)
Gaul/ship_scout (Transport Ship: Dock)

## Age3 - Castle Age:

### Building

pers/House (House +5 Population)
iber/Cicil_centre (TownCentre +10 Population)
Pers/StoreHouse +  x2 gaia/tresure/food_persian_small, 1x gaia/tresure/food_persian_big (Farm\[Mill], Place to drop food, can add up to 4 field farming food +1 per field per tic)
iber/Field (needs to be adjacent to a Farm)
iber/Barracks (Build Solders)
Maur/Market (unlock allied trading, marker buy / sell)
iber/storehouse + x3 gaia/tresure/stone_pile_granite (Mining Camp)
iber/corral + x3 gaia/treasure/wood_lumber (Lumber Camp)
pers/Sentry_Tower (watch Tower-stone throwing)
Pers/wall_tower (Guard Tower - Archer arrow shooting)
brit/wall_short,brit/Wall_Medium,brit/Wall_Long (wall Lumber)
brit/Wall_Gate (Gate Lumber)
pers/wall_short,pers/Wall_Medium,pers/Wall_Long (wall Stone)
pers/Wall_Gate(Gate Stone)
iber/Range (Archery Range)
Pers/Stable (Stable)
Pers/Forge (Blacksmith)
Pers/Dock (Dock)
iber/fortress (Castle +40 Population)
Pers/temple (Monastery)
iber/temple (University)
pers/arsenal (Siege Workshop)
iber/Cicil_centre (Additional Town Centers)

### Units

Gaul/infantry_slinger_a (Militia:TownCentre)
cart/infantry_swordsman_gaul_a (SwardMan:barracks)
maur/Cavalry_swordman_a (Scout Cavalry:stable)
Gaul/Cavalry_swordman_a (sword Cavalry:stable)
pers/caalry_archer_b (Cavalry Archer: Stable)
Gaul/support_civilian (Villager:TownCentre)
pers/infantry_archer_b (Archers: Archery Range)
cart/infantry_spearman_ital_a (Spearmen: Barracks)
Gual/ship_fishing (Fishing Ship: Dock)
Gual/ship_scout (Transport Ship: Dock)
athen/support_healer_a (Monk: Monastery)
athen/ship/arrow (Galley WarShip: Dock)
germ/champion/cavalry (Knights: Castle)
han/infantry_crossbowman_a (Crossbowmen: Archery Range)
units/cart/siege_ram (Battering Ram: Siege Workshop)
units/cart/siege_ballista_packed,units/cart/siege_ballista_unpacked (Ballista: Siege Workshop)
rome/siege_onager_packed,rome/siege_onager_unpacked (Onager: Siege Workshop)

## Age4-Imperial Age:

### Building

rome/House (House +5 Population)
rome/Cicil_centre (TownCentre +10 Population)
rome/farmstead + x2 gaia/treasure/food_persian_small, 1x gaia/treasure/food_persian_big (Farm\[Mill], Place to drop food, can add up to 4 field farming food +1 per field per tic)
iber/Field (needs to be adjacent to a Farm)
rome/Barracks (Build Solders)
rome/Market (unlock allied trading, marker buy / sell)
rome/storehouse + x3 gaia/tresure/stone_pile_granite (Mining Camp)
rome/corral + x3 gaia/treasure/wood_lumber (Lumber Camp)
rome/defense_tower (watch Tower-stone throwing)
rome/wall_tower (Guard Tower - Archer arrow shooting)
brit/wall_short,brit/Wall_Medium,brit/Wall_Long (wall Lumber)
brit/Wall_Gate (Gate Lumber)
pers/wall_short,pers/Wall_Medium,pers/Wall_Long (wall Stone)
pers/Wall_Gate(Gate Stone)
rome/wall_short,rome/Wall_Medium,rome/Wall_Long (wall reinforced)
rome/Wall_Gate(Gate reinforced)
rome/Range (Archery Range)
rome/Stable (Stable)
rome/Forge (Blacksmith)
rome/Dock (Dock)
rome/fortress (Castle +40 Population)
rome/temple (Monastery)
mace/temple (University)
rome/arsenal (Siege Workshop)
rome/Cicil_centre (Additional Town Centers)
hellenic_epic_temple (for Wonder Victory)

### Units

Gaul/infantry_slinger_a (Militia:TownCentre)
rome/infantry_swordsman_a (SwardMan:barracks)
maur/Cavalry_swordman_a (Scout Cavalry:stable)
Gaul/Cavalry_swordman_a (sword Cavalry:stable)
pers/caalry_archer_b (Cavalry Archer: Stable)
Gaul/support_civilian (Villager:TownCentre)
pers/infantry_archer_b (Archers: Archery Range)
cart/infantry_spearman_ital_a (Spearmen: Barracks)
Gual/ship_fishing (Fishing Ship: Dock)
Gual/ship_scout (Transport Ship: Dock)
athen/support_healer_a (Monk: Monastery)
athen/ship/arrow (Galley WarShip: Dock)
germ/champion/cavalry (Knights: Castle)
han/infantry_crossbowman_a (Crossbowmen: Archery Range)
athen/champion_marine (Elite Swordman: Castle)
units/cart/siege_ram (Battering Ram: Siege Workshop)
units/cart/siege_ballista_packed,units/cart/siege_ballista_unpacked (Ballista: Siege Workshop)
ptol/ship_siege (Galleon WarShip: Dock)
rome/siege_onager_packed,rome/siege_onager_unpacked (Onager: Siege Workshop)
han/siege_mangonel_unpacked,han/siege_mangonel_packed (Trebuchet: Siege Workshop, Trebuchet: Castle)


## ORE

### Gold

gaia/ore/aegean_anatolian_small (1000)
gaia/ore/aegean_anatolian_01 (5000)
gaia/ore/aegean_anatolian_02 (10000)

### Stone

gaia/rock/temperate_small (1000)
gaia/rock/temperate_large_02 (7000)

### wood

gaia/tree/elm (500)
gaia/tree/oak (500)
gaia/tree/teak (500)
gaia/tree/toona (500)

### Food

gaia/gruit/berry_01
gaia/fauna_sheep (100)
gaia/fauna_deer (100)
gaia/fauna_wolf (30) attack
gaia/fauna_bear (300)
gaia/fauna_cattle_zebu (500)


## Dragon

## Full Grown

fauna/dragon (Dragon: Castle)

## baby

fauna/dragon (Dragon @ 10% size scale: Castle)

## Dragon Nest

gaia/tree/bush_badlands x22 cover centre grid + gaia/ruins/standing_stone x12 in a circle + structures/shrine_celtic
