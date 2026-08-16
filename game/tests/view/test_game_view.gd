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


func test_a_unit_that_ties_a_buildings_front_corner_still_sorts_after_it() -> void:
	# Reproduced live (a since-deleted dev_preview scene) while wiring up 4.5's
	# build-assist tap: a villager sent to build a house walked to the tile
	# immediately east of its footprint and rendered BEHIND it. An even
	# footprint's front-corner sort point sits at a HALF-tile offset
	# (footprint_sort_offset), and that lands it on the same iso depth
	# (x + y) as several of the tiles PathService commonly substitutes a
	# worker onto -- here, a 4x4 house centred at tile (22, 28) sorts at the
	# same depth as tile (24, 28), a perfectly ordinary place to stand while
	# building it.
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "building.house", "footprint": {"x": 4, "y": 4},
			"phase": SimBuilding.Phase.UNDER_CONSTRUCTION,
			"pos": {"x": 22 * SimWorld.SUBTILE, "y": 28 * SimWorld.SUBTILE}},
		{"id": 2, "def_id": "unit.villager",
			"pos": {"x": 24 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2,
					"y": 28 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2}},
	], "removed": []})

	var building := view.pool.get_view(1)
	var worker := view.pool.get_view(2)
	assert_true(worker.position.y > building.position.y,
			"touching the footprint's edge must resolve in the unit's favour")


func test_a_unit_beside_the_middle_of_a_large_buildings_edge_sorts_after_it() -> void:
	# The actual reported bug, one step past the tie above: the front-corner
	# sort point is a single point, so it only compares fairly against a unit
	# standing right at that corner. A unit beside the MIDDLE of a large
	# building's east or south edge is several tiles short in projected depth
	# by that same point -- not a tie, a real-looking gap -- so it sorted
	# behind the whole building even though it was plainly standing beside
	# it. Reproduced live sending all 5 starting villagers to gather next to
	# the town centre and watching returners clip at drop-off (a
	# since-deleted dev_preview scene). Session decision: a unit touching a
	# building's footprint at all -- any edge, not just the front corner --
	# always sorts after it.
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "building.town_center", "footprint": {"x": 8, "y": 8},
			"phase": SimBuilding.Phase.COMPLETE,
			"pos": {"x": 32 * SimWorld.SUBTILE, "y": 32 * SimWorld.SUBTILE}},
		# Tile (36, 32): touches the middle of the east edge, nowhere near
		# the front (south-east) corner at (35, 35).
		{"id": 2, "def_id": "unit.villager",
			"pos": {"x": 36 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2,
					"y": 32 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2}},
	], "removed": []})

	var building := view.pool.get_view(1)
	var worker := view.pool.get_view(2)
	assert_true(worker.position.y > building.position.y,
			"beside the edge, nowhere near the front corner, still sorts in front")


func test_a_unit_only_diagonally_touching_a_buildings_back_corner_stays_behind() -> void:
	# The edge-adjacency bonus must not swallow the ORIGINAL 3.1 case: a unit
	# diagonally near the back corner (sharing a point, not a side) is
	# genuinely behind the building, not beside an edge someone is working
	# at, and must keep sorting behind it.
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "building.town_center", "footprint": {"x": 8, "y": 8},
			"phase": SimBuilding.Phase.COMPLETE,
			"pos": {"x": 10 * SimWorld.SUBTILE, "y": 10 * SimWorld.SUBTILE}},
		# One tile up-left of the back corner (6, 6) -- a diagonal touch only.
		{"id": 2, "def_id": "unit.villager",
			"pos": {"x": 5 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2,
					"y": 5 * SimWorld.SUBTILE + SimWorld.SUBTILE / 2}},
	], "removed": []})

	var building := view.pool.get_view(1)
	var worker := view.pool.get_view(2)
	assert_true(worker.position.y < building.position.y,
			"a diagonal corner touch is not an edge -- still genuinely behind")


func test_a_newly_seen_entity_snaps_instead_of_gliding_in() -> void:
	# Interpolation is for entities that moved. A view acquired from the pool
	# starts wherever its previous occupant died, so interpolating its first
	# position slid a fresh spawn across the map for 100 ms.
	view.apply_snapshot(_snapshot_of(5, "unit.villager", Vector2i(9, 9)))
	assert_eq(view.pool.get_view(5).position,
			Iso.sub_to_world(Vector2i(9, 9) * SimWorld.SUBTILE),
			"in place on the first snapshot, with no advance() call")


# ── villager headcount (7.1) ───────────────────────────────────────────────

func test_villager_counts_splits_idle_from_busy_and_ignores_other_players() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
				"pos": {"x": 0, "y": 0}},
		{"id": 3, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.GATHER,
				"pos": {"x": 0, "y": 0}},
		# A building must not be counted as a villager just because it too is idle.
		{"id": 4, "def_id": "building.town_center", "owner_id": 1,
				"footprint": {"x": 8, "y": 8}, "phase": SimBuilding.Phase.COMPLETE,
				"pos": {"x": 0, "y": 0}},
		# Someone else's villager must not show up in player 1's count.
		{"id": 5, "def_id": "unit.villager", "owner_id": 2, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
	], "removed": []})

	assert_eq(view.villager_counts(1), Vector2i(1, 3), "1 idle of 3 villagers, gaia/enemy excluded")


