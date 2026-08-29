## Phase 0.6: apply_snapshot() is the only thing standing between a wire
## Dictionary (PLAN.md 7.2) and pooled views -- test it directly rather than
## the JSON snapshot format.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# _ready() (which parents pool, terrain and fog under view) only runs once a node
	# enters a tree, which never happens for a bare .new() in a headless test --
	# so each is a separate orphan and must be freed on its own. Forgetting the fog
	# one showed up immediately as "88 RIDs of type CanvasItem were leaked" at the end
	# of the suite.
	view.pool.free()
	view.terrain.free()
	view.fog.free()
	view.spent.free()
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

## One `updated` entry. Split out from `_snapshot_of` below so a test can put SEVERAL
## entities in one snapshot, which since 2.5 is the only way to have several at once:
## anything a snapshot does not mention is treated as no longer visible.
func _entry(id: int, def_id: String, tile: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var entry := {"id": id, "def_id": def_id, "hp": 10, "max_hp": 10,
			"pos": {"x": tile.x * SimWorld.SUBTILE, "y": tile.y * SimWorld.SUBTILE}}
	entry.merge(extra)
	return entry


func _snapshot_of(id: int, def_id: String, tile: Vector2i, extra: Dictionary = {}) -> Dictionary:
	return {"tick": 1, "updated": [_entry(id, def_id, tile, extra)], "removed": []}


func test_a_building_sorts_by_its_front_tile_but_draws_on_its_centre() -> void:
	# The 2.6 defect: an 8x8 town centre sorted as though it stood on its middle
	# tile, so villagers on the near side drew over its roof. The node has to sit
	# further down the screen than the sprite does.
	var centre := Vector2i(10, 10) * SimWorld.SUBTILE
	view.apply_snapshot(_snapshot_of(1, "building.market", Vector2i(10, 10),
			{"phase": SimBuilding.Phase.COMPLETE}))

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


## THE TELEPORT (project owner, 2026-08-20).
##
## A unit stepping into the band in front of a building gains
## `_ADJACENT_TO_BUILDING_BONUS` on the position it SORTS at, and `draw_offset`
## cancels it so the art does not move. But the position is interpolated and the
## offset is not, so for one window the two did not cancel and the sprite was
## drawn 100,000 px up-screen, sliding back in from the edge on the next frames.
##
## Asserted as the invariant rather than at one hand-picked tile: whenever the
## offset changes, the unit must be DRAWN where it stands, on that very frame.
func test_a_unit_is_drawn_where_it_stands_on_the_tick_its_sort_band_changes() -> void:
	var building := {"id": 1, "def_id": "building.market",
			"phase": SimBuilding.Phase.COMPLETE,
			"pos": {"x": 10 * SimWorld.SUBTILE, "y": 10 * SimWorld.SUBTILE}}

	# The 8x8 centred on tile (10,10) claims tiles 6..13 on both axes, so the band
	# in front of it on this row is x = 14 -- adjacency is orthogonal, which a
	# diagonal approach never satisfies. Start clear of it to the east, so the view
	# already exists and is not treated as new.
	view.apply_snapshot({"tick": 1, "updated": [building,
		{"id": 2, "def_id": "unit.villager",
			"pos": {"x": 20 * SimWorld.SUBTILE, "y": 10 * SimWorld.SUBTILE}}],
		"removed": []})

	var v := view.pool.get_view(2)
	var previous := v.draw_offset
	var crossings := 0

	# Walk it in along the row, a tile at a time, across the band.
	for step in range(19, 11, -1):
		var stood := Vector2i(step, 10) * SimWorld.SUBTILE
		view.apply_snapshot({"tick": 21 - step, "updated": [building,
			{"id": 2, "def_id": "unit.villager", "pos": {"x": stood.x, "y": stood.y}}],
			"removed": []})
		if v.draw_offset != previous:
			crossings += 1
			assert_almost_eq((v.position + v.draw_offset).y, Iso.sub_to_world(stood).y, 0.01,
					"drawn where it stands on the tick the sort band changed (tile %d)" % step)
			assert_almost_eq((v.position + v.draw_offset).x, Iso.sub_to_world(stood).x, 0.01,
					"and on the x axis too (tile %d)" % step)
		previous = v.draw_offset

	assert_true(crossings > 0, "the walk crossed the sort band at least once")


func test_a_unit_in_front_of_a_building_sorts_after_it() -> void:
	# The assertion the whole fix exists for, stated the way the engine reads it:
	# Y-sort draws larger position.y last, so "in front" must mean "greater y".
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "building.market",
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
		{"id": 1, "def_id": "building.house",
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
		{"id": 1, "def_id": "building.market",
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
		{"id": 1, "def_id": "building.market",
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


# ── a resource node hides things too (project owner, 2026-08-17) ───────────

func test_a_unit_behind_a_gold_seam_is_outlined() -> void:
	# Only BUILDINGS were ever occluders, so a villager walking behind a rock
	# vanished with no outline at all -- reported with a screenshot of two of the
	# enemy's soldiers and three of ours doing exactly that.
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "res.gold_mine", "owner_id": 0, "size_class": 2,
				"footprint": {"x": 4, "y": 4},
				"pos": {"x": 20 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
		# Three tiles west: behind the seam, well inside the 244 px sprite, and
		# outside the 3-tile band a building's footprint would have given it.
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
				"pos": {"x": 17 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
	], "removed": []})

	assert_true(view.pool.get_view(2).occluded,
			"the villager behind the seam is hidden and gets a rim")


func test_a_unit_behind_a_TREE_is_outlined() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "res.tree", "owner_id": 0, "size_class": 1,
				"footprint": {"x": 1, "y": 1},
				"pos": {"x": 20 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
				"pos": {"x": 18 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
	], "removed": []})
	assert_true(view.pool.get_view(2).occluded)


func test_a_unit_in_front_of_a_node_is_not_outlined() -> void:
	# The directional half of the rule still holds for nodes: down-screen of the
	# rock is in front of it, and outlining that would be the roof-standing bug in
	# a new place.
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "res.gold_mine", "owner_id": 0, "size_class": 2,
				"footprint": {"x": 4, "y": 4},
				"pos": {"x": 20 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
				"pos": {"x": 22 * SimWorld.SUBTILE, "y": 22 * SimWorld.SUBTILE}},
	], "removed": []})
	assert_false(view.pool.get_view(2).occluded)


