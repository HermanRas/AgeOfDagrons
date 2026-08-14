## Phase 0.4: the entity half of GameDataRegistry -- units, buildings,
## resources, techs, ages (PLAN.md 9, 6.1).
##
## Two kinds of test here, and the second is the valuable one:
##
##   1. The *Def classes parse what the schema says they parse.
##   2. The SHIPPED data is internally consistent. Every ID that one file
##      references in another actually exists. Nothing else in the codebase will
##      notice a renamed ID until a villager silently fails to spawn at runtime,
##      so validate() coming back clean is a real gate, not a nicety -- albeit one
##      someone has to run, since there is no CI (PLAN.md 1.2).
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"

var reg: Node


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()


func after_each() -> void:
	reg.free()


# ── the shipped data ───────────────────────────────────────────────────────

func test_the_shipped_data_is_internally_consistent() -> void:
	# The whole point of validate(). Every visual, unit, building and resource
	# kind referenced across data/*.json must resolve.
	#
	# Asserted unconditionally rather than by looping over the warnings: a loop
	# over an empty array asserts nothing, and a test that asserts nothing is now
	# itself a failure (run_tests.gd). Reporting all warnings in one message also
	# beats failing on whichever happened to come first.
	assert_true(reg.load_warnings.is_empty(),
			"data/*.json is not consistent -- %s" % "; ".join(reg.load_warnings))


func test_the_mvp_roster_is_present() -> void:
	# PLAN.md 10: 1 unit, 2 buildings, 3 ACTIVE resource nodes (wood/gold/food).
	# res.deer stays defined but unused -- res.berry_bush replaced it as the MVP
	# food node (session decision: no hunt/kill/carcass state machine needed,
	# and vis.berry_bush is fully delivered where the deer carcass is not) -- so
	# resource_ids() itself now lists 4, one more than the active roster.
	assert_eq(reg.unit_ids(), [&"unit.villager"] as Array[StringName])
	assert_eq(reg.building_ids(),
			[&"building.house", &"building.town_center"] as Array[StringName])
	# NOT alphabetical -- Array[StringName].sort() orders by StringName identity,
	# not by string content, so this is whatever order these four happen to be
	# interned in, not something to read meaning into.
	assert_eq(reg.resource_ids(),
			[&"res.deer", &"res.berry_bush", &"res.gold_mine", &"res.tree"] as Array[StringName])


func test_entity_def_ids_translate_to_visual_ids() -> void:
	# Two separate namespaces -- unit.villager vs vis.villager -- and conflating
	# them fails SILENTLY: atlas_for() finds no entry for a def id and returns the
	# magenta unknown, so a whole match renders in placeholder colours with nothing
	# reported. That shipped briefly at 2.6; this is the regression guard.
	assert_eq(reg.visual_for(&"unit.villager"), &"vis.villager")
	assert_eq(reg.visual_for(&"res.tree"), &"vis.tree")
	assert_eq(reg.visual_for(&"res.gold_mine"), &"vis.gold_mine")
	assert_eq(reg.visual_for(&"building.house"), &"vis.house")
	assert_eq(reg.visual_for(&"nonsense.thing"), &"",
			"an unknown def resolves to nothing, not to a wrong visual")


func test_a_building_def_resolves_a_different_visual_per_phase() -> void:
	# Foundation / complete / rubble are three atlases, so the phase has to reach
	# the lookup or a destroyed building keeps drawing intact.
	assert_eq(reg.visual_for(&"building.town_center", 0), &"vis.foundation_8x8")
	assert_eq(reg.visual_for(&"building.town_center", 2), &"vis.town_center")
	assert_eq(reg.visual_for(&"building.town_center", 3), &"vis.rubble_town_center")
	assert_eq(reg.visual_for(&"building.town_center"), &"vis.town_center",
			"no phase given means the completed look")


func test_every_def_resolves_to_a_declared_visual() -> void:
	# Closes the loop: the def -> visual hop must land on something visuals.json
	# actually declares, for every entity in the game.
	for id in reg.unit_ids() + reg.resource_ids():
		var vis: StringName = reg.visual_for(id)
		assert_true(reg.visual_ids().has(vis), "%s -> '%s' is declared" % [id, vis])
	for id in reg.building_ids():
		for phase in [0, 1, 2, 3]:
			var vis: StringName = reg.visual_for(id, phase)
			assert_true(reg.visual_ids().has(vis),
					"%s phase %d -> '%s' is declared" % [id, phase, vis])


func test_an_unknown_id_returns_null_rather_than_a_stand_in() -> void:
	# The opposite convention to atlas_for(), on purpose: a missing sprite has a
	# sensible placeholder, a missing unit definition does not.
	assert_null(reg.unit(&"unit.nope"))
	assert_null(reg.building(&"building.nope"))
	assert_null(reg.resource_def(&"res.nope"))
	assert_null(reg.tech(&"tech.nope"))


# ── units ──────────────────────────────────────────────────────────────────

