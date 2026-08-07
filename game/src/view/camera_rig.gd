## The player's view onto the world: drag to pan, clamped to the map (PLAN.md 3.3).
##
## A Camera2D rather than moving the world node, which is what every scene did up
## to 3.1 -- each one carried its own "shove the settlement to the middle of the
## screen" hack, and each one had to be told the viewport size. One camera replaces
## all of them, and 3.4 (centre on the town centre) and 3.5 (follow a unit) become
## calls rather than new hacks.
##
## **Clamping is done here, not by Camera2D's own limit_* properties.** The engine's
## limits are applied deep in its transform update and cannot be exercised without
## a running viewport, so the rule that decides where the player may look would be
## the one part of the camera no test could reach. `clamped_centre()` is a pure
## function instead: 3.2 changes the visible size when it zooms, and the clamp has
## to stay correct across that.
##
## Input handling is deliberately doubled up. project.godot sets
## `pointing/emulate_mouse_from_touch=false` and does not emulate touch from mouse
## either, so a touch produces ONLY touch events and a mouse produces ONLY mouse
## events. Handling one would mean the camera worked on the phone but not on the
## desktop the work is done on, or the reverse.
class_name CameraRig
extends Camera2D

## Only the first finger down drives the camera. Later fingers are ignored rather
## than each dragging on top of the other, and it keeps the gesture space clear
## for 4.2's two-finger box select.
const NO_TOUCH := -1

## What a drag does depends on where it STARTED, and stays that way until the
## finger lifts. Deciding per-move instead would flip a zoom into a pan halfway
## through as the finger wandered out of the edge strip.
enum Gesture { PAN, ZOOM }

## Width of the zoom strip down each side (IDEA 3.2: "swiping up or down the left
## or right side of the screen"). Both sides, so it works left- or right-handed.
##
## In canvas units, which is 100 / 648 of the screen height -- about 10 mm on the
## reference device (PLAN.md 3.0), at the low end of a comfortable touch target.
## Narrower and it gets missed; wider and it eats map you want to drag.
const EDGE_WIDTH := 100.0

## Zoom range. 1.0 draws a tile at its baked 64x32; the ends are roughly "see the
## whole settlement" and "read one villager".
const MIN_ZOOM := 0.6
const MAX_ZOOM := 2.0

## Zoom is multiplied, never added (PLAN.md 814 `zoom_by(factor)`), because zoom is
## a ratio -- a fixed step per pixel would crawl at 2x and leap at 0.6x.
##
## Derived, not tuned by feel: one full-height swipe of the 648-tall canvas should
## cross the whole range exactly once, so exp(648 * k) = MAX_ZOOM / MIN_ZOOM.
const ZOOM_PER_PIXEL := 0.0018566635  # ln(2.0 / 0.6) / 648

var map_size: Vector2i = Vector2i.ZERO

## Viewport size in screen pixels, tracked rather than read on demand.
##
## Stored because it genuinely changes -- rotating the phone or resizing the
## window resizes the viewport, and every rule here depends on it: the clamp
## margin, the zoom-out floor, and where the edge strips are. Reading it live
## would also make the whole class untestable, since TestCase is a RefCounted
## with no scene tree and therefore no viewport.
var view_size: Vector2 = Vector2.ZERO

var _touch_index := NO_TOUCH
var _gesture := Gesture.PAN
var _mouse_dragging := false


func _ready() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_track_viewport)
	_track_viewport()


func _track_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	view_size = Vector2(vp.get_visible_rect().size)
	# A rotation can invalidate both the clamp and the zoom floor at once.
	zoom_by(1.0)


## The screen-space box the map projects into. Derived, so it cannot disagree
## with map_size.
func map_bounds() -> Rect2:
	return Iso.map_bounds(map_size)


## Give the camera the map it is looking at. Until this is called the map is empty,
## which pins the camera rather than letting it wander a map that has not loaded.
func setup(p_map_size: Vector2i) -> void:
	map_size = p_map_size
	position = clamped_centre(position, map_size, visible_size())


## Put `world` in the middle of the screen, as far as the clamp allows. 3.4's
## double-tap-minimap and 3.5's follow both come through here.
func centre_on(world: Vector2) -> void:
	position = clamped_centre(world, map_size, visible_size())


## Move the view by a gesture measured in SCREEN pixels.
##
## Divided by zoom because a drag is a physical distance on the glass: at 2x zoom
## the same finger movement must cover half as much world, or panning speeds up
## as you zoom in (3.2). Negated because dragging the map left moves the camera
## right -- the player is grabbing the ground, not the viewfinder.
func pan_by(screen_delta: Vector2) -> void:
	position = clamped_centre(position - screen_delta / zoom, map_size, visible_size())