func test_a_small_seam_claims_a_narrower_band_than_a_large_one() -> void:
	# The pad is measured off the art the node will actually DRAW, so the three
	# gold size classes do not all behave like the biggest.
	# [size class, hidden?, footprint edge] -- the small seam claims one tile and
	# the large one claims 4x4, which is why they behave differently.
	for spec in [[0, false, 1], [2, true, 4]]:
		view.apply_snapshot({"tick": 1, "updated": [
			{"id": 1, "def_id": "res.gold_mine", "owner_id": 0, "size_class": spec[0],
					"footprint": {"x": spec[2], "y": spec[2]},
					"pos": {"x": 20 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
			{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
					"pos": {"x": 17 * SimWorld.SUBTILE, "y": 20 * SimWorld.SUBTILE}},
		], "removed": []})
		assert_eq(view.pool.get_view(2).occluded, spec[1],
				"size class %d hides a unit 3 tiles behind it: %s" % [spec[0], spec[1]])


func test_a_units_own_sort_is_not_lifted_in_front_of_a_tree() -> void:
	# Occluders grew to include nodes; the SORT LIFT deliberately did not. A unit
	# lifted in front of a one-tile tree would draw on top of its canopy, which is
	# the roof-standing bug the directional rule exists to prevent.
	# BOTH IN ONE SNAPSHOT, which is also what the server sends. Two sequential
	# single-entity snapshots used to work because nothing ever dropped a view the
	# snapshot stopped mentioning; since 2.5 that absence means "you cannot see it any
	# more" (GameView.apply_snapshot), so the second call would forget the tree.
	view.apply_snapshot({"tick": 1, "updated": [
		_entry(1, "res.tree", Vector2i(20, 20), {"size_class": 1, "footprint": {"x": 1, "y": 1}}),
		_entry(2, "unit.villager", Vector2i(21, 21)),
	], "removed": []})
	var tree := view.pool.get_view(1)
	var unit := view.pool.get_view(2)
	assert_true(unit.position.y > tree.position.y,
			"the unit in front sorts after the tree on its own, with no lift")


# ── interchangeable looks (visuals.json `variants`) ────────────────────────

func _field_snapshot(id: int, tile: Vector2i) -> Dictionary:
	return _snapshot_of(id, "building.field", tile,
			{"footprint": {"x": 6, "y": 6}, "phase": SimBuilding.Phase.COMPLETE})


func test_a_field_draws_one_of_the_four_plots() -> void:
	view.apply_snapshot(_field_snapshot(1, Vector2i(10, 10)))
	var chosen := String(view.pool.get_view(1).visual_id)
	assert_true(chosen.begins_with("vis.field_"),
			"%s is one of the plots, not the abstract vis.field" % chosen)


func test_the_same_plot_keeps_its_crop_across_snapshots() -> void:
	# Derived from the TILE, not rolled at spawn. A `randi()` would re-roll every
	# time a pooled view was recycled, so a field would change crop by walking the
	# camera away and back -- and two clients would disagree about a whole map.
	view.apply_snapshot(_field_snapshot(1, Vector2i(10, 10)))
	var first := view.pool.get_view(1).visual_id
	for tick in range(2, 6):
		view.apply_snapshot(_field_snapshot(1, Vector2i(10, 10)))
		assert_eq(view.pool.get_view(1).visual_id, first, "still the same crop on tick %d" % tick)


func test_neighbouring_plots_do_not_all_draw_the_same_crop() -> void:
	# Four fields round one mill is the arrangement this exists for. A seed that
	# gave them all the same plot would look exactly like variants not working.
	var seen: Array[String] = []
	var id := 1
	for tile in [Vector2i(10, 10), Vector2i(17, 10), Vector2i(10, 17), Vector2i(17, 17)]:
		view.apply_snapshot(_field_snapshot(id, tile))
		var vis := String(view.pool.get_view(id).visual_id)
		if not seen.has(vis):
			seen.append(vis)
		id += 1
	assert_true(seen.size() >= 2, "four adjacent plots drew %d different crops" % seen.size())


func test_a_foundation_is_not_given_a_crop() -> void:
	# The variant applies to whatever visual_for() returned, and a field being
	# ploughed is vis.foundation_6x6 -- which declares no variants, so it comes
	# back untouched. Worth pinning: the alternative is a foundation drawn as a
	# finished crop.
	view.apply_snapshot(_snapshot_of(1, "building.field", Vector2i(10, 10),
			{"footprint": {"x": 6, "y": 6}, "phase": SimBuilding.Phase.FOUNDATION}))
	assert_eq(view.pool.get_view(1).visual_id, &"vis.foundation_6x6")


func test_anything_without_variants_is_unaffected() -> void:
	view.apply_snapshot(_snapshot_of(1, "unit.villager", Vector2i(4, 4)))
	assert_eq(view.pool.get_view(1).visual_id, &"vis.villager")


func _tree_snapshot(id: int, tile: Vector2i) -> Dictionary:
	return _snapshot_of(id, "res.tree", tile, {"size_class": 1})


func test_a_view_told_which_map_it_is_on_draws_that_biomes_trees() -> void:
	# The owner's per-map assignment reaching the screen (2026-08-28). Trees are the
	# only user, and the pool is a VIEW fact: nothing about this rides the wire, and
	# the tile seed underneath is unchanged.
	view.variant_pool = &"desert"
	view.apply_snapshot(_tree_snapshot(1, Vector2i(10, 10)))
	var chosen := String(view.pool.get_view(1).visual_id)
	assert_true(["vis.tree_oak_dead", "vis.tree_elm_dead"].has(chosen),
			"%s is desert wood" % chosen)


func test_a_view_that_was_never_told_draws_the_general_mix() -> void:
	# The fixed debug map has no MapData to read a type off, and every preview and
	# test stands this view up directly. That case has to draw a tree, not the base id
	# and not a biome nobody chose.
	view.apply_snapshot(_tree_snapshot(1, Vector2i(10, 10)))
	var chosen := String(view.pool.get_view(1).visual_id)
	assert_true(["vis.tree", "vis.tree_elm", "vis.tree_toona"].has(chosen),
			"%s is one of the general three" % chosen)


func test_the_pool_changes_the_species_and_not_the_seed() -> void:
	# Two maps, one tile: the CHOICE inside each list must be the same index, because
	# the seed is a pure function of position and the pool only decides which list it
	# indexes into. Pinning this is what stops a future pool implementation quietly
	# introducing a second source of randomness -- which would be a desync the moment
	# two clients disagreed.
	var tile := Vector2i(13, 7)
	view.variant_pool = &"forest"
	view.apply_snapshot(_tree_snapshot(1, tile))
	var forest := String(view.pool.get_view(1).visual_id)
	view.variant_pool = &"island"
	view.apply_snapshot(_tree_snapshot(2, tile))
	var island := String(view.pool.get_view(2).visual_id)
	assert_true(forest.begins_with("vis.tree_"), "%s is a forest species" % forest)
	assert_true(island.begins_with("vis.tree_palm"), "%s is an island species" % island)


# ── idle villagers (7.1, the age header's badge) ───────────────────────────

func test_the_idle_count_is_villagers_only_and_only_the_owners() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.MOVE,
				"pos": {"x": 0, "y": 0}},
		{"id": 3, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.GATHER,
				"pos": {"x": 0, "y": 0}},
		# An idle SOLDIER is a garrison, not a mistake, and the badge is a button
		# that walks to whatever it counts -- this is the correction of 2026-08-17.
		{"id": 6, "def_id": "unit.knight", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		# A building must not be counted as a villager just because it too is idle.
		{"id": 4, "def_id": "building.town_center", "owner_id": 1,
				"footprint": {"x": 8, "y": 8}, "phase": SimBuilding.Phase.COMPLETE,
				"pos": {"x": 0, "y": 0}},
		# Someone else's villager must not show up in player 1's count.
		{"id": 5, "def_id": "unit.villager", "owner_id": 2, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
	], "removed": []})

	assert_eq(view.idle_villager_count(1), 1,
			"one idle villager -- not the busy two, the idle knight, the town centre or player 2's")


