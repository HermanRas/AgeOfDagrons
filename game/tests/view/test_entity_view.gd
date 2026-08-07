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


func test_a_placeholder_visual_never_advances_its_frame() -> void:
	# Nothing in visuals.json has art mounted yet, so this is the live path today:
	# a single inert frame, and a clock that must not run away.
	view.visual_id = &"vis.villager"
	view.play_anim(&"walk", 0)
	for _i in range(30):
		view.advance(0.1)
	assert_eq(view.current_frame(), 0, "a one-frame visual stays on frame 0")


func test_changing_animation_restarts_the_clock() -> void:
	view.visual_id = &"vis.villager"
	view.play_anim(&"walk", 0)
	view.advance(0.5)
	view.play_anim(&"idle", 0)
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