func test_villager_counts_is_zero_with_nothing_in_view() -> void:
	assert_eq(view.villager_counts(1), Vector2i(0, 0))


func test_process_advances_the_pool() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "pos": {"x": 0, "y": 0}},
	], "removed": []})
	var v := view.pool.get_view(1)
	v.position = Vector2.ZERO
	v.set_target_transform(Vector2(40, 0), 2)

	view._process(EntityView.INTERP_SECONDS)
	assert_almost_eq(v.position.x, 40.0, 0.01)


# ── tap_action (4.5) ────────────────────────────────────────────────────────

func _snap(entries: Array) -> void:
	view.apply_snapshot({"tick": 1, "updated": entries, "removed": []})


func test_tapping_empty_ground_with_nothing_selected_does_nothing() -> void:
	assert_eq(view.tap_action(0, 1, false), GameView.TapAction.NONE)


func test_tapping_empty_ground_with_a_movable_selection_moves() -> void:
	assert_eq(view.tap_action(0, 1, true), GameView.TapAction.MOVE)


func test_tapping_my_own_unit_always_selects_it() -> void:
	_snap([{"id": 1, "def_id": "unit.villager", "owner_id": 1, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, false), GameView.TapAction.SELECT)
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.SELECT,
			"never redirected into an order, even with others selected")