func test_the_idle_count_is_zero_with_nothing_in_view() -> void:
	assert_eq(view.idle_villager_count(1), 0)


# ── walking the idle ones (7.1, the badge's half) ──────────────────────────

## Player 1's villagers, of which 4 and 9 are idle, plus a busy one, a corpse and
## an idle knight -- and someone else's idle villager. Ids are deliberately out of
## insertion order: `_facts` is a Dictionary keyed in the order entities first
## appeared in a snapshot, so a walk that did not sort would visit them in join
## order.
func _idle_fixture() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 9, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		{"id": 6, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.GATHER,
				"pos": {"x": 0, "y": 0}},
		{"id": 4, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		{"id": 2, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"alive": false, "pos": {"x": 0, "y": 0}},
		{"id": 3, "def_id": "unit.knight", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
		{"id": 7, "def_id": "unit.villager", "owner_id": 2, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
	], "removed": []})


func test_idle_villager_ids_are_sorted_and_only_the_owners_living_idle_ones() -> void:
	_idle_fixture()
	assert_eq(view.idle_villager_ids(1), [4, 9] as Array[int],
			"ascending, no busy one, no corpse, no knight, nobody else's")


func test_the_idle_walk_visits_each_in_turn_and_then_wraps() -> void:
	_idle_fixture()
	assert_eq(view.next_idle_villager(1, 0), 4, "the first tap starts at the lowest id")
	assert_eq(view.next_idle_villager(1, 4), 9)
	assert_eq(view.next_idle_villager(1, 9), 4, "and round again rather than stopping")