func test_the_villager_parses_every_field_the_schema_declares() -> void:
	var v: UnitDef = reg.unit(&"unit.villager")
	assert_not_null(v)
	assert_eq(v.name, "Villager")
	assert_eq(v.visual, &"vis.villager")
	assert_eq(v.hp, 30)
	assert_eq(v.speed, 200)
	assert_eq(v.pop_cost, 1)
	assert_eq(int(v.cost[&"food"]), 50)
	assert_eq(v.build_time_ticks, 250)
	assert_eq(v.attack_damage, 3)
	assert_eq(v.attack_type, &"melee")
	assert_eq(int(v.carry_cap[&"wood"]), 10)
	assert_true(v.trainable_at.has(&"building.town_center"))


func test_gather_rate_is_per_hundred_ticks_and_survives_the_conversion() -> void:
	# Authored x100 so the sim stays on integers (determinism, PLAN.md 7.1).
	# Rounding to an int per tick would collapse every rate under 100 to zero,
	# which would look like gathering being broken rather than like a data bug.
	var v: UnitDef = reg.unit(&"unit.villager")
	assert_eq(int(v.gather_rate[&"wood"]), 25)
	assert_almost_eq(v.gather_per_tick(&"wood"), 0.25, 0.0001)
	assert_almost_eq(v.gather_per_tick(&"nonexistent"), 0.0, 0.0001)


# ── buildings ──────────────────────────────────────────────────────────────

func test_footprints_are_the_max_across_all_four_age_skins() -> void:
	# Two corrections layered here, and this pins both so neither can quietly
	# revert. PLAN.md 9 first wrote [4, 4] for the town centre before the art was
	# measured; 0.4 corrected that to [8, 8] off the Athenian actor's 15.53 x
	# 15.00 m. But a building re-skins in place as its owner advances an age
	# (PLAN.md 13.2 item 10), so the footprint has to be the MAX across all four
	# age skins -- and 0 A.D.'s civs disagree: the Roman age-4 civic centre is
	# 37 x 37 world units against the Briton age-1 25 x 25. Hence [10, 10].
	assert_eq((reg.building(&"building.town_center") as BuildingDef).footprint,
			Vector2i(10, 10), "town centre is 10x10 -- the age-4 Roman skin, not the age-1 one")
	assert_eq((reg.building(&"building.house") as BuildingDef).footprint,
			Vector2i(4, 4), "house is 4x4, matching its 4x4 foundation")


func test_every_building_names_a_visual_for_all_three_phases() -> void:
	# SimBuilding.Phase is foundation / under-construction / complete / destroyed,
	# and the first two share art. A building missing one would render nothing at
	# that phase.
	for id in reg.building_ids():
		var b: BuildingDef = reg.building(id)
		assert_false(b.visual.is_empty(), "%s has a complete visual" % id)
		assert_false(b.visual_foundation.is_empty(), "%s has a foundation visual" % id)
		assert_false(b.visual_rubble.is_empty(), "%s has a rubble visual" % id)


func test_visual_for_phase_maps_construction_phases_onto_the_foundation() -> void:
	var b: BuildingDef = reg.building(&"building.town_center")
	assert_eq(b.visual_for_phase(0), &"vis.foundation_8x8", "FOUNDATION")
	assert_eq(b.visual_for_phase(1), &"vis.foundation_8x8", "UNDER_CONSTRUCTION shares it")
	assert_eq(b.visual_for_phase(2), &"vis.town_center", "COMPLETE")
	assert_eq(b.visual_for_phase(3), &"vis.rubble_town_center", "DESTROYED")


func test_the_town_centre_is_the_drop_off_and_trains_the_villager() -> void:
	var tc: BuildingDef = reg.building(&"building.town_center")
	for kind in [&"food", &"wood", &"gold", &"stone"] as Array[StringName]:
		assert_true(tc.accepts_drop_off(kind), "town centre accepts %s" % kind)
	assert_true(tc.trains.has(&"unit.villager"))
	assert_eq(tc.provides_pop, 10)

	var house: BuildingDef = reg.building(&"building.house")
	assert_false(house.accepts_drop_off(&"wood"), "a house is not a drop-off point")
	assert_eq(house.provides_pop, 5)


# ── resources ──────────────────────────────────────────────────────────────

func test_resource_nodes_carry_a_kind_and_per_size_amounts() -> void:
	var tree: ResourceDef = reg.resource_def(&"res.tree")
	assert_eq(tree.kind, &"wood")
	assert_eq(tree.size_class_count(), 3)
	assert_eq(tree.amount_for(0), 40)
	assert_eq(tree.amount_for(2), 175)

	var mine: ResourceDef = reg.resource_def(&"res.gold_mine")
	assert_eq(mine.kind, &"gold")
	assert_eq(mine.gather_slots, 4)


func test_an_out_of_range_size_class_clamps_rather_than_crashing() -> void:
	# A map generator asking for a size a resource does not define should get the
	# nearest one, not take the sim down.
	var tree: ResourceDef = reg.resource_def(&"res.tree")
	assert_eq(tree.amount_for(99), 175, "clamps to the largest")
	assert_eq(tree.amount_for(-5), 40, "clamps to the smallest")


