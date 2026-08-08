## Phase 4.3 (tap/box) and 5.1 (single_pressed/single_drag_moved/single_released).
##
## Driven through synthetic InputEvents into _unhandled_input() -- this class IS
## the input plumbing, so there is no pure-math layer underneath it the way
## CameraRig has pan_by()/apply_drag() to test instead.
extends TestCase

var router: InputRouter


func before_each() -> void:
	router = InputRouter.new()


func after_each() -> void:
	router.free()


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	return t


func _drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	d.relative = relative
	return d


# ── the three signals PLAN.md 5.1 added ────────────────────────────────────

func test_single_pressed_fires_on_touch_down() -> void:
	var seen: Array[Vector2] = []
	router.single_pressed.connect(func(p: Vector2) -> void: seen.append(p))

	router._unhandled_input(_touch(0, Vector2(40, 50), true))

	assert_eq(seen, [Vector2(40, 50)])


func test_single_drag_moved_fires_for_each_step_of_a_one_finger_drag() -> void:
	var seen: Array[Vector2] = []
	router.single_drag_moved.connect(func(p: Vector2) -> void: seen.append(p))

	router._unhandled_input(_touch(0, Vector2(0, 0), true))
	router._unhandled_input(_drag(0, Vector2(30, 0), Vector2(30, 0)))
	router._unhandled_input(_drag(0, Vector2(60, 0), Vector2(30, 0)))

	assert_eq(seen, [Vector2(30, 0), Vector2(60, 0)])


func test_single_released_fires_on_release_even_far_past_tap_slop() -> void:
	var seen: Array[Vector2] = []
	router.single_released.connect(func(p: Vector2) -> void: seen.append(p))

	router._unhandled_input(_touch(0, Vector2(0, 0), true))
	router._unhandled_input(_drag(0, Vector2(200, 0), Vector2(200, 0)))   # well past TAP_SLOP
	router._unhandled_input(_touch(0, Vector2(200, 0), false))

	assert_eq(seen, [Vector2(200, 0)], "released fires for a drag, not just a tap")


func test_tapped_does_not_fire_for_a_drag_past_slop_but_single_released_still_does() -> void:
	# Counters as single-element Arrays, not reassigned local ints: a lambda's
	# capture of an outer primitive is by value, so `count += 1` inside one
	# would mutate a copy and leave the assertion below looking at the
	# original -- the same reason test_sim_world.gd's clock test appends to an
	# Array rather than incrementing an int.
	var tapped_calls: Array[int] = []
	var released_calls: Array[int] = []
	router.tapped.connect(func(_p: Vector2) -> void: tapped_calls.append(1))
	router.single_released.connect(func(_p: Vector2) -> void: released_calls.append(1))

	router._unhandled_input(_touch(0, Vector2(0, 0), true))
	router._unhandled_input(_drag(0, Vector2(200, 0), Vector2(200, 0)))
	router._unhandled_input(_touch(0, Vector2(200, 0), false))

	assert_eq(tapped_calls.size(), 0, "moved too far to be a tap")
	assert_eq(released_calls.size(), 1, "but the finger still lifted")


## GameScene's placement handling (PLAN.md 5.1) depends on this ordering: a
## listener that reacts to `single_released` by clearing build-mode state must
## not have already run by the time `_on_tapped` decides whether THIS release
## was a placement tap or an ordinary one.
func test_tapped_is_resolved_before_single_released_for_the_same_release() -> void:
	var order: Array[String] = []
	router.tapped.connect(func(_p: Vector2) -> void: order.append("tapped"))
	router.single_released.connect(func(_p: Vector2) -> void: order.append("released"))

	router._unhandled_input(_touch(0, Vector2(10, 10), true))
	router._unhandled_input(_touch(0, Vector2(10, 10), false))    # a clean, stationary tap

	assert_eq(order, ["tapped", "released"])


# ── the original tap/box behaviour (4.3, 8.3) is unaffected ────────────────

func test_a_clean_tap_still_emits_tapped() -> void:
	var seen: Array[Vector2] = []
	router.tapped.connect(func(p: Vector2) -> void: seen.append(p))

	router._unhandled_input(_touch(0, Vector2(5, 5), true))
	router._unhandled_input(_touch(0, Vector2(5, 5), false))

	assert_eq(seen, [Vector2(5, 5)])


func test_a_second_finger_still_starts_a_box_not_a_placement_drag() -> void:
	var box_events: Array[Rect2] = []
	router.box_changed.connect(func(r: Rect2) -> void: box_events.append(r))

	router._unhandled_input(_touch(0, Vector2(0, 0), true))
	router._unhandled_input(_touch(1, Vector2(100, 100), true))

	assert_false(box_events.is_empty(), "two fingers down is still a box, unchanged by 5.1")