func test_tapping_my_own_incomplete_building_with_builders_selected_sends_them() -> void:
	_snap([{"id": 1, "def_id": "building.house", "owner_id": 1, "footprint": {"x": 2, "y": 2},
			"phase": SimBuilding.Phase.UNDER_CONSTRUCTION, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.BUILD)


func test_tapping_my_own_incomplete_building_with_nothing_selected_still_selects_it() -> void:
	_snap([{"id": 1, "def_id": "building.house", "owner_id": 1, "footprint": {"x": 2, "y": 2},
			"phase": SimBuilding.Phase.UNDER_CONSTRUCTION, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, false), GameView.TapAction.SELECT)


func test_tapping_my_own_complete_building_always_selects_it() -> void:
	_snap([{"id": 1, "def_id": "building.town_center", "owner_id": 1, "footprint": {"x": 8, "y": 8},
			"phase": SimBuilding.Phase.COMPLETE, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.SELECT,
			"a finished building's training row must stay reachable by tapping it")


func test_tapping_a_resource_node_with_gatherers_selected_gathers() -> void:
	_snap([{"id": 1, "def_id": "res.tree", "owner_id": 0, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.GATHER)


func test_tapping_a_resource_node_with_nothing_selected_does_nothing() -> void:
	_snap([{"id": 1, "def_id": "res.tree", "owner_id": 0, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, false), GameView.TapAction.NONE)


func test_tapping_someone_elses_unit_with_a_movable_selection_moves_there_instead() -> void:
	_snap([{"id": 1, "def_id": "unit.villager", "owner_id": 2, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.MOVE)


# -- the skin key: age and player colour (PLAN.md 2.7.1) ---------------------

func _skinned_snapshot(owner: int, age: int, colour: int, def_id := "unit.villager") -> Dictionary:
	return {
		"tick": 1,
		"updated": [{"id": 42, "def_id": def_id, "owner_id": owner, "hp": 10, "max_hp": 10,
				"pos": {"x": SimWorld.SUBTILE, "y": SimWorld.SUBTILE}}],
		"removed": [],
		"player_state": {owner: {"age": age, "colour": colour, "stock": {},
				"pop_used": 0, "pop_cap": 10, "control_groups": [[], [], [], [], []]}},
	}


func test_an_entity_takes_its_owners_age_and_colour() -> void:
	view.apply_snapshot(_skinned_snapshot(1, 3, 5))
	var v := view.pool.get_view(42)
	assert_eq(v.skin_age, 3)
	assert_eq(v.skin_colour, 5, "colour is a palette INDEX, not a Color")


func test_a_gaia_entity_is_unaged_and_untinted() -> void:
	# colours.json is explicit that the tint keys off WHO OWNS a thing, never off
	# whether its art carries a playercolor mask -- 0 A.D.'s sheep declares one
	# and is still nobody's sheep. Owner 0 must not silently read as player 1.
	view.apply_snapshot({
		"tick": 1,
		"updated": [{"id": 7, "def_id": "res.tree", "owner_id": 0, "hp": 1, "max_hp": 1,
				"pos": {"x": 0, "y": 0}}],
		"removed": [],
		"player_state": {1: {"age": 4, "colour": 2}},
	})
	var v := view.pool.get_view(7)
	assert_eq(v.skin_age, 0, "gaia has no age skin")
	assert_eq(v.skin_colour, -1, "and no player tint")


func test_a_standing_building_re_skins_when_its_owner_advances() -> void:
	# PLAN.md 2.7 item 2: a building re-skins IN PLACE as its owner advances,
	# which is why its footprint is locked to the max across all four skins. The
	# only signal is the age changing in player_state, so the view has to read it
	# every snapshot rather than only when an entity spawns.
	view.apply_snapshot(_skinned_snapshot(1, 1, 0, "building.town_center"))
	assert_eq(view.pool.get_view(42).skin_age, 1)

	view.apply_snapshot(_skinned_snapshot(1, 2, 0, "building.town_center"))
	assert_eq(view.pool.get_view(42).skin_age, 2,
			"the node stays, the art behind it changes")


func test_a_snapshot_without_player_state_keeps_the_last_known_skin() -> void:
	# Plenty of tests (and the early ticks of a join) send entity updates with no
	# player_state. Clearing the skins there would strobe every unit back to
	# player 1's colour for a frame.
	view.apply_snapshot(_skinned_snapshot(1, 3, 6))
	view.apply_snapshot({"tick": 2, "updated": [{"id": 42, "def_id": "unit.villager",
			"owner_id": 1, "hp": 10, "max_hp": 10, "pos": {"x": 0, "y": 0}}], "removed": []})
	assert_eq(view.pool.get_view(42).skin_colour, 6)


func test_the_skin_is_read_before_the_entities_that_use_it() -> void:
	# An entity spawning this tick resolves its atlas the first time it draws. If
	# player_state were read after the entity loop, that first resolve would use
	# a stale skin -- one frame of the wrong player's colour, which is the whole
	# of what tells players apart.
	view.apply_snapshot(_skinned_snapshot(2, 4, 7))
	var v := view.pool.get_view(42)
	assert_eq(v.skin_colour, 7,
			"a brand-new entity already carries its owner's colour, not a default")


func test_age_of_reports_one_for_a_player_not_in_the_snapshot() -> void:
	# The menus gate on this, and an age of 0 would offer nothing at all.
	assert_eq(view.age_of(99), 1)
	view.apply_snapshot(_skinned_snapshot(3, 4, 1))
	assert_eq(view.age_of(3), 4)
	assert_eq(view.age_of(0), 1, "gaia reads as age 1, not as age 0")

func test_the_queued_def_ids_arrive_as_stringnames_not_strings() -> void:
	# JSON has no StringName, so anything off the wire is a String -- and
	# `&"unit.villager" == "unit.villager"` is FALSE in GDScript, so a missed
	# conversion here is a portrait lookup that silently finds nothing.
	view.apply_snapshot({
		"tick": 1,
		"updated": [{"id": 3, "def_id": "building.town_center", "owner_id": 1,
				"hp": 10, "max_hp": 10, "pos": {"x": 0, "y": 0},
				"footprint": {"x": 4, "y": 4}, "phase": SimBuilding.Phase.COMPLETE,
				"queue_len": 2, "queue_fraction": 0.5,
				"queue": ["unit.villager", "unit.militia"]}],
		"removed": [],
	})
	var queue: Array = view.facts_for(3)["queue"]
	assert_eq(queue.size(), 2)
	assert_eq(queue[0], &"unit.villager")
	assert_true(queue[0] is StringName, "compares equal to the StringName literals downstream")


func test_an_entry_with_no_queue_reads_as_an_empty_one() -> void:
	# Units and resource nodes never carry a queue, and neither does a building
	# from an older host. Absent must mean empty rather than break the lookup.
	view.apply_snapshot({"tick": 1, "updated": [{"id": 4, "def_id": "unit.villager",
			"pos": {"x": 0, "y": 0}}], "removed": []})
	assert_eq(view.facts_for(4)["queue"], [] as Array[StringName])

func test_age_progress_is_the_one_place_the_ticks_become_a_fraction() -> void:
	view.apply_snapshot({
		"tick": 1, "updated": [], "removed": [],
		"player_state": {1: {"age": 1, "colour": 0,
				"advancing_to": 2, "advance_ticks": 25, "advance_total_ticks": 100}},
	})
	assert_almost_eq(view.age_progress_of(1), 0.25, 0.001)
	assert_true(view.is_advancing(1))
	assert_eq(view.age_of(1), 1, "still the old age until the research lands")


func test_a_player_who_is_not_advancing_reports_no_progress() -> void:
	view.apply_snapshot({
		"tick": 1, "updated": [], "removed": [],
		"player_state": {1: {"age": 3, "colour": 0,
				"advancing_to": 0, "advance_ticks": 0, "advance_total_ticks": 0}},
	})
	assert_almost_eq(view.age_progress_of(1), 0.0, 0.001)
	assert_false(view.is_advancing(1))


func test_progress_for_an_unknown_player_is_zero_rather_than_a_divide_by_zero() -> void:
	assert_almost_eq(view.age_progress_of(99), 0.0, 0.001)
	assert_false(view.is_advancing(99))