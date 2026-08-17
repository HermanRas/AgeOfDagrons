## The fog of war as it is DRAWN (PLAN.md 2.5's FogLayer). The sim half is
## test_vision.gd; this is the overlay, the client's forgetting, and the minimap.
extends TestCase

var fog: FogOverlay


func before_each() -> void:
	fog = FogOverlay.new()
	fog.build(Vector2i(4, 4))


func after_each() -> void:
	fog.free()


## A 4x4 grid, all one state, with `overrides` applied as {Vector2i: Fog}.
func _grid(base: int, overrides: Dictionary = {}) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(16)
	bytes.fill(base)
	for tile in overrides:
		bytes[(tile as Vector2i).y * 4 + (tile as Vector2i).x] = overrides[tile]
	return bytes


func test_unseen_ground_is_covered_and_visible_ground_is_not() -> void:
	fog.apply(_grid(SimPlayer.Fog.UNSEEN, {Vector2i(1, 1): SimPlayer.Fog.VISIBLE}))
	assert_eq(fog.fog_at(Vector2i(0, 0)), SimPlayer.Fog.UNSEEN)
	assert_eq(fog.fog_at(Vector2i(1, 1)), SimPlayer.Fog.VISIBLE,
			"a visible tile is the ABSENCE of a cell -- the cheapest answer for the "
			+ "tiles a player spends the match looking at")


func test_explored_ground_gets_the_lighter_wash() -> void:
	fog.apply(_grid(SimPlayer.Fog.UNSEEN, {Vector2i(2, 3): SimPlayer.Fog.EXPLORED}))
	assert_eq(fog.fog_at(Vector2i(2, 3)), SimPlayer.Fog.EXPLORED)
	assert_true(FogOverlay.EXPLORED_COLOR.a < FogOverlay.UNSEEN_COLOR.a,
			"explored has to leave the terrain readable, or remembering it is pointless")


func test_a_cell_source_id_is_its_fog_state() -> void:
	# Same trick TerrainLayer plays with terrain kinds: no second mapping to drift.
	fog.apply(_grid(SimPlayer.Fog.EXPLORED))
	assert_eq(fog.get_cell_source_id(Vector2i(0, 0)), int(SimPlayer.Fog.EXPLORED))
	assert_eq(FogOverlay.SOURCE_UNSEEN, int(SimPlayer.Fog.UNSEEN))
	assert_eq(FogOverlay.SOURCE_EXPLORED, int(SimPlayer.Fog.EXPLORED))


func test_it_follows_the_fog_as_it_changes() -> void:
	fog.apply(_grid(SimPlayer.Fog.UNSEEN))
	assert_eq(fog.fog_at(Vector2i(1, 1)), SimPlayer.Fog.UNSEEN)

	fog.apply(_grid(SimPlayer.Fog.UNSEEN, {Vector2i(1, 1): SimPlayer.Fog.VISIBLE}))
	assert_eq(fog.fog_at(Vector2i(1, 1)), SimPlayer.Fog.VISIBLE, "a scout arrived")

	fog.apply(_grid(SimPlayer.Fog.UNSEEN, {Vector2i(1, 1): SimPlayer.Fog.EXPLORED}))
	assert_eq(fog.fog_at(Vector2i(1, 1)), SimPlayer.Fog.EXPLORED, "and moved on")


func test_an_empty_grid_means_no_fog_rather_than_a_black_map() -> void:
	# What a world with no fog sends (SimPlayer.vision), and what a test snapshot or a
	# pre-2.5 replay carries. Blacking the map out would be the worse failure.
	fog.apply(_grid(SimPlayer.Fog.UNSEEN))
	assert_eq(fog.fog_at(Vector2i(0, 0)), SimPlayer.Fog.UNSEEN)

	fog.apply(PackedByteArray())
	assert_eq(fog.fog_at(Vector2i(0, 0)), SimPlayer.Fog.VISIBLE, "cleared, not blacked out")


func test_a_short_grid_is_refused_rather_than_read_past() -> void:
	var short := PackedByteArray()
	short.resize(5)
	short.fill(SimPlayer.Fog.UNSEEN)
	fog.apply(short)
	assert_eq(fog.fog_at(Vector2i(3, 3)), SimPlayer.Fog.VISIBLE, "nothing drawn from bad data")


func test_rebuilding_drops_what_was_drawn() -> void:
	fog.apply(_grid(SimPlayer.Fog.UNSEEN))
	fog.build(Vector2i(4, 4))
	assert_eq(fog.fog_at(Vector2i(0, 0)), SimPlayer.Fog.VISIBLE)
	# And the diff cache went with it, or the first apply() after a rebuild would
	# decide nothing had changed and draw nothing at all.
	fog.apply(_grid(SimPlayer.Fog.UNSEEN))
	assert_eq(fog.fog_at(Vector2i(0, 0)), SimPlayer.Fog.UNSEEN)


func test_the_fog_tiles_tessellate_without_double_darkening_the_seams() -> void:
	# THE ONE THAT SEMI-TRANSPARENCY MADE MATTER. TerrainLayer has drawn placeholder
	# diamonds with this same scanline fill since 3.1, and an off-by-one at the tile
	# boundary would have been invisible there because those tiles are opaque -- one
	# more opaque pixel over another looks like the pixel. Blend the explored wash
	# twice on the same pixel and you get a darker diamond grid criss-crossing every
	# explored region, which is a rendering artefact the player would report as a bug
	# in the fog.
	#
	# The east neighbour sits half a tile right and half a tile down, so the two
	# diamonds share exactly one quadrant. Every pixel in it must be claimed by
	# precisely one of them: `both` means seams, `neither` means bright pinholes.
	var img := FogOverlay._diamond_texture(Color.WHITE).get_image()
	var w := img.get_width()
	var h := img.get_height()
	var both := 0
	var neither := 0
	for y in range(h / 2, h):
		for x in range(w / 2, w):
			var mine := img.get_pixel(x, y).a > 0.0
			var theirs := img.get_pixel(x - w / 2, y - h / 2).a > 0.0
			if mine and theirs:
				both += 1
			elif not mine and not theirs:
				neither += 1
	assert_eq(both, 0, "no pixel is washed by two tiles at once")
	assert_eq(neither, 0, "and none is left unwashed between them")


func test_the_overlay_lines_up_with_the_ground_it_covers() -> void:
	# Both layers align themselves against Iso rather than against each other, so a
	# mismatch here would be fog sitting half a tile off the terrain -- which reads as
	# a rendering bug anywhere but here.
	var terrain := TerrainLayer.new()
	var bytes := PackedByteArray()
	bytes.resize(16)
	bytes.fill(SimMap.Terrain.GRASS)
	terrain.build(Vector2i(4, 4), bytes)
	assert_eq(fog.position, terrain.position)
	assert_eq(fog.tile_set.tile_size, terrain.tile_set.tile_size)
	terrain.free()
