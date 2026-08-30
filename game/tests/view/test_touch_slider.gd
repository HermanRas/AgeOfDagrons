## The three volume sliders, and whether a thumb can move them (project owner, 2026-08-30:
## *"on android while in game opening settings does not allow me to interact with volume
## sliders"*).
##
## ⚠️ **A STOCK `HSlider` IS COMPLETELY INERT UNDER A FINGER when
## `emulate_mouse_from_touch` is off**, which is what `GameScene` sets for the length of a
## match. Measured on 4.7.1 with `dev_preview`'s throwaway probe, an `HSlider` at 0.50 given
## a tap and a drag at 95% of its track:
##
##     real input pipeline, emulation OFF -> 0.50, 0.50     (the in-match case)
##     real input pipeline, emulation ON  -> 0.95, 0.95     (the menus)
##     a mouse click                      -> 0.95
##
## THE ROUTING IS NOT WHAT IS TESTED HERE, because a `Control` outside a tree has no
## viewport to route through and standing one up headlessly would be testing Godot. The
## probe proved routing end to end; what these pin is the CONTRACT of the handler the
## routing arrives at -- that it answers a touch at all, that it follows a drag, that it
## follows the right finger, and that it stops when the finger lifts.
extends TestCase

var slider: TouchSlider


func before_each() -> void:
	slider = TouchSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size = Vector2(200, 30)
	slider.set_value_no_signal(0.5)


func after_each() -> void:
	slider.free()


func _touch(x: float, pressed: bool, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = Vector2(x, 15.0)
	slider._gui_input(ev)


func _drag(x: float, index := 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = Vector2(x, 15.0)
	slider._gui_input(ev)


func test_a_tap_moves_it() -> void:
	# THE WHOLE BUG. On the phone, in a match, this did nothing at all.
	_touch(190.0, true)
	assert_true(slider.value > 0.8, "a tap near the right-hand end reads %.2f" % slider.value)


func test_a_tap_at_the_far_end_reaches_the_far_end() -> void:
	# Clamped rather than merely close: a volume slider that cannot be put to zero or to
	# full is a volume slider with the two values a player most wants missing.
	_touch(1000.0, true)
	assert_almost_eq(slider.value, 1.0, 0.001)
	_touch(0.0, true)
	assert_almost_eq(slider.value, 0.0, 0.001)
	_touch(-50.0, true)
	assert_almost_eq(slider.value, 0.0, 0.001, "and off the left-hand end too")


func test_a_drag_follows_the_finger() -> void:
	_touch(20.0, true)
	var after_press := slider.value
	_drag(180.0)
	assert_true(slider.value > after_press,
			"%.2f after dragging right from %.2f" % [slider.value, after_press])
	_drag(20.0)
	assert_almost_eq(slider.value, after_press, 0.001, "and back again")


func test_a_drag_that_never_pressed_this_slider_is_ignored() -> void:
	# `_gui_input` sees drags for fingers that never touched this control -- a second thumb
	# resting on the panel, most obviously. Without the index check the two would fight
	# over the value, which on a three-slider panel is a thumb changing the wrong row.
	_touch(20.0, true, 0)
	var held := slider.value
	_drag(190.0, 1)
	assert_almost_eq(slider.value, held, 0.001, "the other finger moves nothing")
	_drag(190.0, 0)
	assert_true(slider.value > held, "and the one holding it still does")


func test_letting_go_stops_it_following() -> void:
	_touch(20.0, true)
	_touch(20.0, false)
	var released := slider.value
	_drag(190.0)
	assert_almost_eq(slider.value, released, 0.001,
			"a drag after the lift is somebody else's gesture")


func test_the_value_is_snapped_to_the_step_like_any_other_range() -> void:
	# Nothing here does the snapping -- `Range.set_as_ratio` does, which is the reason to
	# go through it rather than writing `value` from the arithmetic directly.
	_touch(77.0, true)
	assert_almost_eq(fmod(slider.value, slider.step), 0.0, 0.0001,
			"%.4f is not a multiple of %.2f" % [slider.value, slider.step])


func test_it_is_still_a_slider_to_everything_else() -> void:
	# `VolumePanel` reads `value` and writes `set_value_no_signal`, and the front door's
	# copy of the panel is driven by a mouse. This class ADDS a path; it must not replace
	# one, and nothing about `Range` may be shadowed by the two lines it overrides.
	slider.value = 0.25
	assert_almost_eq(slider.value, 0.25, 0.001)
	slider.set_value_no_signal(0.75)
	assert_almost_eq(slider.value, 0.75, 0.001)
	_touch(20.0, true)
	assert_true(slider.value < 0.5, "and a touch still writes through the same property")


## ⚠️ **A `Range` OUTSIDE THE TREE EMITS NO `value_changed` AT ALL**, verified here rather
## than worked around silently — the first version of the test above asserted the signal
## and got nothing. `Range::Shared::emit_value_changed()` skips every owner for which
## `is_inside_tree()` is false, so the value moves and no listener hears it.
##
## It costs nothing in the game (`VolumePanel`'s sliders are in a tree by the time anybody
## can touch them) and it is a trap for the next test of anything Range-shaped: the value
## is observable and the signal is not, so "the slider did not change" and "the signal is
## not wired" look identical from out here. Assert the VALUE.
func test_a_detached_range_moves_silently_which_is_why_nothing_above_asserts_the_signal() -> void:
	var heard: Array[float] = []
	slider.value_changed.connect(func(v: float) -> void: heard.append(v))
	slider.value = 0.25
	assert_almost_eq(slider.value, 0.25, 0.001, "the value moved")
	assert_true(heard.is_empty(), "and no signal was emitted, because it is not in a tree")


func test_the_volume_panel_uses_one() -> void:
	# The wiring, which is the half a handler test cannot see: three inert `HSlider`s and
	# three working `TouchSlider`s pass every assertion above equally.
	var panel := VolumePanel.new(216.0)
	var found := 0
	for row in panel.get_children():
		for child in row.get_children():
			if child is TouchSlider:
				found += 1
	assert_eq(found, VolumePanel.ROWS.size(), "every volume row is touchable")
	panel.free()
