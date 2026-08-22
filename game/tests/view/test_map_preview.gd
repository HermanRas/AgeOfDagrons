## The lobby's picture of a map (PLAN.md 1.6), and specifically the 45-degree turn
## `show_map` puts it through so that the lobby, the minimap and the match all stand
## the map on the same corner.
##
## The turn is the part worth testing, because it is the part that can be wrong in a
## way nobody sees: a preview rotated the wrong way round still looks like a map, and
## the only tell is that the start position a player picked is not where their town
## centre appears. So the tips are asserted against `Iso` itself rather than against
## a remembered picture -- if the projection is ever changed, this fails rather than
## the lobby quietly disagreeing with the camera again.
extends TestCase


## A map whose four tiles-of-interest are four different colours, so where each one
## ends up in the rotated image identifies which corner went where. Terrain only --
## entities and start rings are drawn by the same `_blot` and add nothing to test.
func _corner_map(size: Vector2i = Vector2i(8, 8)) -> MapData:
	var data := MapData.create(size, SimMap.Terrain.GRASS)
	data.set_terrain(Vector2i(0, 0), SimMap.Terrain.SAND)
	data.set_terrain(Vector2i(size.x - 1, 0), SimMap.Terrain.ROCK)
	data.set_terrain(Vector2i(0, size.y - 1), SimMap.Terrain.WATER_DEEP)
	data.set_terrain(Vector2i(size.x - 1, size.y - 1), SimMap.Terrain.WATER_SHALLOW)
	return data


func test_the_flat_picture_is_one_pixel_per_tile() -> void:
	var img := MapPreview.image(_corner_map())
	assert_eq(img.get_width(), 8)
	assert_eq(img.get_height(), 8)
	assert_eq(img.get_pixel(0, 0), MapPreview.C_SAND, "tile (0,0) is the top-left pixel")


func test_scale_is_for_the_dev_tools_png_and_multiplies_both_axes() -> void:
	var img := MapPreview.image(_corner_map(), 3)
	assert_eq(img.get_width(), 24)
	assert_eq(img.get_height(), 24)
	assert_eq(img.get_pixel(2, 2), MapPreview.C_SAND, "a tile is a 3x3 block of pixels")


func test_an_absent_or_empty_map_draws_nothing_rather_than_failing() -> void:
	assert_null(MapPreview.image(null), "no map, no picture")
	assert_null(MapPreview.image(MapData.create(Vector2i.ZERO)),
			"a zero-size map is not a 0x0 image")
	assert_null(MapPreview.to_diamond(null), "and the turn passes the nothing through")


# ── the 45-degree turn ─────────────────────────────────────────────────────

func test_the_diamond_is_the_flat_squares_bounding_box() -> void:
	var d := MapPreview.to_diamond(MapPreview.image(_corner_map()))
	assert_eq(d.get_width(), 16, "8 + 8 -- a square turned 45 degrees needs its diagonal")
	assert_eq(d.get_height(), 16)


func test_each_corner_tile_lands_on_the_tip_iso_would_put_it_on() -> void:
	# The whole point. `Iso._project` is not reachable from here, but `tile_to_world`
	# is exactly it, and the diamond is that projection with the y axis unsquashed --
	# so the ORDER of the four tips has to match, which is what could be inverted.
	var data := _corner_map()
	var d := MapPreview.to_diamond(MapPreview.image(data))
	var w := data.size.x
	var h := data.size.y

	# Tile (0,0) at the top, and it is the tile Iso projects highest on screen.
	assert_eq(d.get_pixel(h, 0), MapPreview.C_SAND, "tile (0,0) is the TOP tip")
	assert_eq(d.get_pixel(w + h - 1, w - 1), MapPreview.C_ROCK,
			"tile (w-1,0) is the RIGHT tip -- +x runs down-RIGHT, as Iso projects it")
	assert_eq(d.get_pixel(1, h - 1), MapPreview.C_DEEP,
			"tile (0,h-1) is the LEFT tip -- +y runs down-left")
	assert_eq(d.get_pixel(w, w + h - 2), MapPreview.C_WATER,
			"tile (w-1,h-1) is the BOTTOM tip")

	var top := Iso.tile_to_world(Vector2i.ZERO)
	var right := Iso.tile_to_world(Vector2i(w, 0))
	var left := Iso.tile_to_world(Vector2i(0, h))
	assert_true(right.x > top.x and right.y > top.y, "Iso agrees: +x is down and right")
	assert_true(left.x < top.x and left.y > top.y, "and +y is down and left")


func test_the_corners_outside_the_diamond_are_left_transparent() -> void:
	# The lobby panel shows through them, the same void the camera clamp leaves at
	# the corners of the real map. An opaque black square would read as ocean.
	var d := MapPreview.to_diamond(MapPreview.image(_corner_map()))
	for at in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
		assert_almost_eq(d.get_pixel(at.x, at.y).a, 0.0, 0.001,
				"%s is off the map" % at)


func test_the_turn_loses_no_tile() -> void:
	# Read inversely for exactly this reason: the forward map lands on every other
	# pixel, so a tile-by-tile draw sieves holes through the map. Every tile of a
	# uniform map must arrive, and nothing but the four corner regions may be empty.
	var data := _corner_map(Vector2i(9, 5))
	var d := MapPreview.to_diamond(MapPreview.image(data))
	var opaque := 0
	for y in range(d.get_height()):
		for x in range(d.get_width()):
			if d.get_pixel(x, y).a > 0.0:
				opaque += 1
	# A tile covers two pixels of a diamond whose area is half the bounding box.
	assert_eq(opaque, data.size.x * data.size.y * 2,
			"every tile arrives, and each covers the same area as every other")


func test_a_lopsided_map_stays_lopsided() -> void:
	# A 2:1 map must not come out square -- which is what a naive rotate-and-crop
	# would do, and it would misreport how far apart two start positions are.
	var d := MapPreview.to_diamond(MapPreview.image(_corner_map(Vector2i(16, 8))))
	assert_eq(d.get_width(), 24, "16 + 8")
	assert_eq(d.get_pixel(8, 0), MapPreview.C_SAND, "the top tip sits h across, not centred")
