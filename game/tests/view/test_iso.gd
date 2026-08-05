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
