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
	assert_true(Iso.depth_sort_key(Iso.tile_centre_to_world(Vector2i(5, 5)))
			> Iso.depth_sort_key(Iso.tile_centre_to_world(Vector2i(1, 1))))


# ── tile centres vs tile corners (3.1) ─────────────────────────────────────

func test_a_tiles_centre_is_where_the_sim_stands_an_entity_on_it() -> void:
	# spawn_unit() places a unit at `tile * SUBTILE + SUBTILE/2`, so tile_to_world()
	# -- which matches sub_to_world at exact multiples -- is the tile's CORNER.
	# Drawing terrain there instead of at the centre is a half-tile error, which is
	# invisible on uniform grass and obvious where two terrains meet.
	var t := Vector2i(6, 2)
	var stood_on := t * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE / 2, SimWorld.SUBTILE / 2)
	assert_eq(Iso.tile_centre_to_world(t), Iso.sub_to_world(stood_on))
	assert_ne(Iso.tile_centre_to_world(t), Iso.tile_to_world(t),
			"centre and corner are different points")


func test_a_tile_centre_is_half_a_tile_below_its_corner() -> void:
	var t := Vector2i(3, 3)
	var delta := Iso.tile_centre_to_world(t) - Iso.tile_to_world(t)
	assert_almost_eq(delta.x, 0.0, 0.001, "the centre is straight down from the corner")
	assert_almost_eq(delta.y, Iso.TILE_SIZE.y / 2.0, 0.001)


# ── footprint depth sorting (3.1) ──────────────────────────────────────────

func test_a_one_tile_footprint_needs_no_sort_offset() -> void:
	# Units and resource nodes must be completely unaffected by the building fix.
	assert_eq(Iso.footprint_sort_offset(Vector2i.ONE), Vector2.ZERO)
	assert_eq(Iso.footprint_sort_offset(Vector2i.ZERO), Vector2.ZERO,
			"a degenerate footprint is treated as 1x1 rather than pulled off-screen")


func test_a_footprint_sorts_from_its_front_tile() -> void:
	# The offset must land exactly on the centre of tile (origin + footprint - 1),
	# because that is the ground a unit has to stand in front of to occlude the
	# building. Checked against Iso's own projection of that tile rather than a
	# recomputed formula, so the two cannot drift.
	var origin := Vector2i(10, 10)
	for footprint in [Vector2i(8, 8), Vector2i(4, 4), Vector2i(3, 5)]:
		var centre_sub := SimBuilding.centre_of(origin, footprint)
		var sorted_at := Iso.sub_to_world(centre_sub) + Iso.footprint_sort_offset(footprint)
		var front_tile: Vector2i = origin + footprint - Vector2i.ONE
		assert_almost_eq(sorted_at.x, Iso.tile_centre_to_world(front_tile).x, 0.01,
				"%s sorts at its front tile" % footprint)
		assert_almost_eq(sorted_at.y, Iso.tile_centre_to_world(front_tile).y, 0.01,
				"%s sorts at its front tile" % footprint)


func test_a_bigger_footprint_sorts_further_forward() -> void:
	assert_true(Iso.footprint_sort_offset(Vector2i(8, 8)).y
			> Iso.footprint_sort_offset(Vector2i(4, 4)).y,
			"a town centre reaches further toward the camera than a house")


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


## THE SEAM THE FACING BUG LIVED IN (project owner, 2026-08-20).
##
## `SimUnit.facing_toward` and `AtlasEntry.FACINGS` were each pinned by their own
## tests and both were right; what nothing checked was the view feeding one into
## the other. It had been passing the sim's octant through unconverted, drawing
## the mirror of the correct sprite. This walks every tile direction through both
## conventions and asserts they land on the same facing.
func test_a_sim_facing_converts_to_the_sprite_that_points_the_same_way() -> void:
	for sprite in range(8):
		var dir: Vector2 = Iso.FACING_TILE_DIRS[sprite]
		var sim := SimUnit.facing_toward(Vector2i(dir))
		assert_eq(Iso.sim_facing_to_sprite(sim), sprite,
				"walking tile %v must draw the %s sprite, not %s"
				% [dir, AtlasEntry.FACINGS[sprite],
				AtlasEntry.FACINGS[Iso.sim_facing_to_sprite(sim)]])


func test_the_sprite_conversion_wraps_rather_than_going_negative() -> void:
	for facing in range(-8, 16):
		var sprite := Iso.sim_facing_to_sprite(facing)
		assert_true(sprite >= 0 and sprite < 8, "facing %d resolved in range" % facing)


func test_diagonal_facings_are_unit_length_and_ordered_around_the_compass() -> void:
	for facing in range(8):
		assert_almost_eq(Iso.facing_to_screen_dir(facing).length(), 1.0, 0.001,
				"facing %d is a unit vector" % facing)
	# SW is left of S; NE is right of N. Confirms the table turns one way
	# consistently rather than zig-zagging.
	assert_true(Iso.facing_to_screen_dir(1).x < 0.0, "SW is screen-left of S")
	assert_true(Iso.facing_to_screen_dir(5).x > 0.0, "NE is screen-right of N")
