## Turns raw touch/mouse events into game gestures (PLAN.md 4.3). Phase 4.3.
##
## Only TAP for now. Pan and zoom still live in `CameraRig`, which recognises them
## from the same events; the two do not fight because they are looking for opposite
## things -- the camera acts on drag motion, this acts on a press that ended
## without any. Double-tap, two-finger box select and the rest join here as their
## phases land, at which point the camera's own `_unhandled_input` is what gets
## replaced, not its rules (`begin_gesture`/`apply_drag` are already public for it).
##
## A tap is a press and release that stayed within TAP_SLOP pixels and under
## TAP_TIME_MS. Both bounds are needed: distance alone would make a long press with
## a steady thumb a tap, and time alone would make a fast flick a tap.
class_name InputRouter
extends Node

## Fingers are imprecise and screens are dense -- 2600 px across on the reference
## device (PLAN.md 3.0). In canvas units, ~2 mm of wobble there.
const TAP_SLOP := 18.0
const TAP_TIME_MS := 400

signal tapped(screen_pos: Vector2)

var _touch_index := CameraRig.NO_TOUCH
var _down_pos := Vector2.ZERO
var _down_msec := 0
var _moved := 0.0
var _mouse_down := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index == CameraRig.NO_TOUCH:
				_touch_index = touch.index
				_begin(touch.position)
		elif touch.index == _touch_index:
			_touch_index = CameraRig.NO_TOUCH
			_end(touch.position)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_moved += drag.relative.length()

	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_mouse_down = true
			_begin(button.position)
		elif _mouse_down:
			_mouse_down = false
			_end(button.position)

	elif event is InputEventMouseMotion and _mouse_down:
		_moved += (event as InputEventMouseMotion).relative.length()


func _begin(pos: Vector2) -> void:
	_down_pos = pos
	_down_msec = Time.get_ticks_msec()
	_moved = 0.0


## Accumulated travel is checked as well as start-to-end distance: a finger that
## wanders out and comes back has panned the map, and releasing it should not also
## count as a tap on wherever it happened to end up.
func _end(pos: Vector2) -> void:
	if _moved > TAP_SLOP or pos.distance_to(_down_pos) > TAP_SLOP:
		return
	if Time.get_ticks_msec() - _down_msec > TAP_TIME_MS:
		return
	tapped.emit(pos)
