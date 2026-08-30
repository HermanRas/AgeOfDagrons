## An HSlider a finger can actually move.
##
## THE BUG THIS EXISTS FOR (project owner, 2026-08-30): *"on android while in game opening
## settings does not allow me to interact with volume sliders."* **In game** is the whole
## report — the front door's SETTINGS shows the same `VolumePanel` and works there.
##
## `TouchLineEdit`'s bug one control along, and the same root: this project sets
## `input_devices/pointing/emulate_mouse_from_touch = false` ([project.godot:35]) because a
## touch that ALSO arrives as a mouse event drives the camera twice — `CameraRig` handles
## both `InputEventScreenDrag` and `InputEventMouseMotion`, so one thumb would pan two
## thumbs' worth. `GameScene` turns emulation off on entry and hands it back in
## `_exit_tree`, so **it is off for exactly as long as a match lasts**, which is exactly
## when the pause menu is reachable.
##
## Godot's `Slider` drives its value from `InputEventMouseButton` and
## `InputEventMouseMotion` and from nothing else. Measured on 4.7.1, an `HSlider` at 0.50
## given a tap and then a drag at 95% of its track:
##
##     real input pipeline, emulation OFF -> 0.50, 0.50     (the in-match case)
##     real input pipeline, emulation ON  -> 0.95, 0.95     (the menus)
##     a mouse click                      -> 0.95
##
## So the control is not sluggish or mis-hit on the phone: it is **completely inert**, and
## the three volume sliders are the only controls in the game that are, because everything
## else on a HUD is a `BaseButton` and buttons do answer a raw touch.
##
## ⚠️ **THE FIX IS THE CONTROL, NOT THE PROJECT SETTING**, and the tempting one-liner is a
## trap. Turning emulation back on while the menu is open would fix every control at once
## and leave a global flag that has to be turned off again on every path out of the menu —
## and the failure if one path misses it is a camera that pans twice for the rest of the
## match, silently, which is the exact hazard `GameScene._exit_tree`'s own comment records
## from the other direction.
##
## **IT IS ADDITIVE, NOT A REPLACEMENT.** `accept_event()` is deliberately not called, the
## same choice `TouchLineEdit` makes and for the same reason: `Control` runs the script's
## `_gui_input` before the built-in handler, so with emulation ON (the front door) the base
## class still does its own thing and both set the SAME value from the SAME position.
## Setting a value from a position is idempotent, which is what makes doubling up harmless
## here where it would not be on a button.
class_name TouchSlider
extends HSlider

## Which finger is holding the track, or -1. A drag carries the index of the touch that
## started it, and `_gui_input` sees drags for fingers that never pressed THIS control --
## a second thumb elsewhere on the screen, most obviously. Without the check, resting a
## thumb on the panel while dragging the other would fight over the value.
var _finger := -1


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_finger = touch.index
			_set_from(touch.position.x)
		elif touch.index == _finger:
			_finger = -1
		return

	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		_set_from(drag.position.x)


## The value a CLICK at this x would have produced, which is the property worth having:
## the arithmetic below is Godot's own from `Slider::gui_input`, so a thumb and a mouse
## land on the same number rather than merely on similar ones.
##
## The grabber's WIDTH is the part a hand-rolled version gets wrong. The usable track is
## the control less one grabber, and the value is measured from the grabber's CENTRE — so
## ignoring it makes a tap at either end unreachable and every tap in between wrong by up
## to half a grabber.
func _set_from(x: float) -> void:
	var grabber: Texture2D = get_theme_icon(&"grabber")
	var grab_width := float(grabber.get_width()) if grabber != null else 0.0
	var track := size.x - grab_width
	if track <= 0.0:
		return
	set_as_ratio(clampf((x - grab_width * 0.5) / track, 0.0, 1.0))
