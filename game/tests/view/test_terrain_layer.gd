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
