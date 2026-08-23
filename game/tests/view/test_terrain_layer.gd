## Phase 3.1: the terrain grid rendered as a real TileMapLayer.
##
## The load-bearing assertion is that Godot's isometric tile placement and Iso's
## projection put a tile in the SAME place. Iso is meant to be the only grid
## <-> screen math in the project (PLAN.md 6.3), and a TileMapLayer brings its own;
## if the two disagree, terrain and the entities standing on it drift apart by an
## amount no unit test of either alone would notice.
extends TestCase

var layer: TerrainLayer


func before_each() -> void:
	layer = TerrainLayer.new()


func after_each() -> void:
	layer.free()


## A `size`-shaped grid of one terrain, with `patch` tiles overridden.
func _terrain(size: Vector2i, fill: int, patch: Dictionary = {}) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y)
	for i in range(bytes.size()):
		bytes[i] = fill
	for t in patch:
		var tile: Vector2i = t
		bytes[tile.y * size.x + tile.x] = patch[t]
	return bytes


# ── the transition blend (2026-08-23) ──────────────────────────────────────
#
# No new art: every transition is generated from the one diamond each terrain already
# ships, which is what keeps a future theme pack to one sprite per terrain.

func test_a_single_terrain_map_has_nothing_to_blend() -> void:
	layer.build(Vector2i(4, 4), _terrain(Vector2i(4, 4), SimMap.Terrain.GRASS))
	var blend := layer.blend_layer()
	assert_true(blend == null or blend.tile_set == null,
			"no transition layer where there is no transition")


func test_the_higher_terrain_reaches_over_the_lower_one() -> void:
	# Grass outranks water in BLEND_ORDER, so the cell lands on the WATER tile and
	# carries GRASS. The other way round, the sea would climb the beach.
	var size := Vector2i(4, 4)
	var t := _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(1, 1): SimMap.Terrain.WATER_SHALLOW})
	layer.build(size, t)
	var blend := layer.blend_layer()

	assert_eq(blend.get_cell_source_id(Vector2i(1, 1)), int(SimMap.Terrain.GRASS),
			"grass reaches onto the water tile")
	assert_eq(blend.get_cell_source_id(Vector2i(2, 2)), -1,
			"and the grass tiles get nothing back")


func test_the_mask_names_the_edges_the_neighbour_is_actually_on() -> void:
	# One water tile with grass on all four sides is mask 1111; a water tile in the
	# middle of a lake with grass on one side only names that one side.
	var size := Vector2i(5, 5)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(2, 2): SimMap.Terrain.WATER_SHALLOW}))
	# atlas x is `bits - 1`, so all four edges is column 14.
	assert_eq(layer.blend_layer().get_cell_atlas_coords(Vector2i(2, 2)),
			Vector2i(14, 0), "surrounded on four sides")

	# A 2x1 pond: the left tile has grass on three sides, not four -- its east
	# neighbour is the other water tile. Bit 1 is (1, 0), so the mask is 1101 = 13.
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(2, 2): SimMap.Terrain.WATER_SHALLOW,
			Vector2i(3, 2): SimMap.Terrain.WATER_SHALLOW}))
	assert_eq(layer.blend_layer().get_cell_atlas_coords(Vector2i(2, 2)),
			Vector2i(12, 0), "three sides, not the one facing its own water")


func test_the_ramp_is_opaque_at_the_shared_edge_and_gone_at_the_far_one() -> void:
	# THE ONE THAT WOULD BE SILENTLY BACKWARDS. A reversed ramp still blends, still
	# looks soft in a screenshot thumbnail, and puts every transition on the wrong
	# side of every boundary. Bit 0 is the neighbour at (0, -1), which projects
	# up-RIGHT, so the ramp must be solid on the diamond's north-east side.
	var ne := 1 << 0
	assert_almost_eq(layer._edge_alpha(0.5, -0.5, ne), 1.0, 0.01, "on the NE edge")
	assert_almost_eq(layer._edge_alpha(-0.5, 0.5, ne), 0.0, 0.01, "at the far SW point")
	assert_true(layer._edge_alpha(0.0, 0.0, ne) > 0.0, "and reaches the middle")


func test_two_edges_take_the_stronger_rather_than_the_sum() -> void:
	# Adding them would make a corner MORE opaque than either edge, which draws a
	# bright wedge exactly where two coastlines meet.
	var ne := 1 << 0
	var se := 1 << 1
	var both := ne | se
	for p in [Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.0, 0.0)]:
		var strongest: float = maxf(layer._edge_alpha(p.x, p.y, ne),
				layer._edge_alpha(p.x, p.y, se))
		assert_almost_eq(layer._edge_alpha(p.x, p.y, both), strongest, 0.001,
				"at %s" % p)


func test_the_blend_layer_inherits_this_layers_alignment() -> void:
	# It is a CHILD, so it already carries the iso offset. Aligning it again would
	# put every transition one tile off the ground it is meant to soften.
	var size := Vector2i(4, 4)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(1, 1): SimMap.Terrain.WATER_SHALLOW}))
	var blend := layer.blend_layer()
	assert_eq(blend.position, Vector2.ZERO)
	assert_eq(blend.get_parent(), layer)
	assert_eq(blend.tile_set.tile_size, Vector2i(Iso.TILE_SIZE))


