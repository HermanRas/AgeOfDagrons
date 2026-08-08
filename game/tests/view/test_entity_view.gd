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