func test_the_deer_is_wildlife_and_the_others_are_not() -> void:
	var deer: ResourceDef = reg.resource_def(&"res.deer")
	assert_true(deer.is_wildlife)
	assert_eq(deer.roam_radius, 6)
	assert_true(deer.flees)
	assert_eq(deer.kind, &"food")

	assert_false((reg.resource_def(&"res.tree") as ResourceDef).is_wildlife,
			"a tree does not roam")


# ── ages, techs, factions ──────────────────────────────────────────────────

func test_ages_are_one_indexed_to_match_sim_player() -> void:
	assert_null(reg.age(0), "there is no age 0 -- SimPlayer.age starts at 1")
	var first: AgeDef = reg.age(1)
	assert_not_null(first)
	assert_eq(first.index, 1)
	assert_eq(first.numeral, "I")
	assert_null(reg.age(reg.age_count() + 1), "past the last age is null")


func test_techs_are_empty_but_the_file_loads() -> void:
	# An absent file and an empty one are different states and only one is a bug;
	# this pins that techs.json is the empty kind, not the missing kind.
	assert_eq(reg.tech(&"tech.anything"), null)
	assert_false("; ".join(reg.load_warnings).contains("techs.json"),
			"techs.json loads cleanly rather than reporting as missing")


func test_the_player_colour_palette_covers_every_player_slot() -> void:
	# PLAN.md 1: colour is the ONLY thing distinguishing players, and 3.1 budgets
	# for 8 at full scope, so a short palette would make two players identical.
	assert_eq(reg.colour_count(), 8, "one colour per player slot")


func test_colour_order_is_the_contract_so_index_zero_stays_player_one() -> void:
	# SimPlayer.colour is an index (sim_world.setup() assigns it from join order),
	# so reordering colours.json silently repaints existing saves and replays.
	assert_eq(reg.colour(0), Color.html("#0043D6"), "index 0 is blue")
	assert_eq(reg.colour(7), Color.html("#FFFFFF"), "index 7 is white")


func test_the_first_four_slots_are_the_most_separable_colours() -> void:
	# Most matches are 1v1 or 2v2, so slots 1-4 have to be the safe set. Colour is
	# the ONLY player identifier (PLAN.md 1), so two players who look alike is not
	# a cosmetic problem. Asserted on relative luminance, which is what a
	# colour-blind player falls back on when hue collapses.
	var lum: Array[float] = []
	for i in 4:
		lum.append((reg.colour(i) as Color).get_luminance())
	for i in 4:
		for j in range(i + 1, 4):
			assert_true(absf(lum[i] - lum[j]) > 0.02,
					"slots %d and %d must not be near-identical in brightness" % [i, j])


func test_green_and_yellow_are_far_enough_apart_in_lightness() -> void:
	# The one pair red-green colour blindness genuinely collapses. They cannot be
	# separated by hue, so they must be separated by brightness -- this is what the
	# L* ladder in colours.json's note exists to guarantee, and what silently
	# regresses if someone picks a "nicer" green.
	var green: float = (reg.colour(4) as Color).get_luminance()
	var yellow: float = (reg.colour(2) as Color).get_luminance()
	assert_true(yellow - green > 0.3,
			"yellow must be markedly brighter than green (got %.3f vs %.3f)" % [yellow, green])


func test_an_out_of_range_colour_wraps_rather_than_stopping_the_render() -> void:
	# Deliberately the opposite of unit()/building() returning null: a missing
	# definition has no stand-in, a missing colour does.
	assert_eq(reg.colour(8), reg.colour(0), "wraps at the palette size")
	assert_eq(reg.colour(-1), reg.colour(7), "and wraps downward too")


func test_the_default_faction_exists_so_sim_player_has_something_valid_to_hold() -> void:
	# PLAN.md 2.7.1: one civilisation in v1, but `faction` is half the skin key and
	# survives to 9.5, so SimPlayer's default has to name a real entry.
	assert_true(reg.faction_ids().has(&"faction.default"))
	assert_eq(SimPlayer.new().faction, &"faction.default",
			"SimPlayer's default faction must be an ID this file actually declares")


# ── parsing rules ──────────────────────────────────────────────────────────

func test_json_numbers_become_ints_not_floats() -> void:
	# JSON has no integer type; everything arrives as a float. A float reaching
	# the sim would break determinism (PLAN.md 7.1).
	var cost := GameDefs.int_map({"food": 50.0, "wood": 12.7})
	assert_eq(typeof(cost[&"food"]), TYPE_INT)
	assert_eq(int(cost[&"wood"]), 12, "truncates rather than carrying a float")


func test_unknown_resource_kinds_are_reported_rather_than_dropped() -> void:
	assert_true(GameDefs.unknown_kinds({&"food": 1, &"unobtainium": 5})
			.has(&"unobtainium"))
	assert_true(GameDefs.unknown_kinds({&"food": 1, &"stone": 2}).is_empty())


func test_a_missing_footprint_falls_back_to_one_tile_not_zero() -> void:
	# A zero footprint would occupy no tiles and collide with nothing.
	var b := BuildingDef.from_dict(&"building.x", {})
	assert_eq(b.footprint, Vector2i.ONE)
