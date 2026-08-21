## Phase 12.1b: the placement ghost on a client, which has the map but no world.
##
## The bar is not "agrees with the server always" -- it cannot, and PLAN.md 12.1b says
## so. The bar is that it agrees about the cases a player actually meets, and that where
## it differs it errs GREEN, costing a refusal rather than blocking something legal.
extends TestCase

var map: SimMap


func before_each() -> void:
	map = SimMap.create(Vector2i(32, 32), SimMap.Terrain.GRASS)


## Snapshot-shaped facts, the way `GameView._facts` records them: `tile` is the CENTRE
## for anything multi-tile.
func _fact(id: int, def_id: StringName, centre: Vector2i, fp: Vector2i,
		owner := 1, alive := true, is_unit := false) -> Dictionary:
	return {"id": id, "def_id": def_id, "tile": centre, "footprint": fp,
			"owner_id": owner, "alive": alive, "is_unit": is_unit}


# ── ground and occupancy ────────────────────────────────────────────────────

func test_open_ground_is_placeable() -> void:
	assert_true(PlacementAdvice.can_place(map, {}, Rect2i(4, 4, 3, 3)))


func test_impassable_terrain_is_refused() -> void:
	map.set_terrain_rect(Rect2i(4, 4, 2, 2), SimMap.Terrain.ROCK)
	assert_false(PlacementAdvice.can_place(map, {}, Rect2i(3, 3, 3, 3)),
			"the ghost reads the ground from the map the config carried")


func test_a_building_in_the_way_is_refused_from_facts_alone() -> void:
	# The half a client cannot get from the map: what has been built since.
	var facts := {7: _fact(7, &"building.house", Vector2i(10, 10), Vector2i(4, 4))}
	assert_false(PlacementAdvice.can_place(map, facts, Rect2i(9, 9, 3, 3)),
			"overlaps the house's footprint")
	assert_true(PlacementAdvice.can_place(map, facts, Rect2i(20, 20, 3, 3)),
			"and well clear of it is fine")


func test_the_centre_convention_is_read_the_same_way_the_view_records_it() -> void:
	# A 4x4 centred on (10,10) claims 8..11 on both axes. Getting this wrong would put
	# the ghost's idea of a building one or two tiles off its art.
	var facts := {7: _fact(7, &"building.house", Vector2i(10, 10), Vector2i(4, 4))}
	assert_false(PlacementAdvice.can_place(map, facts, Rect2i(8, 8, 1, 1)), "top-left corner")
	assert_false(PlacementAdvice.can_place(map, facts, Rect2i(11, 11, 1, 1)), "bottom-right")
	assert_true(PlacementAdvice.can_place(map, facts, Rect2i(7, 7, 1, 1)), "just outside")
	assert_true(PlacementAdvice.can_place(map, facts, Rect2i(12, 12, 1, 1)), "just outside")


func test_units_do_not_block_a_placement() -> void:
	# Placing over villagers is legal and steps them aside
	# (`SimWorld._evict_from_footprint`), so a ghost that went red over them would be
	# refusing something the server allows.
	var facts := {3: _fact(3, &"unit.villager", Vector2i(5, 5), Vector2i.ONE, 1, true, true)}
	assert_true(PlacementAdvice.can_place(map, facts, Rect2i(4, 4, 3, 3)))


func test_rubble_and_corpses_do_not_block() -> void:
	# Building over rubble clears it (5.5); `alive` is false by then.
	var facts := {9: _fact(9, &"building.house", Vector2i(10, 10), Vector2i(4, 4), 1, false)}
	assert_true(PlacementAdvice.can_place(map, facts, Rect2i(9, 9, 3, 3)))


func test_a_resource_node_blocks() -> void:
	var facts := {11: _fact(11, &"res.tree", Vector2i(6, 6), Vector2i.ONE, 0)}
	assert_false(PlacementAdvice.can_place(map, facts, Rect2i(6, 6, 2, 2)))


func test_a_null_map_still_consults_the_facts() -> void:
	# The tick before the config lands; the ghost should not go green over a building.
	var facts := {7: _fact(7, &"building.house", Vector2i(10, 10), Vector2i(4, 4))}
	assert_false(PlacementAdvice.can_place(null, facts, Rect2i(10, 10, 1, 1)))


# ── adjacency ───────────────────────────────────────────────────────────────

func test_anything_without_an_adjacency_rule_is_allowed_anywhere() -> void:
	assert_true(PlacementAdvice.adjacency_allows(&"building.house", 1, Vector2i(5, 5), {}))