func test_rebuilding_does_not_leave_stale_transitions_behind() -> void:
	var size := Vector2i(4, 4)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(1, 1): SimMap.Terrain.WATER_SHALLOW}))
	assert_true(layer.blend_layer().get_cell_source_id(Vector2i(1, 1)) != -1)

	layer.build(size, _terrain(size, SimMap.Terrain.GRASS))
	var blend := layer.blend_layer()
	assert_eq(blend.get_cell_source_id(Vector2i(1, 1)), -1, "the pond is gone")


# ── alignment with Iso ─────────────────────────────────────────────────────

func test_tiles_land_where_iso_projects_their_centres() -> void:
	var size := Vector2i(8, 8)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS))

	# Several tiles, not one: a constant offset would be absorbed by the layer's
	# own alignment shift, so only checking a spread catches a mismatch in SLOPE
	# -- a different tile size or layout convention.
	for t in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(3, 5), Vector2i(7, 7)]:
		var placed: Vector2 = layer.position + layer.map_to_local(t)
		var projected := Iso.tile_centre_to_world(t)
		assert_almost_eq(placed.x, projected.x, 0.01, "tile %s x" % t)
		assert_almost_eq(placed.y, projected.y, 0.01, "tile %s y" % t)


func test_the_tile_set_uses_the_iso_tile_size() -> void:
	layer.build(Vector2i(2, 2), _terrain(Vector2i(2, 2), SimMap.Terrain.GRASS))
	assert_eq(layer.tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC)
	assert_eq(layer.tile_set.tile_size, Vector2i(Iso.TILE_SIZE),
			"the tileset follows Iso.TILE_SIZE rather than restating it")


# ── painting ───────────────────────────────────────────────────────────────

func test_every_tile_is_painted_and_carries_its_terrain_as_the_source_id() -> void:
	var size := Vector2i(4, 3)
	var bytes := _terrain(size, SimMap.Terrain.GRASS, {
		Vector2i(0, 0): SimMap.Terrain.DIRT, Vector2i(3, 2): SimMap.Terrain.DIRT})
	layer.build(size, bytes)

	for y in range(size.y):
		for x in range(size.x):
			var t := Vector2i(x, y)
			assert_eq(layer.get_cell_source_id(t), int(bytes[y * size.x + x]),
					"%s is painted with its own terrain kind" % t)


func test_terrain_with_no_baked_atlas_still_paints() -> void:
	# The no-pack-mounted path (PLAN.md 3.2). `terrain.dirt` has no atlas and no
	# visuals.json entry yet (art track A.1), so it resolves to the loud unknown
	# placeholder -- but it must still produce a tile, or the map renders with
	# holes in it rather than with an obviously wrong colour.
	var size := Vector2i(2, 2)
	layer.build(size, _terrain(size, SimMap.Terrain.DIRT))
	assert_true(layer.tile_set.has_source(SimMap.Terrain.DIRT))
	assert_eq(layer.get_cell_source_id(Vector2i(1, 1)), int(SimMap.Terrain.DIRT))


func test_only_the_terrains_present_get_a_source() -> void:
	# A grass map should not build and hold five unused atlas textures.
	var size := Vector2i(3, 3)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS))
	assert_true(layer.tile_set.has_source(SimMap.Terrain.GRASS))
	assert_false(layer.tile_set.has_source(SimMap.Terrain.WATER_DEEP))


func test_rebuilding_replaces_the_previous_map() -> void:
	layer.build(Vector2i(8, 8), _terrain(Vector2i(8, 8), SimMap.Terrain.GRASS))
	layer.build(Vector2i(2, 2), _terrain(Vector2i(2, 2), SimMap.Terrain.GRASS))
	assert_eq(layer.size(), Vector2i(2, 2))
	assert_eq(layer.get_cell_source_id(Vector2i(7, 7)), -1,
			"tiles from the old map are gone, not left behind")


func test_a_short_or_empty_terrain_array_is_refused_rather_than_read_past() -> void:
	# A truncated map must not index out of bounds -- better an empty render than
	# a crash on a malformed payload.
	layer.build(Vector2i(4, 4), PackedByteArray([0, 0, 0]))
	assert_eq(layer.get_cell_source_id(Vector2i(0, 0)), -1)
	layer.build(Vector2i.ZERO, PackedByteArray())
	assert_eq(layer.get_used_rect().size, Vector2i.ZERO)


# ── the seam ───────────────────────────────────────────────────────────────

func test_grass_draws_its_baked_atlas_when_the_pack_is_staged() -> void:
	# Conditional on the pack, because game/assets/atlases/ is gitignored and a
	# fresh clone has none of it (the same reason test_visual_seam asserts on
	# declared placeholders rather than on files).
	if not GameDataRegistry.has_atlas(&"terrain.grass"):
		return
	layer.build(Vector2i(2, 2), _terrain(Vector2i(2, 2), SimMap.Terrain.GRASS))
	var source := layer.tile_set.get_source(SimMap.Terrain.GRASS) as TileSetAtlasSource
	assert_not_null(source)
	assert_true(source.texture is AtlasTexture,
			"the frame is lifted off its page rather than the page being gridded")
