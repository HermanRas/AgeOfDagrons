## Phase 0.2b: EntityView's animation clock and its resolution through the seam.
##
## Interpolation and pooling are covered by test_entity_view_pool.gd. What is new
## here is that a view now has a frame clock and a resolved visual, and that the
## clock must be driven by advance() rather than by the node's own _process --
## same reason as the interpolation: one central driver, and drivable headless.
extends TestCase

var view: EntityView


func before_each() -> void:
	view = EntityView.new()


func after_each() -> void:
	view.free()


func test_a_view_resolves_its_visual_through_the_seam() -> void:
	view.visual_id = &"vis.villager"
	var vis := view.visual()
	assert_not_null(vis, "atlas_for never returns null")
	assert_eq(vis.id, &"vis.villager")


func test_changing_visual_id_drops_the_resolved_visual() -> void:
	# Pooled nodes get reused for different entity kinds, so a stale AtlasEntry
	# would draw a villager as a tree.
	view.visual_id = &"vis.villager"
	var first := view.visual()
	view.visual_id = &"vis.tree"
	assert_ne(view.visual(), first, "a new visual_id re-resolves")
	assert_eq(view.visual().id, &"vis.tree")


func test_an_unknown_visual_still_resolves_so_the_view_draws_something() -> void:
	view.visual_id = &"vis.nonexistent"
	assert_true(view.visual().is_placeholder)


## A 4-frame looping walk at 10 fps and a 1-frame static, built here rather than
## taken from the registry. The clock's behaviour must not depend on whether the
## art pack happens to be staged on this machine -- game/assets/atlases/ is
## gitignored, so a fresh clone resolves these IDs to placeholders and a machine
## that has baked resolves them to real atlases.
func _animated() -> AtlasEntry:
	var frames: Array = []
	for i in range(4):
		frames.append({"page": 0, "rect": [i * 10, 0, 10, 20], "anchor": [5.0, 19.0]})
	return AtlasEntry.from_atlas_dict(&"test.animated", {
		"pages": ["p.png"],
		"directions": {"table": [{"stored_index": 0, "flip_x": false}]},
		"anims": {
			"walk": {"fps": 10.0, "loop": true, "frames": 4, "first": 0},
			"die": {"fps": 10.0, "loop": false, "frames": 4, "first": 0},
		},
		"frames": frames,
	}, "res://tests/fixtures")


func test_a_single_frame_visual_never_advances() -> void:
	view.set_visual(AtlasEntry.from_placeholder(&"test.ph", PlaceholderSpec.unknown()))
	view.play_anim(&"walk", 0)
	for _i in range(30):
		view.advance(0.1)
	assert_eq(view.current_frame(), 0, "a one-frame visual stays on frame 0")


func test_a_looping_animation_advances_at_its_own_fps_and_wraps() -> void:
	view.set_visual(_animated())
	view.play_anim(&"walk", 0)
	assert_eq(view.current_frame(), 0, "starts at 0")

	view.advance(0.1)                        # 10 fps -> one frame per 0.1 s
	assert_eq(view.current_frame(), 1)
	view.advance(0.2)
	assert_eq(view.current_frame(), 3, "0.3 s in is frame 3 of 4")
	view.advance(0.1)
	assert_eq(view.current_frame(), 0, "a looping anim wraps rather than running off")


func test_a_non_looping_animation_holds_its_last_frame() -> void:
	# A death animation that wrapped would resurrect the corpse.
	view.set_visual(_animated())
	view.play_anim(&"die", 0)
	for _i in range(20):
		view.advance(0.1)
	assert_eq(view.current_frame(), 3, "clamps to the final frame and stays there")


func test_changing_animation_restarts_the_clock() -> void:
	view.set_visual(_animated())
	view.play_anim(&"walk", 0)
	view.advance(0.5)
	assert_ne(view.current_frame(), 0, "the clock was genuinely running")
	view.play_anim(&"die", 0)
	assert_eq(view.current_frame(), 0, "a new anim starts at its first frame")


func test_play_anim_records_facing() -> void:
	view.visual_id = &"vis.villager"
	view.play_anim(&"walk", 3)
	assert_eq(view.anim, &"walk")
	assert_eq(view.facing, 3)


func test_interpolation_still_works_now_that_advance_also_drives_the_clock() -> void:
	# advance() gained a responsibility; make sure it did not lose one.
	view.visual_id = &"vis.villager"
	view.position = Vector2.ZERO
	view.set_target_transform(Vector2(100, 0), 1)
	view.advance(EntityView.INTERP_SECONDS)
	assert_almost_eq(view.position.x, 100.0, 0.01)


# ── health dot and death (4.6, 4.7) ──────────────────────────────────────────

func test_set_health_dot_stores_the_fraction() -> void:
	view.set_health_dot(0.4)
	assert_almost_eq(view.health_pct, 0.4, 0.001)


func test_set_dead_marks_the_view_dead() -> void:
	assert_false(view.dead)
	view.set_dead(true)
	assert_true(view.dead)


func test_set_corpse_fade_drives_modulate_alpha() -> void:
	view.set_corpse_fade(0.25)
	assert_almost_eq(view.modulate.a, 0.25, 0.001)


# ── the selection ring (4.3), and its square for buildings ──────────────────

## Both shapes are drawn with `draw_polyline`, which does not close a loop for you.
## A ring with a gap in it is what forgetting that looks like, and it is invisible in
## a screenshot at phone zoom.
func test_both_ring_shapes_come_back_closed() -> void:
	for square in [false, true]:
		var pts := EntityView.ring_points(Vector2(4.0, 4.0), square)
		assert_eq(pts[0], pts[pts.size() - 1], "square=%s closes on itself" % square)


func test_a_square_ring_is_the_four_corners_of_the_footprint() -> void:
	# Not "four points somewhere near the right size" -- the SAME four points
	# PlacementGhost draws, so what the player was shown while placing is what they
	# get back when they select what they placed.
	var pts := EntityView.ring_points(Vector2(6.0, 4.0), true)
	assert_eq(pts.size(), 5, "four corners and the closing repeat")
	var expected := PlaceholderRenderer.footprint_points(Vector2(6.0, 4.0))
	for i in range(4):
		assert_eq(pts[i], expected[i], "corner %d" % i)


func test_a_round_ring_is_inscribed_in_the_square_one() -> void:
	# Which is why the square had to replace it on buildings rather than be drawn
	# alongside: the ellipse sits INSIDE the footprint, so a house's ring stopped
	# short of the ground the house actually holds on all four sides.
	var footprint := Vector2(8.0, 8.0)
	var corner := EntityView.ring_points(footprint, true)[1].length()
	for p in EntityView.ring_points(footprint, false):
		assert_true(p.length() <= corner + 0.001,
				"every point of the ellipse is within the square's corner reach")


func test_a_tiny_footprint_is_floored_to_a_ring_that_can_be_seen() -> void:
	# A villager's measured footprint is 0.6 m. The floor applies to both shapes --
	# it applied only to the ellipse when the ellipse was the only shape.
	var tiny := EntityView.ring_points(Vector2(0.1, 0.1), true)
	var floored := EntityView.ring_points(
			Vector2(EntityView.RING_MIN_METRES, EntityView.RING_MIN_METRES), true)
	assert_eq(tiny, floored, "sized up to the minimum rather than drawn at 0.1 m")


func test_ring_square_defaults_off_so_only_a_building_gets_one() -> void:
	# GameView turns it on, and only for a def the registry calls a building. A view
	# holds a VISUAL id and could not work that out for itself.
	assert_false(view.ring_square)