func test_a_field_needs_a_mill_of_its_own_beside_it() -> void:
	var mill_fp: Vector2i = GameDataRegistry.building(&"building.mill").footprint
	var field_fp: Vector2i = GameDataRegistry.building(&"building.field").footprint

	# A mill centred at (10,10), and a field whose footprint starts right after it.
	var facts := {5: _fact(5, &"building.mill", Vector2i(10, 10), mill_fp)}
	var mill_rect := Rect2i(Vector2i(10, 10) - mill_fp / 2, mill_fp)

	var touching := Vector2i(mill_rect.end.x, mill_rect.position.y)
	assert_true(PlacementAdvice.adjacency_allows(&"building.field", 1, touching, facts),
			"abutting the mill's east edge")

	var far := Vector2i(mill_rect.end.x + 3, mill_rect.position.y)
	assert_false(PlacementAdvice.adjacency_allows(&"building.field", 1, far, facts),
			"three tiles clear of it is not abutting")
	assert_true(field_fp.x > 0, "the field has a real footprint to place")


func test_somebody_elses_mill_is_not_a_host() -> void:
	var mill_fp: Vector2i = GameDataRegistry.building(&"building.mill").footprint
	var facts := {5: _fact(5, &"building.mill", Vector2i(10, 10), mill_fp, 2)}
	var mill_rect := Rect2i(Vector2i(10, 10) - mill_fp / 2, mill_fp)
	assert_false(PlacementAdvice.adjacency_allows(&"building.field", 1,
			Vector2i(mill_rect.end.x, mill_rect.position.y), facts))


func test_a_dead_mill_is_not_a_host() -> void:
	var mill_fp: Vector2i = GameDataRegistry.building(&"building.mill").footprint
	var facts := {5: _fact(5, &"building.mill", Vector2i(10, 10), mill_fp, 1, false)}
	var mill_rect := Rect2i(Vector2i(10, 10) - mill_fp / 2, mill_fp)
	assert_false(PlacementAdvice.adjacency_allows(&"building.field", 1,
			Vector2i(mill_rect.end.x, mill_rect.position.y), facts))


# ── affordability ───────────────────────────────────────────────────────────

func test_affordability_comes_off_the_snapshots_stock() -> void:
	var cost := {&"wood": 100, &"food": 20}
	assert_true(PlacementAdvice.can_afford(cost, {&"wood": 100, &"food": 20}), "exactly enough")
	assert_true(PlacementAdvice.can_afford(cost, {&"wood": 500, &"food": 500}))
	assert_false(PlacementAdvice.can_afford(cost, {&"wood": 99, &"food": 500}))
	assert_false(PlacementAdvice.can_afford(cost, {}), "an empty treasury affords nothing")
	assert_true(PlacementAdvice.can_afford({}, {}), "and a free building is always affordable")


# ── it agrees with the authority where it counts ────────────────────────────

func test_it_agrees_with_the_real_world_across_a_generated_map() -> void:
	# The assertion worth having: build a real world, then ask both the authority and
	# the advice about the same tiles and require them to agree. Where they differ the
	# advice must be the GREENER of the two -- never refusing something legal.
	var cfg := MatchConfig.debug_generated(4, MapGenerator.Type.FOREST, 2)
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)

	var client_map := SimMap.create(cfg.map_data.size)
	for y in range(cfg.map_data.size.y):
		for x in range(cfg.map_data.size.x):
			var t := Vector2i(x, y)
			client_map.set_terrain(t, cfg.map_data.terrain_at(t) as SimMap.Terrain)

	# Facts in the shape GameView records, for everything in the world.
	var facts := {}
	for e in w.entities.values():
		var fp := Vector2i.ONE
		if e is SimBuilding:
			fp = (e as SimBuilding).footprint
		elif e is SimResourceNode:
			fp = (e as SimResourceNode).footprint
		facts[e.id] = _fact(e.id, e.def_id, e.tile(), fp, e.owner_id, e.alive, e is SimUnit)

	var fp3 := Vector2i(3, 3)
	var checked := 0
	var refused_when_legal := 0
	for y in range(0, cfg.map_data.size.y - 3, 3):
		for x in range(0, cfg.map_data.size.x - 3, 3):
			var rect := SimMap.footprint_rect(Vector2i(x, y), fp3)
			var truth := w.map.can_place_building(rect)
			var advice := PlacementAdvice.can_place(client_map, facts, rect)
			checked += 1
			if truth and not advice:
				refused_when_legal += 1
	assert_true(checked > 100, "checked %d candidate footprints" % checked)
	assert_eq(refused_when_legal, 0,
			"the advice never refuses ground the server would accept (%d of %d)"
			% [refused_when_legal, checked])
