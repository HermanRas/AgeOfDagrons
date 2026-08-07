## Phase 0.4: the entity half of GameDataRegistry -- units, buildings,
## resources, techs, ages (PLAN.md 9, 6.1).
##
## Two kinds of test here, and the second is the valuable one:
##
##   1. The *Def classes parse what the schema says they parse.
##   2. The SHIPPED data is internally consistent. Every ID that one file
##      references in another actually exists. Nothing else in the codebase will
##      notice a renamed ID until a villager silently fails to spawn at runtime,
##      so validate() coming back clean is a CI gate, not a nicety.
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
	# PLAN.md 10: 1 unit, 2 buildings, 3 resource nodes.
	assert_eq(reg.unit_ids(), [&"unit.villager"] as Array[StringName])
	assert_eq(reg.building_ids(),
			[&"building.house", &"building.town_center"] as Array[StringName])
	assert_eq(reg.resource_ids(),
			[&"res.deer", &"res.gold_mine", &"res.tree"] as Array[StringName])


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

func test_footprints_are_the_measured_ones_not_the_pre_measurement_sketch() -> void:
	# PLAN.md 9 wrote [4, 4] for the town centre before the art was measured; the
	# civic centre is 15.53 x 15.00 m, i.e. 7.77 tiles. This pins the correction
	# so it cannot quietly revert.
	assert_eq((reg.building(&"building.town_center") as BuildingDef).footprint,
			Vector2i(8, 8), "town centre is 8x8, from the measured art")
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


func test_a_neutral_faction_exists_so_sim_player_has_something_valid_to_hold() -> void:
	assert_true(reg.faction_ids().has(&"faction.neutral"))


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
