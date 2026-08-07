## Phase 0.6: apply_snapshot() is the only thing standing between a wire
## Dictionary (PLAN.md 7.2) and pooled views -- test it directly rather than
## the JSON snapshot format.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# _ready() (which parents pool and terrain under view) only runs once a node
	# enters a tree, which never happens for a bare .new() in a headless test --
	# so both are separate orphans and must be freed on their own.
	view.pool.free()
	view.terrain.free()
	view.free()


func test_apply_snapshot_acquires_a_view_at_the_projected_position() -> void:
	var sub_pos := Vector2i(3, 3) * SimWorld.SUBTILE
	view.apply_snapshot({
		"tick": 1,
		"updated": [{"id": 7, "def_id": "unit.villager", "pos": {"x": sub_pos.x, "y": sub_pos.y},
				"hp": 30, "max_hp": 30}],
		"removed": [],
	})
	var v := view.pool.get_view(7)
	assert_not_null(v)
	v.advance(EntityView.INTERP_SECONDS)          # land on the target for a clean assert
	assert_eq(v.position, Iso.sub_to_world(sub_pos))
	assert_almost_eq(v.health_pct, 1.0, 0.001)


func test_apply_snapshot_removed_releases_the_view() -> void:
	view.apply_snapshot({"tick": 1, "updated": [{"id": 9, "pos": {"x": 0, "y": 0}}], "removed": []})
	assert_not_null(view.pool.get_view(9))

	view.apply_snapshot({"tick": 2, "updated": [], "removed": [9]})
	assert_null(view.pool.get_view(9))


# ── depth sorting for large footprints (3.1) ───────────────────────────────

func _snapshot_of(id: int, def_id: String, tile: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var entry := {"id": id, "def_id": def_id, "hp": 10, "max_hp": 10,
			"pos": {"x": tile.x * SimWorld.SUBTILE, "y": tile.y * SimWorld.SUBTILE}}
	entry.merge(extra)
	return {"tick": 1, "updated": [entry], "removed": []}


func test_a_building_sorts_by_its_front_tile_but_draws_on_its_centre() -> void:
	# The 2.6 defect: an 8x8 town centre sorted as though it stood on its middle
	# tile, so villagers on the near side drew over its roof. The node has to sit
	# further down the screen than the sprite does.
	var centre := Vector2i(10, 10) * SimWorld.SUBTILE
	view.apply_snapshot(_snapshot_of(1, "building.town_center", Vector2i(10, 10),
			{"footprint": {"x": 8, "y": 8}, "phase": SimBuilding.Phase.COMPLETE}))

	var v := view.pool.get_view(1)
	assert_true(v.position.y > Iso.sub_to_world(centre).y,
			"the node sorts at the front tile, nearer the camera than the centre")
	assert_almost_eq(v.position.y + v.draw_offset.y, Iso.sub_to_world(centre).y, 0.01,
			"and draw_offset puts the art back on the centre")


func test_a_unit_sorts_where_it_stands() -> void:
	# A 1x1 footprint's front tile IS its tile, so nothing about units changes.
	view.apply_snapshot(_snapshot_of(2, "unit.villager", Vector2i(4, 6)))
	var v := view.pool.get_view(2)
	assert_eq(v.draw_offset, Vector2.ZERO)
	assert_eq(v.position, Iso.sub_to_world(Vector2i(4, 6) * SimWorld.SUBTILE))


func test_a_unit_in_front_of_a_building_sorts_after_it() -> void:
	# The assertion the whole fix exists for, stated the way the engine reads it:
	# Y-sort draws larger position.y last, so "in front" must mean "greater y".
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "building.town_center", "footprint": {"x": 8, "y": 8},
			"phase": SimBuilding.Phase.COMPLETE,
			"pos": {"x": 10 * SimWorld.SUBTILE, "y": 10 * SimWorld.SUBTILE}},
		# Standing on the tile just beyond the footprint's front corner.
		{"id": 2, "def_id": "unit.villager",
			"pos": {"x": 15 * SimWorld.SUBTILE, "y": 15 * SimWorld.SUBTILE}},
		# And one behind the building's back corner.
		{"id": 3, "def_id": "unit.villager",
			"pos": {"x": 5 * SimWorld.SUBTILE, "y": 5 * SimWorld.SUBTILE}},
	], "removed": []})

	var building := view.pool.get_view(1)
	assert_true(view.pool.get_view(2).position.y > building.position.y,
			"a unit in front of the building draws after it")
	assert_true(view.pool.get_view(3).position.y < building.position.y,
			"a unit behind it draws before it")


func test_a_newly_seen_entity_snaps_instead_of_gliding_in() -> void:
	# Interpolation is for entities that moved. A view acquired from the pool
	# starts wherever its previous occupant died, so interpolating its first
	# position slid a fresh spawn across the map for 100 ms.
	view.apply_snapshot(_snapshot_of(5, "unit.villager", Vector2i(9, 9)))
	assert_eq(view.pool.get_view(5).position,
			Iso.sub_to_world(Vector2i(9, 9) * SimWorld.SUBTILE),
			"in place on the first snapshot, with no advance() call")


func test_process_advances_the_pool() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "pos": {"x": 0, "y": 0}},
	], "removed": []})
	var v := view.pool.get_view(1)
	v.position = Vector2.ZERO
	v.set_target_transform(Vector2(40, 0), 2)

	view._process(EntityView.INTERP_SECONDS)
	assert_almost_eq(v.position.x, 40.0, 0.01)
