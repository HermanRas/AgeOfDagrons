## Fields (PLAN.md 6.5): a building that is placed and built like a building and
## then HARVESTED like a berry bush.
##
## `building.field` shipped in buildings.json with no code behind it at all --
## placeable anywhere, yielding nothing, and selecting rather than gathering when
## tapped. The project owner found all three at once (2026-08-16). Two rules come
## from the roster line `Farm[Mill] ... can add up to 4 field`:
## a field must touch a mill, and four is the most one mill will carry.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)
	w.player_for(1).stock = {&"wood": 5000, &"food": 5000}
	w.player_for(1).age = 2          # building.field is age 2
	w.player_for(2).age = 2


func _mill(owner: int = 1, at: Vector2i = Vector2i(10, 10)) -> SimBuilding:
	return w.spawn_building(&"building.mill", owner, at, SimBuilding.Phase.COMPLETE, true)


## A field's 6x6 origin such that its footprint abuts `mill` on the west side.
func _beside(mill: SimBuilding) -> Vector2i:
	return mill.origin_tile() - Vector2i(6, 0)


func _place(origin: Vector2i, owner: int = 1) -> bool:
	var cmd := PlaceBuildingCommand.new(owner, &"building.field", origin)
	return cmd.validate(w)


func _fields() -> Array:
	var out: Array = []
	for e in w.entities.values():
		if e is SimBuilding and e.def_id == &"building.field":
			out.append(e)
	return out


# ── placement must touch a mill ─────────────────────────────────────────────

func test_a_field_may_be_placed_touching_a_mill() -> void:
	var mill := _mill()
	assert_true(_place(_beside(mill)))


func test_a_field_may_not_be_placed_out_in_the_open() -> void:
	_mill()
	assert_false(_place(Vector2i(30, 30)), "nowhere near a mill")


func test_a_field_may_not_be_placed_with_no_mill_at_all() -> void:
	assert_false(_place(Vector2i(10, 10)))


func test_touching_means_touching_not_merely_close() -> void:
	# One tile of gap is not adjacency. Checked because `grow(1).intersects()`
	# is exactly the sort of off-by-one that would let a field float.
	var mill := _mill()
	assert_true(_place(_beside(mill)), "flush against it")
	assert_false(_place(_beside(mill) - Vector2i(1, 0)), "one tile clear of it")


func test_a_mill_still_under_construction_is_not_a_host() -> void:
	# Its foundation may yet be cancelled or destroyed out from under the field.
	var mill := w.spawn_building(&"building.mill", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, true)
	assert_false(_place(_beside(mill)))


func test_somebody_elses_mill_is_not_a_host() -> void:
	var theirs := _mill(2)
	assert_false(_place(_beside(theirs), 1), "you cannot farm off a neighbour's mill")


func test_everything_that_is_not_a_field_still_places_anywhere() -> void:
	# The rule is opt-in through `requires_adjacent`; a house must not inherit it.
	assert_true(PlaceBuildingCommand.new(1, &"building.house", Vector2i(30, 30)).validate(w))


# ── four to a mill ──────────────────────────────────────────────────────────

func test_a_mill_carries_four_fields_and_refuses_a_fifth() -> void:
	# Two fields down each side of the mill, none of them overlapping. The
	# assertion is about the CAP, so the fifth is tested through
	# `adjacency_allows` rather than a full placement: that is the predicate the
	# rule lives in, and it is deliberately separate from whether the ground
	# happens to be free (`can_place_building` answers that). Around a 5x4 mill
	# ringed by four 6x6 fields there is no free touching ground left, so a
	# placement-based test would pass for the wrong reason.
	var mill := _mill()
	var origin := mill.origin_tile()
	var spots: Array[Vector2i] = [
		origin - Vector2i(6, 6), origin - Vector2i(6, 0),
		origin + Vector2i(5, -6), origin + Vector2i(5, 0),
	]
	for i in range(spots.size()):
		assert_true(w.adjacency_allows(&"building.field", 1, spots[i]),
				"field %d is allowed" % (i + 1))
		assert_not_null(w.spawn_building(&"building.field", 1, spots[i],
				SimBuilding.Phase.COMPLETE), "field %d fits on the grid" % (i + 1))
	assert_eq(_fields().size(), 4)
	assert_eq(w._count_abutting(&"building.field", 1, mill), 4)

	assert_false(w.adjacency_allows(&"building.field", 1, origin - Vector2i(6, 12)),
			"the mill is full at four, however much room is left around it")


func test_a_foundation_counts_against_the_cap() -> void:
	# Otherwise the cap is beatable by placing all of them before any finishes.
	var mill := _mill()
	var f := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.FOUNDATION, true)
	assert_not_null(f)
	assert_eq(w._count_abutting(&"building.field", 1, mill), 1)


func test_a_second_mill_carries_its_own_four() -> void:
	var a := _mill(1, Vector2i(10, 10))
	var b := _mill(1, Vector2i(30, 30))
	assert_true(_place(_beside(a)))
	assert_true(_place(_beside(b)), "a different mill has its own allowance")


