## Turns raw touch/mouse events into game gestures (PLAN.md 4.3, 8.3).
##
## TAP and two-finger BOX SELECT. Pan and zoom still live in `CameraRig`, which
## recognises them from the same events; they do not fight because each is looking
## for something the others are not -- the camera acts on a one-finger drag, the
## tap on a press that ended without any, and the box on a second finger arriving.
## Double-tap and the rest join here as their phases land.
##
## A tap is a press and release that stayed within TAP_SLOP pixels and under
## TAP_TIME_MS. Both bounds are needed: distance alone would make a long press with
## a steady thumb a tap, and time alone would make a fast flick a tap.
##
## This is why `pointing/emulate_mouse_from_touch` is off (PLAN.md 881): box select
## needs raw `InputEventScreenTouch`/`Drag` with real finger indices, and emulation
## collapses them into one mouse.
class_name InputRouter
extends Node

## Fingers are imprecise and screens are dense -- 2600 px across on the reference
## device (PLAN.md 3.0). In canvas units, ~2 mm of wobble there.
const TAP_SLOP := 18.0
const TAP_TIME_MS := 400

## A box smaller than this is treated as a fumbled two-finger tap rather than a
## selection, so brushing the screen with two fingers does not clear what you had
## selected by "selecting" a three-pixel rectangle.
const MIN_BOX := 24.0

## `from_touch` separates a finger from a mouse, which the two devices need
## different answers for: a tap on empty ground DESELECTS on touch and only
## moves on a double tap (a small quick pan otherwise reads as a tap and sends
## units wandering), while a mouse is precise enough to move on one click.
## Carried on the signal rather than read from `DisplayServer` because what
## matters is which device produced THIS gesture, not what the machine supports
## -- a touchscreen laptop has both.
signal tapped(screen_pos: Vector2, from_touch: bool)
## Live box, for drawing it while the fingers are still down.
signal box_changed(screen_rect: Rect2)
## Committed box, on release. Never emitted for a box under MIN_BOX.
signal box_selected(screen_rect: Rect2)
## The box was abandoned (too small, or cancelled) -- stop drawing it.
signal box_cancelled()

## Right-click released without having dragged a box (desktop only). "Back out
## of whatever I am doing": cancel a placement, else clear the selection.
##
## Kept separate from `box_cancelled`, which fires for this AND for a fumbled
## two-finger touch -- and a mobile player brushing the screen with two fingers
## must not lose their selection, which is the whole reason MIN_BOX exists.
signal context_cancel()

## The single-finger/mouse gesture, reported unconditionally rather than only
## when it turns out to have been a tap -- PLAN.md 5.1's drag-to-place wants
## the finger's position for as long as it is down, whether or not the drag
## ever qualifies as a tap. `tapped` is unaffected and still fires only for a
## press-and-release that stayed inside TAP_SLOP/TAP_TIME_MS; these three fire
## alongside it for every single-finger gesture, tap or not.
signal single_pressed(screen_pos: Vector2)
signal single_drag_moved(screen_pos: Vector2)
signal single_released(screen_pos: Vector2)

## Mouse moved with nothing held down at all -- no touch equivalent, since a
## finger cannot hover. PLAN.md 5.1's placement ghost wants this on desktop:
## touch drags the ghost into position and releases to drop it, but a mouse
## has no reason to hold a button down just to move the cursor, so build mode
## would otherwise leave the ghost frozen wherever the initiating click landed
## until the player thought to drag.
signal mouse_hover_moved(screen_pos: Vector2)

var _touch_index := CameraRig.NO_TOUCH
var _down_pos := Vector2.ZERO
var _down_msec := 0
var _moved := 0.0
var _mouse_down := false

## index -> current position, for every finger down. The box is the rectangle
## spanned by two of them, so both positions have to be tracked live.
var _touches: Dictionary = {}
var _boxing := false

## Desktop stand-in for the two-finger gesture: right-drag. There is no second
## finger on a mouse, and a feature that can only be exercised by deploying to a
## phone is one that gets tested once.
var _right_drag_from := Vector2.ZERO
var _right_dragging := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _boxing:
			box_changed.emit(_box())
		elif drag.index == _touch_index:
			_moved += drag.relative.length()
			single_drag_moved.emit(drag.position)

	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _right_dragging:
			box_changed.emit(_rect_between(_right_drag_from, motion.position))
		elif _mouse_down:
			_moved += motion.relative.length()
			single_drag_moved.emit(motion.position)
		else:
			mouse_hover_moved.emit(motion.position)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_touches[touch.index] = touch.position
		# The second finger turns whatever was happening into a box. A tap in
		# progress is abandoned rather than also firing on release -- the player
		# who put a second finger down did not mean to tap with the first.
		if _touches.size() >= 2:
			_boxing = true
			_touch_index = CameraRig.NO_TOUCH
			box_changed.emit(_box())
		elif _touch_index == CameraRig.NO_TOUCH:
			_touch_index = touch.index
			_begin(touch.position)
		return

	# A lift. Commit the box on the FIRST finger up rather than waiting for both:
	# the box stops meaning anything the moment one corner is gone, and waiting
	# would let the remaining finger drag it somewhere the player did not choose.
	if _boxing:
		var rect := _box()
		_touches.erase(touch.index)
		if _touches.is_empty():
			_boxing = false
		_commit(rect)
		return

	_touches.erase(touch.index)
	if touch.index == _touch_index:
		_touch_index = CameraRig.NO_TOUCH
		_end(touch.position, true)


func _on_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				_mouse_down = true
				_begin(button.position)
			elif _mouse_down:
				_mouse_down = false
				_end(button.position, false)
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_right_dragging = true
				_right_drag_from = button.position
				box_changed.emit(_rect_between(_right_drag_from, button.position))
			elif _right_dragging:
				_right_dragging = false
				# Not routed through _commit(): a right-click that never became a
				# box is a deliberate "cancel", whereas the same too-small rect
				# arriving from two fumbled fingers must stay a silent no-op.
				var rect := _rect_between(_right_drag_from, button.position)
				if rect.size.x < MIN_BOX and rect.size.y < MIN_BOX:
					box_cancelled.emit()
					context_cancel.emit()
				else:
					box_selected.emit(rect)


## The rectangle spanned by the two fingers currently down.
func _box() -> Rect2:
	var points := _touches.values()
	if points.size() < 2:
		return Rect2()
	return _rect_between(points[0], points[1])


func _rect_between(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


func _commit(rect: Rect2) -> void:
	if rect.size.x < MIN_BOX and rect.size.y < MIN_BOX:
		box_cancelled.emit()
		return
	box_selected.emit(rect)


func _begin(pos: Vector2) -> void:
	_down_pos = pos
	_down_msec = Time.get_ticks_msec()
	_moved = 0.0
	single_pressed.emit(pos)


## Accumulated travel is checked as well as start-to-end distance: a finger that
## wanders out and comes back has panned the map, and releasing it should not also
## count as a tap on wherever it happened to end up.
##
## `tapped` is resolved and emitted BEFORE `single_released`, not after, and the
## order is load-bearing: a placement listener reacting to `single_released` may
## exit build mode, and `_on_tapped` needs to see the build-mode state as it was
## for THIS gesture, not as whatever the other handler just changed it to for the
## next one.
func _end(pos: Vector2, from_touch: bool) -> void:
	if _moved <= TAP_SLOP and pos.distance_to(_down_pos) <= TAP_SLOP \
			and Time.get_ticks_msec() - _down_msec <= TAP_TIME_MS:
		tapped.emit(pos, from_touch)
	single_released.emit(pos)