func test_the_walk_carries_on_from_where_it_was_when_that_villager_gets_a_job() -> void:
	# The point of remembering an ID rather than an index: the player taps to id
	# 4, orders it to gather, and taps again. 4 has left the list -- the next tap
	# must still go to 9 rather than back to the top.
	_idle_fixture()
	# 9 IS RESENT UNCHANGED, because since 2.5 a snapshot that stops mentioning an
	# entity is telling the client it can no longer see it -- so a second snapshot
	# carrying only the villager that changed would forget the one this test is about.
	# The host sends the whole visible cast every tick, which is what this now mirrors.
	view.apply_snapshot({"tick": 2, "updated": [
		{"id": 4, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.GATHER,
				"pos": {"x": 0, "y": 0}},
		{"id": 9, "def_id": "unit.villager", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
	], "removed": []})
	assert_eq(view.idle_villager_ids(1), [9] as Array[int])
	assert_eq(view.next_idle_villager(1, 4), 9)


func test_the_walk_asks_for_nothing_when_nobody_is_idle() -> void:
	assert_eq(view.next_idle_villager(1, 0), 0,
			"0 is 'no villager', which GameScene treats as a no-op")


func test_the_badges_count_and_the_walks_list_cannot_disagree() -> void:
	# Both go through _is_own_living_villager(): the number in the ring and the
	# units the taps visit are the same question asked twice, and a badge reading
	# 5 that walks to 4 villagers is a bug the player would have to count to spot.
	_idle_fixture()
	assert_eq(view.idle_villager_ids(1).size(), view.idle_villager_count(1))


## The definition is a gather rate, not the id `unit.villager` -- so a unit that
## does not exist in the roster at all is not silently counted as one.
func test_an_unknown_def_is_not_taken_for_a_villager() -> void:
	view.apply_snapshot({"tick": 1, "updated": [
		{"id": 1, "def_id": "unit.nonesuch", "owner_id": 1, "task": SimUnit.Task.IDLE,
				"pos": {"x": 0, "y": 0}},
	], "removed": []})
	assert_eq(view.idle_villager_count(1), 0)


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


func test_tapping_someone_elses_unit_with_a_movable_selection_attacks_it() -> void:
	# Was MOVE until 4.13, when there was nothing else it could mean. Tapping an
	# enemy is now the whole attack UI -- there is no targeting mode to enter.
	_snap([{"id": 1, "def_id": "unit.villager", "owner_id": 2, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.ATTACK)


func test_tapping_someone_elses_building_with_an_army_attacks_it_too() -> void:
	_snap([{"id": 1, "def_id": "building.house", "owner_id": 2, "pos": {"x": 0, "y": 0},
			"phase": SimBuilding.Phase.COMPLETE, "footprint": {"x": 4, "y": 4}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.ATTACK)


func test_tapping_an_enemy_with_nothing_selected_just_looks_at_it() -> void:
	# An enemy's portrait and health stay readable without an army in hand.
	_snap([{"id": 1, "def_id": "unit.villager", "owner_id": 2, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, false), GameView.TapAction.SELECT)


func test_a_tree_is_still_chopped_rather_than_shot() -> void:
	# Gaia owns both trees and (later) hostile wildlife, so the attack branch has
	# to sit behind the resource check or every gather order becomes an attack.
	_snap([{"id": 1, "def_id": "res.tree", "owner_id": 0, "pos": {"x": 0, "y": 0}}])
	assert_eq(view.tap_action(1, 1, true), GameView.TapAction.GATHER)


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


# ── a unit standing ON a building draws in front of it (owner, 2026-08-28) ───

func test_a_unit_inside_a_footprint_counts_as_in_front_of_it() -> void:
	# THE REPORT: "wolf renders behind the field i am unable to target it for attack."
	# `_in_front_of_any` HAD this case written -- `if r.has_point(tile): return true` --
	# and it sat below a guard that made it unreachable: `Occlusion.is_in_front` is
	# `tile.x >= r.end.x or tile.y >= r.end.y`, false for every tile inside the rect.
	var field := Rect2i(10, 10, 5, 5)
	assert_false(Occlusion.is_in_front(Vector2i(12, 12), field),
			"the guard that was swallowing it")
	assert_true(view._in_front_of_any(Vector2i(12, 12), [field] as Array[Rect2i]),
			"standing on it is in front of it")


func test_every_tile_of_a_walkable_footprint_draws_in_front() -> void:
	# Not just the middle: a wolf anywhere on the crop must be visible, and the north
	# edge is the corner the old `is_in_front` rule was most wrong about.
	var field := Rect2i(10, 10, 5, 5)
	for y in range(10, 15):
		for x in range(10, 15):
			assert_true(view._in_front_of_any(Vector2i(x, y), [field] as Array[Rect2i]),
					"(%d, %d) is on the field" % [x, y])


func test_a_unit_genuinely_behind_a_building_is_still_behind_it() -> void:
	# The roof-standing bug this guard was protecting against (2026-08-16). Touching
	# the north edge is adjacent and is BEHIND, and must stay that way -- the fix is
	# only about being inside the rect, not about relaxing the direction rule.
	var house := Rect2i(10, 10, 4, 4)
	assert_false(view._in_front_of_any(Vector2i(11, 9), [house] as Array[Rect2i]),
			"one tile north of it is behind it")
	assert_false(view._in_front_of_any(Vector2i(9, 11), [house] as Array[Rect2i]),
			"one tile west of it is behind it")
	assert_true(view._in_front_of_any(Vector2i(11, 14), [house] as Array[Rect2i]),
			"one tile south of it is in front")


func test_a_unit_on_a_field_is_not_reported_as_hidden_by_it() -> void:
	# `Occlusion.hides` already returns false for a tile inside the rect, and that
	# stays right: standing inside a footprint is not being hidden BY it. It is only
	# correct now that the unit is actually drawn in front -- before, the two rules
	# agreed the wolf was neither in front nor hidden, so it got no lift AND no
	# outline, which is why it vanished rather than being rimmed.
	assert_false(Occlusion.hides(Rect2i(10, 10, 5, 5), Vector2i(12, 12)))


# ── which clip a building draws (gates gained an `open` pose 2026-08-28) ──────

## `building.wall_wood_gate` and NOT `building.wall_gate`, which is not a def at all --
## `vis.wall_gate` is the age-1 ATLAS and nothing points at it, because the wood gate is
## `age_required: 2` and age 1 has no gate. The first version of this fixture used the
## visual id by mistake, `building()` returned null, and the test correctly reported
## static: a def id and a visual id are two namespaces (`game_data.gd:visual_for`) and
## this is what conflating them looks like.
func _gate_entry(locked: bool, phase: int = SimBuilding.Phase.COMPLETE) -> Dictionary:
	return {"id": 1, "def_id": &"building.wall_wood_gate", "owner_id": 1,
			"phase": phase, "gate_locked": locked, "facing": 0}


func test_an_open_gate_draws_its_open_clip() -> void:
	assert_eq(view._building_anim(_gate_entry(false)), AtlasEntry.OPEN_ANIM)


func test_a_locked_gate_draws_static_which_IS_the_closed_pose() -> void:
	# The art side's design, and the reason no atlas needed a `closed` clip: a gate at
	# rest is shut, so an atlas with only `static` draws the right thing untouched.
	assert_eq(view._building_anim(_gate_entry(true)), AtlasEntry.STATIC_ANIM)


func test_an_ordinary_building_never_asks_for_an_open_clip() -> void:
	# THE TRAP THIS EXISTS FOR. `gate_locked` rides EVERY building entry and defaults
	# false, so a check of `not gate_locked` alone would ask every house, tower and town
	# centre in the game for a clip none of them has. `is_gate` off the def is what
	# separates them, and nothing else on the wire can.
	for def_id in [&"building.house", &"building.town_center", &"building.wall_long"]:
		var entry := _gate_entry(false)
		entry["def_id"] = def_id
		assert_eq(view._building_anim(entry), AtlasEntry.STATIC_ANIM, String(def_id))


func test_a_gate_under_construction_is_a_building_site_not_an_open_gate() -> void:
	# It resolves to a `vis.foundation_*` atlas, which has no `open` clip, so
	# `resolve_anim` would fall back and draw the right thing regardless -- this pins
	# the intent rather than leaning on that.
	for phase in [SimBuilding.Phase.FOUNDATION, SimBuilding.Phase.UNDER_CONSTRUCTION]:
		assert_eq(view._building_anim(_gate_entry(false, phase)), AtlasEntry.STATIC_ANIM)


func test_an_unknown_def_falls_back_rather_than_erroring() -> void:
	# A remembered entity or a def renamed in one file and not the other. `building()`
	# returns null and the seam's rule is that nothing blocks on missing data.
	var entry := _gate_entry(false)
	entry["def_id"] = &"building.does_not_exist"
	assert_eq(view._building_anim(entry), AtlasEntry.STATIC_ANIM)


func test_every_gate_def_actually_has_the_clip_its_atlas_is_asked_for() -> void:
	# Ties the DATA to the ART: `is_gate` in buildings.json against an `open` clip in
	# the staged atlas. Skipped entirely when the art pack is not mounted, because a
	# clean checkout has no atlases at all (they are gitignored build output) and
	# every id would resolve to a placeholder.
	# EVERY AGE, not just the base atlas. The wood gate is the reason: its skin map
	# points ages 1-2 at the German palisade gate and 3-4 at the Roman siege one, so a
	# check of `def.visual` alone would look at one of the two files and miss the other
	# entirely. Buildings carry the age (PLAN.md 2.7.1), and a gate is a building.
	var gates := 0
	var checked := 0
	for def_id in GameDataRegistry.building_ids():
		var def: BuildingDef = GameDataRegistry.building(def_id)
		if def == null or not def.is_gate:
			continue
		gates += 1
		for age in [1, 2, 3, 4]:
			var entry: AtlasEntry = GameDataRegistry.atlas_for(def.visual, age)
			if entry.is_placeholder:
				continue
			checked += 1
			assert_true(entry.has_anim(AtlasEntry.OPEN_ANIM),
					"%s age %d (%s) has an open clip" % [def_id, age, def.visual])
			assert_true(entry.has_anim(AtlasEntry.STATIC_ANIM),
					"%s age %d keeps static as its closed pose" % [def_id, age])
	assert_eq(gates, 3, "three gate defs -- one per wall tier above age 1")
	if checked > 0:
		assert_eq(checked, 12, "and all four ages of each were reached")


# ── the selection ring's shape and size (owner report, 2026-08-29) ──────────

## "the green circle when selecting units don't look good on buildings. replace the
## green circle with one tracing the footprint square."
func test_a_building_gets_a_square_ring_sized_from_its_footprint() -> void:
	view.apply_snapshot(_snapshot_of(1, "building.house", Vector2i(10, 10),
			{"phase": SimBuilding.Phase.COMPLETE}))
	var v := view.pool.get_view(1)
	assert_true(v.ring_square, "traced, not an ellipse")

	var def: BuildingDef = GameDataRegistry.building(&"building.house")
	assert_eq(v.ground_m, Vector2(def.footprint) * Iso.METRES_PER_TILE,
			"the SIM's rect -- the tiles it stands on and refuses to be built over")


func test_a_unit_keeps_the_round_ring_and_its_measured_size() -> void:
	# The other half of the split, and the reason it is a split: a villager occupies a
	# vague measured 0.6 m of ground, not the whole tile she is standing on, and a ring
	# the size of the tile would be three times too big.
	view.apply_snapshot(_snapshot_of(2, "unit.villager", Vector2i(4, 6)))
	var v := view.pool.get_view(2)
	assert_false(v.ring_square)
	assert_eq(v.ground_m, Vector2.ZERO, "which means: ask the visual's own placeholder")


func test_a_foundation_is_already_traced_at_the_size_it_will_finish_at() -> void:
	# A foundation holds the finished building's ground from the moment it is placed --
	# it is the same footprint the placement ghost was drawn at a tick earlier.
	view.apply_snapshot(_snapshot_of(3, "building.house", Vector2i(20, 20),
			{"phase": SimBuilding.Phase.FOUNDATION}))
	var v := view.pool.get_view(3)
	assert_true(v.ring_square)
	assert_eq(v.ground_m,
			Vector2(GameDataRegistry.building(&"building.house").footprint) * Iso.METRES_PER_TILE)


func test_a_north_south_wall_is_traced_on_its_transposed_footprint() -> void:
	# The case that used to be the ONLY one sized from the footprint (2026-08-22): a
	# wall's art is baked east-west, so a piece dragged the other way claims the
	# transpose of what `visuals.json` declares, and a ring built from the placeholder
	# sprawled the long way across open grass.
	var def_id := &"building.wall_wood_long"
	var def: BuildingDef = GameDataRegistry.building(def_id)
	assert_ne(def.footprint.x, def.footprint.y, "a wall segment is a long thin rect")

	view.apply_snapshot(_snapshot_of(4, String(def_id), Vector2i(30, 30),
			{"phase": SimBuilding.Phase.COMPLETE,
			"facing": WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y]}))
	var v := view.pool.get_view(4)
	assert_eq(v.ground_m,
			Vector2(def.footprint.y, def.footprint.x) * Iso.METRES_PER_TILE,
			"turned with the drag, not left at the axis the art was baked on")