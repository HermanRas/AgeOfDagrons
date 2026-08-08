## Phase 4.3: tap-select. The selection set, and picking an entity out of the
## world by the tile under the finger.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	view.pool.free()
	view.terrain.free()
	view.free()


func _entity(id: int, def_id: String, tile: Vector2i, owner := 1,
		footprint := Vector2i.ONE) -> Dictionary:
	var centre := tile * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE / 2, SimWorld.SUBTILE / 2)
	if footprint != Vector2i.ONE:
		centre = SimBuilding.centre_of(tile, footprint)
	var d := {"id": id, "def_id": def_id, "owner_id": owner, "hp": 30, "max_hp": 30,
			"pos": {"x": centre.x, "y": centre.y}}
	if footprint != Vector2i.ONE:
		d["footprint"] = {"x": footprint.x, "y": footprint.y}
		d["phase"] = SimBuilding.Phase.COMPLETE
	return d


func _populate(entries: Array) -> void:
	view.apply_snapshot({"tick": 1, "updated": entries, "removed": []})


# ── the selection set ──────────────────────────────────────────────────────

func test_selecting_replaces_rather_than_accumulates() -> void:
	var s := Selection.new()
	s.set_selection([1, 2] as Array[int])
	s.set_selection([3] as Array[int])
	assert_eq(s.current(), [3] as Array[int])


func test_the_same_id_is_not_selected_twice() -> void:
	var s := Selection.new()
	s.add([1, 1, 2] as Array[int])
	assert_eq(s.size(), 2)


func test_the_returned_list_cannot_be_used_to_mutate_the_selection() -> void:
	# A caller builds a MoveCommand from this; if it were the live array, the
	# command and the selection would alias and drift apart in confusing ways.
	var s := Selection.new()
	s.set_selection([1, 2] as Array[int])
	var taken := s.current()
	taken.append(99)
	assert_eq(s.size(), 2)


func test_selection_is_capped() -> void:
	var many: Array[int] = []
	for i in range(Selection.MAX_SELECTED + 25):
		many.append(i + 1)
	var s := Selection.new()
	s.set_selection(many)
	assert_eq(s.size(), Selection.MAX_SELECTED, "refused rather than truncated silently")


func test_a_dead_entity_drops_out_of_the_selection() -> void:
	# Otherwise an order names an entity the sim rejects and nothing happens,
	# which reads to the player as the game ignoring them.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])
	view.select([1, 2] as Array[int])

	view.apply_snapshot({"tick": 2, "updated": [], "removed": [2]})
	assert_eq(view.selection.current(), [1] as Array[int])


# ── picking (4.3) ──────────────────────────────────────────────────────────

func test_tapping_a_units_own_tile_selects_it() -> void:
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5))), 7)


func test_tapping_anywhere_inside_a_tile_selects_what_is_on_it() -> void:
	# The regression that `Iso.tile_at()` exists for: `world_to_tile()` ROUNDS, so
	# using it here sent the near half of every tile to its neighbour and the tap
	# missed whatever the player was aiming at.
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	var centre := Iso.tile_centre_to_world(Vector2i(5, 5))
	for nudge in [Vector2(0, -12), Vector2(0, 12), Vector2(-24, 0), Vector2(24, 0)]:
		assert_eq(view.pick(centre + nudge), 7, "nudged by %s" % nudge)


func test_tapping_empty_ground_selects_nothing() -> void:
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(20, 20))), 0)


func test_a_building_can_be_tapped_anywhere_on_its_footprint() -> void:
	# A town centre is 8x8; only tapping its centre tile would make most of it
	# untappable.
	_populate([_entity(3, "building.town_center", Vector2i(10, 10), 1, Vector2i(8, 8))])
	for tile in [Vector2i(10, 10), Vector2i(13, 14), Vector2i(17, 17)]:
		assert_eq(view.pick(Iso.tile_centre_to_world(tile)), 3, "tapped %s" % tile)
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(9, 9))), 0, "and not just outside it")


func test_a_unit_standing_on_a_building_wins_the_tap() -> void:
	# The villager is the thing worth tapping; the town centre is not going
	# anywhere and is far easier to hit elsewhere.
	_populate([
		_entity(3, "building.town_center", Vector2i(10, 10), 1, Vector2i(8, 8)),
		_entity(9, "unit.villager", Vector2i(12, 12)),
	])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(12, 12))), 9)


func test_picking_can_be_limited_to_one_players_things() -> void:
	_populate([_entity(4, "unit.villager", Vector2i(5, 5), 2)])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5)), 1), 0, "not mine")
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5)), 2), 4, "theirs")


# ── the ring ───────────────────────────────────────────────────────────────

func test_selecting_marks_the_view_and_deselecting_clears_it() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])

	view.select([1] as Array[int])
	assert_true(view.pool.get_view(1).selected)
	assert_false(view.pool.get_view(2).selected)

	view.select([2] as Array[int])
	assert_false(view.pool.get_view(1).selected, "the old ring is taken away")
	assert_true(view.pool.get_view(2).selected)


func test_a_selection_survives_the_next_snapshot() -> void:
	# Views are pooled and re-pointed every snapshot; a ring that vanished on the
	# next tick would make selection look broken while the state was fine.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	view.select([1] as Array[int])
	_populate([_entity(1, "unit.villager", Vector2i(6, 5))])
	assert_true(view.pool.get_view(1).selected)
