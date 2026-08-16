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
	assert_true(field.gather_amount < GameDataRegistry.building(&"building.field").gather_amount,
			"and it came out of the crop")


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


func test_a_spent_field_is_removed_and_gives_its_ground_back() -> void:
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
