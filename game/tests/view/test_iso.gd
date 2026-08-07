## Phase 0.6: Iso is the only place grid<->screen math lives (PLAN.md 6.3) --
## worth pinning down with a round-trip test before anything renders through it.
extends TestCase

func test_tile_to_world_round_trips_through_world_to_tile() -> void:
	for t in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 5), Vector2i(4, 7), Vector2i(-2, 6)]:
		var w := Iso.tile_to_world(t)
		assert_eq(Iso.world_to_tile(w), t, "round trip for %s" % t)


func test_sub_to_world_matches_tile_to_world_at_tile_boundaries() -> void:
	var t := Vector2i(6, 2)
	var sub := t * SimWorld.SUBTILE
	assert_eq(Iso.sub_to_world(sub), Iso.tile_to_world(t))


func test_sub_to_world_is_between_neighbouring_tiles_mid_step() -> void:
	var a := Iso.tile_to_world(Vector2i(0, 0))
	var b := Iso.tile_to_world(Vector2i(2, 0))
	var mid := Iso.sub_to_world(Vector2i(SimWorld.SUBTILE, 0))
	assert_almost_eq(mid.x, (a.x + b.x) / 2.0, 0.01)
	assert_almost_eq(mid.y, (a.y + b.y) / 2.0, 0.01)


func test_depth_sort_key_increases_toward_bottom_of_map() -> void:
	assert_true(Iso.depth_sort_key(Vector2i(5, 5)) > Iso.depth_sort_key(Vector2i(1, 1)))


# ── phase 0.2b: metre-space projection, used by the placeholder renderer ────

func test_pixels_per_metre_is_consistent_with_tile_size() -> void:
	# PIXELS_PER_METRE is a hardcoded constant so it can be a `const`, but it is
	# DERIVED from TILE_SIZE and METRES_PER_TILE. If someone changes the tile and
	# not the constant, every atlas silently renders at the wrong scale -- which
	# is exactly the class of bug that got vis.villager (PLAN.md 13.2). Recompute
	# it here so the two cannot drift apart unnoticed.
	var horizontal_px_per_m := Iso.TILE_SIZE.x / (2.0 * Iso.METRES_PER_TILE)
	assert_almost_eq(Iso.PIXELS_PER_METRE, horizontal_px_per_m / cos(PI / 4.0), 0.001,
			"PIXELS_PER_METRE must follow from TILE_SIZE")
	assert_almost_eq(Iso.ELEVATION_RAD, asin(Iso.TILE_SIZE.y / Iso.TILE_SIZE.x), 0.0001,
			"elevation is derived from the tile aspect, not configured")
	assert_almost_eq(Iso.VERTICAL_PX_PER_METRE,
			Iso.PIXELS_PER_METRE * cos(Iso.ELEVATION_RAD), 0.001)


func test_one_tile_of_metres_projects_to_one_tile() -> void:
	var by_metres := Iso.metres_to_world(Vector2(Iso.METRES_PER_TILE, 0.0))
	assert_almost_eq(by_metres.x, Iso.TILE_SIZE.x / 2.0, 0.01)
	assert_almost_eq(by_metres.y, Iso.TILE_SIZE.y / 2.0, 0.01)


func test_height_projects_upward_and_scales_linearly() -> void:
	assert_true(Iso.height_to_world(3.0).y < 0.0, "height moves up the screen")
	assert_almost_eq(Iso.height_to_world(2.0).y, 2.0 * Iso.height_to_world(1.0).y, 0.001)
	assert_almost_eq(Iso.height_to_world(0.0).y, 0.0)


func test_the_eight_facings_point_the_way_their_names_say() -> void:
	# Screen y grows downward, so S is +y and N is -y. Getting this table wrong
	# means units walk one way and face another, so it is worth pinning per facing
	# rather than trusting the array literal.
	var expected := {
		0: Vector2(0, 1),    # S
		2: Vector2(-1, 0),   # W
		4: Vector2(0, -1),   # N
		6: Vector2(1, 0),    # E
	}
	for facing in expected:
		var dir := Iso.facing_to_screen_dir(facing)
		assert_almost_eq(dir.x, expected[facing].x, 0.01,
				"%s points x" % AtlasEntry.FACINGS[facing])
		assert_almost_eq(dir.y, expected[facing].y, 0.01,
				"%s points y" % AtlasEntry.FACINGS[facing])


func test_diagonal_facings_are_unit_length_and_ordered_around_the_compass() -> void:
	for facing in range(8):
		assert_almost_eq(Iso.facing_to_screen_dir(facing).length(), 1.0, 0.001,
				"facing %d is a unit vector" % facing)
	# SW is left of S; NE is right of N. Confirms the table turns one way
	# consistently rather than zig-zagging.
	assert_true(Iso.facing_to_screen_dir(1).x < 0.0, "SW is screen-left of S")
	assert_true(Iso.facing_to_screen_dir(5).x > 0.0, "NE is screen-right of N")