# ── harvesting ──────────────────────────────────────────────────────────────

func test_a_villager_farms_a_field_and_banks_the_food() -> void:
	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.COMPLETE, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))

	w.queue_command(GatherCommand.new(1, [v.id], field.id))
	var before: int = w.player_for(1).stock.get(&"food", 0)
	for i in range(600):
		w.step()
		if int(w.player_for(1).stock.get(&"food", 0)) > before:
			break
	assert_true(int(w.player_for(1).stock.get(&"food", 0)) > before,
			"a load of food reached the stockpile")
	assert_eq(field.gather_amount, BuildingDef.INFINITE_CROP,
			"and it did NOT come out of a crop -- a field never depletes")


# ── a field never runs out (project owner, 2026-08-17) ──────────────────────

func test_a_field_is_inexhaustible() -> void:
	# It used to carry 300 food and be removed when harvested out. Farm it for a
	# thousand ticks and it is still standing with the same crop it started with.
	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.COMPLETE, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))
	w.queue_command(GatherCommand.new(1, [v.id], field.id))

	for i in range(1000):
		w.step()

	assert_not_null(w.get_entity(field.id), "still there after a thousand ticks")
	assert_false(field.is_spent())
	assert_eq(field.gather_amount, BuildingDef.INFINITE_CROP)
	assert_true(int(w.player_for(1).stock.get(&"food", 0)) > 5000,
			"and it has been feeding the town the whole time")


func test_an_infinite_crop_hands_back_whatever_is_asked_for() -> void:
	var b := SimBuilding.new()
	b.gather_kind = &"food"
	b.gather_amount = BuildingDef.INFINITE_CROP
	assert_eq(b.gather(4), 4)
	assert_eq(b.gather(400), 400, "and does not run down")
	assert_eq(b.gather_amount, BuildingDef.INFINITE_CROP)
	assert_false(b.is_spent())


# ── five to a plot, four plots to a mill ────────────────────────────────────

func test_five_villagers_can_work_one_field() -> void:
	# The owner's cap. Crossed with max_per_host = 4, one mill absorbs 20 farmers.
	var bd: BuildingDef = GameDataRegistry.building(&"building.field")
	assert_eq(bd.gather_slots, 5)
	assert_eq(bd.max_per_host, 4)

	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.COMPLETE, true)
	var farmers: Array[int] = []
	for i in range(6):
		farmers.append(w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12 + i)).id)
	w.queue_command(GatherCommand.new(1, farmers, field.id))

	# Long enough for all six to walk over and settle into GATHER or RETURN.
	for i in range(400):
		w.step()

	var working := 0
	for id in farmers:
		var u: SimUnit = w.get_entity(id)
		if u.task == SimUnit.Task.GATHER or u.task == SimUnit.Task.RETURN:
			working += 1
	assert_true(working >= 5, "at least the five slot-holders are on the job")


# ── the age-scaled yield ────────────────────────────────────────────────────

func test_the_yield_comes_from_the_field_and_rises_with_the_age() -> void:
	# The owner's numbers, per villager per tick: none at age 1, then 1, 2.5, 4.
	# Authored per 100 ticks so it shares a unit with UnitDef.gather_rate.
	var bd: BuildingDef = GameDataRegistry.building(&"building.field")
	assert_eq(bd.gather_yield_for_age(1), 0, "there are no fields in age 1")
	assert_eq(bd.gather_yield_for_age(2), 100)
	assert_eq(bd.gather_yield_for_age(3), 250)
	assert_eq(bd.gather_yield_for_age(4), 400)
	assert_eq(bd.gather_yield_for_age(9), 400, "a fifth age would inherit the fourth")


func test_a_field_out_yields_a_berry_bush_by_the_declared_ratio() -> void:
	# The comparison worth having in front of anyone balancing this: the villager's
	# own food rate is 25 per 100 ticks, so an age-2 plot is 4x a bush per farmer
	# and an age-4 plot is 16x.
	var villager: UnitDef = GameDataRegistry.unit(&"unit.villager")
	var bd: BuildingDef = GameDataRegistry.building(&"building.field")
	assert_eq(int(villager.gather_rate.get(&"food", 0)), 25)
	assert_eq(bd.gather_yield_for_age(2), 4 * 25)
	assert_eq(bd.gather_yield_for_age(4), 16 * 25)


func test_a_higher_age_actually_banks_food_faster() -> void:
	# Through the whole loop rather than off the def: two identical worlds, one at
	# age 2 and one at age 4, farming for the same number of ticks.
	var banked: Array[int] = []
	for age in [2, 4]:
		var world := SimWorld.new()
		var cfg := MatchConfig.new()
		cfg.player_ids = [1]
		cfg.map_size = Vector2i(48, 48)
		world.setup(cfg)
		world.map.fill_terrain(SimMap.Terrain.GRASS)
		world.player_for(1).age = age
		var m: SimBuilding = world.spawn_building(&"building.mill", 1, Vector2i(10, 10),
				SimBuilding.Phase.COMPLETE, true)
		var f: SimBuilding = world.spawn_building(&"building.field", 1,
				m.origin_tile() - Vector2i(6, 0), SimBuilding.Phase.COMPLETE, true)
		# Outside the mill's own footprint, like every other fixture here: a unit
		# standing inside a claimed 5x4 has nowhere to path from.
		var v: SimUnit = world.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))
		world.queue_command(GatherCommand.new(1, [v.id], f.id))
		for i in range(900):
			world.step()
		banked.append(int(world.player_for(1).stock.get(&"food", 0)))

	assert_true(banked[1] > banked[0],
			"age 4 banked %d against age 2's %d" % [banked[1], banked[0]])


