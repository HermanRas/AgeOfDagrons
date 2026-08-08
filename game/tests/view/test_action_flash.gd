## PLAN.md 4.5: a brief marker at the tap target, coloured by which order the
## tap actually issued.
extends TestCase

var flash: ActionFlash


func before_each() -> void:
	flash = ActionFlash.new()


func after_each() -> void:
	flash.free()


func test_play_shows_it_at_full_opacity_on_the_target() -> void:
	flash.play(ActionFlash.Kind.MOVE, Vector2(120.0, 40.0))
	assert_eq(flash.position, Vector2(120.0, 40.0))
	assert_almost_eq(flash.modulate.a, 1.0, 0.001)
	assert_eq(flash.current_kind(), ActionFlash.Kind.MOVE)


func test_each_kind_is_remembered_for_drawing() -> void:
	flash.play(ActionFlash.Kind.GATHER, Vector2.ZERO)
	assert_eq(flash.current_kind(), ActionFlash.Kind.GATHER)
	flash.play(ActionFlash.Kind.BUILD, Vector2.ZERO)
	assert_eq(flash.current_kind(), ActionFlash.Kind.BUILD)


func test_not_in_a_tree_still_shows_it_without_crashing() -> void:
	# No tween can be scheduled without a tree (NoticeToast's own reasoning) --
	# the flash still snaps to its visible state.
	assert_false(flash.is_inside_tree())
	flash.play(ActionFlash.Kind.BUILD, Vector2(5.0, 5.0))
	assert_almost_eq(flash.modulate.a, 1.0, 0.001)


func test_a_later_flash_replaces_an_earlier_one() -> void:
	flash.play(ActionFlash.Kind.MOVE, Vector2(1.0, 1.0))
	flash.play(ActionFlash.Kind.GATHER, Vector2(2.0, 2.0))
	assert_eq(flash.current_kind(), ActionFlash.Kind.GATHER)
	assert_eq(flash.position, Vector2(2.0, 2.0))
