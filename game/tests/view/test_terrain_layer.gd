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
	# A lone water tile has grass on all four edges. Its four corners are grass too,
	# but every one of them is shadowed by an edge and drops out -- so the mask is
	# 0b1111 and not 0b11111111.
	var size := Vector2i(5, 5)
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(2, 2): SimMap.Terrain.WATER_SHALLOW}))
	assert_eq(layer.blend_mask_at(Vector2i(2, 2)), 0b1111, "surrounded on four sides")

	# A 2x1 pond. The left tile keeps three edges -- bit 1 is (1, 0), its own water --
	# and gains no corner, because the two corners on that side are water as well.
	layer.build(size, _terrain(size, SimMap.Terrain.GRASS,
			{Vector2i(2, 2): SimMap.Terrain.WATER_SHALLOW,
			Vector2i(3, 2): SimMap.Terrain.WATER_SHALLOW}))
	assert_eq(layer.blend_mask_at(Vector2i(2, 2)), 0b1101,
			"three sides, not the one facing its own water")


func test_a_terrain_touching_only_at_a_corner_still_blends() -> void:
	# THE DIAGONALS. Reported by the project owner against the first version, which
	# had edge bits only: a tile meeting another terrain at a single VERTEX got no
	# transition at all, so every step of a staircase boundary kept one hard point --
	# and the soft edges around it made that point more conspicuous, not less.
	#
	# A lake with one island tile of grass in it. Grass outranks water, so the water
	# tiles are the ones that receive -- and (2, 2) meets the grass at (3, 3) ONLY at
	# a corner, offset (1, 1). All four of its edges are water.
	var size := Vector2i(6, 6)
	layer.build(size, _terrain(size, SimMap.Terrain.WATER_SHALLOW,
			{Vector2i(3, 3): SimMap.Terrain.GRASS}))

	var mask := layer.blend_mask_at(Vector2i(2, 2))
	assert_eq(mask & 0b1111, 0, "no edge of it touches the grass")
	assert_true(mask != 0, "but the corner still produces a transition")
	assert_eq(layer.blend_layer().get_cell_source_id(Vector2i(2, 2)),
			int(SimMap.Terrain.GRASS), "and it is the grass reaching in")


func test_a_corner_is_dropped_when_its_own_edge_already_covers_it() -> void:
	# What keeps the strip at 47 columns rather than 256. An edge ramp is opaque all
	# the way to both its endpoints, so a corner beside a matching edge would draw
	# nothing new and only multiply the variants.
	assert_eq(TerrainLayer.canonical_mask(0b00010001), 0b00000001,
			"corner 0 sits between edges 0 and 1; edge 0 is set")
	assert_eq(TerrainLayer.canonical_mask(0b00010010), 0b00000010,
			"and edge 1 shadows it just as well")
	assert_eq(TerrainLayer.canonical_mask(0b00010000), 0b00010000,
			"but with neither edge, the corner survives")


func test_there_are_forty_seven_distinct_transitions() -> void:
	# The classic blob count, arrived at here for the reason it exists everywhere:
	# four edges free, and a corner only meaningful where neither of its edges is.
	var seen: Dictionary = {}
	for bits in range(1 << 8):
		seen[TerrainLayer.canonical_mask(bits)] = true
	assert_eq(seen.size(), 47, "46 drawable plus the empty mask")


func test_the_ramp_is_opaque_at_the_shared_edge_and_gone_at_the_far_one() -> void:
	# THE ONE THAT WOULD BE SILENTLY BACKWARDS. A reversed ramp still blends, still
	# looks soft in a screenshot thumbnail, and puts every transition on the wrong
	# side of every boundary. Bit 0 is the neighbour at (0, -1), which projects
	# up-RIGHT, so the ramp must be solid on the diamond's north-east side.
	var ne := 1 << 0
	assert_almost_eq(layer._edge_alpha(0.5, -0.5, ne), 1.0, 0.01, "on the NE edge")
	assert_almost_eq(layer._edge_alpha(-0.5, 0.5, ne), 0.0, 0.01, "at the far SW point")
	assert_true(layer._edge_alpha(0.0, 0.0, ne) > 0.0, "and reaches the middle")


func test_a_corner_ramp_peaks_at_its_vertex_and_not_along_a_side() -> void:
	# Corner 0 is between edges 0 (NE) and 1 (SE), i.e. the diamond's RIGHT point.
	# If this behaved like an edge it would wash along a whole side and the corner
	# fix would look like a smear rather than a rounded cap.
	var corner := 1 << TerrainLayer.CORNER_BIT
	assert_almost_eq(layer._edge_alpha(1.0, 0.0, corner), 1.0, 0.01, "at the vertex")
	assert_almost_eq(layer._edge_alpha(-1.0, 0.0, corner), 0.0, 0.01, "opposite it")
	# The two vertices either side of it are the ends of the adjacent edges, and a
	# corner cap must have fallen well off by the time it reaches them.
	assert_true(layer._edge_alpha(0.0, -1.0, corner) < 0.5, "not up at the top point")
	assert_true(layer._edge_alpha(0.0, 1.0, corner) < 0.5, "nor down at the bottom")


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