func test_the_take_schedule_is_exact_above_one_unit_a_tick() -> void:
	# The old "one unit every ceil(100/rate) ticks" floors at a one-tick interval,
	# so 250 and 400 and 10000 all collapsed to 1 a tick. As a fraction in lowest
	# terms 250 is 5 units every 2 ticks -- exactly 2.5 -- with no float anywhere.
	assert_eq(GatherSystem.take_schedule(25), Vector2i(1, 4), "unchanged: the villager")
	assert_eq(GatherSystem.take_schedule(100), Vector2i(1, 1))
	assert_eq(GatherSystem.take_schedule(250), Vector2i(5, 2))
	assert_eq(GatherSystem.take_schedule(400), Vector2i(4, 1))
	assert_eq(GatherSystem.take_schedule(0), Vector2i.ZERO, "nothing yields nothing")
	# Strictly more accurate where the two forms differ: 40 per 100 ticks is 0.4 a
	# tick, which the interval form rounded to one every 3 ticks, i.e. 0.33.
	assert_eq(GatherSystem.take_schedule(40), Vector2i(2, 5))


func test_the_villager_stands_at_the_edge_of_a_field_not_its_centre() -> void:
	# A 6x6 footprint measured centre-to-centre would need the villager three
	# tiles INSIDE the crop before it counted as arrived -- the same mistake
	# CombatSystem.tile_gap exists to avoid, and it would deadlock the gather.
	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.COMPLETE, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))

	w.queue_command(GatherCommand.new(1, [v.id], field.id))
	var ticks := -1
	for i in range(600):
		w.step()
		if v.carry_amount > 0:
			ticks = i
			break
	assert_true(ticks > 0, "it actually started farming")
	assert_false(field.footprint_rect().has_point(v.tile()),
			"and did it from outside the crop")


## Unreachable for a FIELD now that its crop is infinite -- the crop is set to a
## finite 2 by hand here. Kept because the machinery is still live and still the
## right behaviour for whatever wants a one-harvest crop next: a spent gatherable
## is despawned rather than left as rubble, and its ground comes straight back.
func test_a_spent_gatherable_is_removed_and_gives_its_ground_back() -> void:
	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.COMPLETE, true)
	var rect := field.footprint_rect()
	field.gather_amount = 2
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))

	w.queue_command(GatherCommand.new(1, [v.id], field.id))
	for i in range(600):
		w.step()
		if w.get_entity(field.id) == null:
			break
	assert_null(w.get_entity(field.id), "harvested out and gone, not left as rubble")
	assert_true(w.map.can_place_building(rect), "the ground is free for the next one")


func test_you_cannot_farm_someone_elses_field() -> void:
	var theirs := w.spawn_building(&"building.field", 2, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(29, 29))
	assert_false(GatherCommand.new(1, [v.id], theirs.id).validate(w))


func test_a_field_still_being_built_cannot_be_farmed() -> void:
	var mill := _mill()
	var field := w.spawn_building(&"building.field", 1, _beside(mill),
			SimBuilding.Phase.FOUNDATION, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))
	assert_false(GatherCommand.new(1, [v.id], field.id).validate(w))


func test_an_ordinary_building_is_not_harvestable() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(29, 29))
	assert_false(GatherCommand.new(1, [v.id], house.id).validate(w),
			"a house has no crop")


# ── determinism (7.1) ───────────────────────────────────────────────────────

func test_two_worlds_farming_the_same_field_stay_identical() -> void:
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)
	# before_each stocked and aged player 1 in `w` only; the two worlds have to
	# start byte-identical or they diverge on tick 1 for a reason that has
	# nothing to do with farming.
	other.player_for(1).stock = w.player_for(1).stock.duplicate()
	other.player_for(1).age = w.player_for(1).age
	other.player_for(2).age = w.player_for(2).age

	for world: SimWorld in [w, other]:
		var m: SimBuilding = world.spawn_building(&"building.mill", 1, Vector2i(10, 10),
				SimBuilding.Phase.COMPLETE, true)
		var f: SimBuilding = world.spawn_building(&"building.field", 1,
				m.origin_tile() - Vector2i(6, 0), SimBuilding.Phase.COMPLETE, true)
		var v: SimUnit = world.spawn_unit(&"unit.villager", 1, Vector2i(20, 12))
		world.queue_command(GatherCommand.new(1, [v.id], f.id))

	for i in range(300):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