## Multiply the zoom, about the middle of the screen (PLAN.md 814).
##
## Re-clamps afterwards because zooming OUT enlarges the visible area, which can
## leave a camera that was legally parked against an edge now looking past it.
func zoom_by(factor: float) -> void:
	var level := clampf(zoom.x * factor, min_zoom(), MAX_ZOOM)
	zoom = Vector2(level, level)
	position = clamped_centre(position, map_size, visible_size())


## An edge swipe, in screen pixels. Up is negative screen y and zooms IN, the way
## a slider pushed away from you goes up.
func zoom_by_swipe(screen_delta_y: float) -> void:
	zoom_by(exp(-screen_delta_y * ZOOM_PER_PIXEL))


## The furthest out the player may zoom.
##
## MIN_ZOOM unless the map is small enough to fit on screen before then -- past
## that point zooming out only adds void, so the map itself sets the floor. Never
## binds on a 64x64 map; a small test map hits it immediately.
func min_zoom() -> float:
	var bounds := map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or view_size == Vector2.ZERO:
		return MIN_ZOOM
	return maxf(MIN_ZOOM, minf(MAX_ZOOM,
			maxf(view_size.x / bounds.size.x, view_size.y / bounds.size.y)))


## How much world the viewport currently shows, in world units.
func visible_size() -> Vector2:
	return view_size / zoom


## True for the zoom strips down either side of the screen.
func is_edge(screen_x: float) -> bool:
	return screen_x <= EDGE_WIDTH or screen_x >= view_size.x - EDGE_WIDTH


## Decide what a drag starting at `screen_x` will do, and hold that decision until
## it ends. Public because 4.2's InputRouter takes over gesture recognition and
## drives the camera through this pair rather than through _unhandled_input.
func begin_gesture(screen_x: float) -> void:
	_gesture = Gesture.ZOOM if is_edge(screen_x) else Gesture.PAN


## One drag step, doing whatever the gesture that started it decided on.
func apply_drag(relative: Vector2) -> void:
	if _gesture == Gesture.ZOOM:
		zoom_by_swipe(relative.y)
	else:
		pan_by(relative)


## Where the camera may sit, given the map and how much of it the viewport shows.
##
## TWO rules, because the map is a diamond inside a rectangular box and neither
## rule alone gives a decent frame:
##
##   1. The camera must be looking AT the map -- its centre stays on the diamond.
##      Without this the west and east corners are reachable with the ground
##      reduced to a sliver: measured at 15% of the frame on a 64x64 map before
##      this rule existed, because the box extends a full half-map beyond the
##      diamond's tip.
##   2. The viewport must stay inside the projected box, which is what stops the
##      north and south edges showing void above and below the map.
##
## Applied in that order. The box rule only ever pushes a point further INTO the
## box, and the diamond is convex and concentric with it, so the second rule
## cannot undo the first.
static func clamped_centre(centre: Vector2, map_size: Vector2i, view: Vector2) -> Vector2:
	return _inside_box(_on_the_map(centre, map_size), Iso.map_bounds(map_size), view)


## Confine a screen point to the map diamond, by clamping it in TILE space where
## the diamond is an axis-aligned box.
static func _on_the_map(centre: Vector2, map_size: Vector2i) -> Vector2:
	var t := Iso.world_to_tile_f(centre)
	return Iso.tile_to_world_f(Vector2(
		clampf(t.x, 0.0, float(maxi(0, map_size.x))),
		clampf(t.y, 0.0, float(maxi(0, map_size.y)))))


## Keep the visible rect within `bounds`.
##
## When the map is SMALLER than the view on an axis the clamp would invert -- the
## minimum ends up beyond the maximum -- and clamping to an inverted range gives
## whichever end came last, pinning a small map to a corner. That axis is centred
## on the map instead, which is the only sensible framing when the ground does not
## fill the screen, and is the case a small test map hits immediately.
static func _inside_box(centre: Vector2, bounds: Rect2, view: Vector2) -> Vector2:
	var half := view * 0.5
	var low := bounds.position + half
	var high := bounds.end - half
	var middle := bounds.get_center()
	return Vector2(
		middle.x if low.x > high.x else clampf(centre.x, low.x, high.x),
		middle.y if low.y > high.y else clampf(centre.y, low.y, high.y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			apply_drag(drag.relative)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _mouse_dragging:
		apply_drag((event as InputEventMouseMotion).relative)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touch_index == NO_TOUCH:
			_touch_index = touch.index
			begin_gesture(touch.position.x)
	elif touch.index == _touch_index:
		_touch_index = NO_TOUCH


## The mouse gets the same edge rule as a finger, so the gesture can be exercised
## on the desktop the work is done on rather than only on a phone. The wheel is a
## desktop-only convenience on top -- there is no wheel to test on the device.
func _on_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			_mouse_dragging = button.pressed
			if button.pressed:
				begin_gesture(button.position.x)
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				zoom_by_swipe(-60.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				zoom_by_swipe(60.0)
