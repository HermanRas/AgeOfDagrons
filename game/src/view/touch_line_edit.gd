## A LineEdit a finger can actually type into.
##
## THE BUG THIS EXISTS FOR (BUGS.md, blocking PLAN.md 12.1c). Tapping a plain LineEdit
## on Android raised no keyboard at all -- by hand or via `adb input text` -- so an
## address could not be entered on the phone, and the (g) bring-up had to be worked
## around by making the phone host and the laptop join from a terminal.
##
## It is not an Android gap, and not an adb artefact. This project sets
## `input_devices/pointing/emulate_mouse_from_touch = false` (project.godot), because a
## touch that ALSO arrives as a mouse event drives the camera twice: CameraRig handles
## both `InputEventScreenDrag` and `InputEventMouseMotion`, so one thumb would pan two
## thumbs' worth. Godot's GUI still routes raw touches to controls -- a Button reacts to
## one, and this class's `_gui_input` sees them -- but the touch path does NOT grab
## keyboard focus the way the mouse path does. Measured on 4.7.1:
##
##     focus after a SCREEN TOUCH = false
##     focus after a MOUSE CLICK  = true
##
## LineEdit asks for the on-screen keyboard when it gains focus, so a field that never
## gains focus never asks, and the keyboard never appears. Grabbing it by hand is the
## whole fix.
class_name TouchLineEdit
extends LineEdit


## A TAP CANNOT PLACE THE CARET, which is the same gap one layer down and is why this
## selects everything instead. Measured on 4.7.1, tapping and clicking 90 px into the
## text of an identical field:
##
##     TOUCH -> caret column 0
##     CLICK -> caret column 11
##
## LineEdit places the caret from `InputEventMouseButton` only. With the caret pinned at
## 0, typing an address into a field pre-filled with `127.0.0.1` INSERTS IN FRONT of it
## -- "192" gives "192127.0.0.1" -- which is worse than useless for the one job the field
## has. Selecting the lot on focus means the first keystroke replaces it, and sidesteps
## caret placement rather than reimplementing it. Left as a plain property so a field
## that wants the other behaviour can say so.
func _init() -> void:
	select_all_on_focus = true


## Not calling `accept_event()`: `Control` runs the script's `_gui_input` before the
## built-in C++ handler, so the event is left to continue on to it. That is deliberate
## even though the base handler ignores touches for caret purposes -- suppressing it
## would be a second, silent behaviour change on top of the one this class is for.
func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return

	if not has_focus():
		grab_focus()
		# The keyboard follows from focus, so there is nothing more to do on the
		# first tap.
		return

	# A SECOND tap on a field that already has focus, which is its own bug: the
	# player dismissed the keyboard with the system Back button, which does not move
	# focus, so tapping the field again changes nothing and asks for nothing. Only
	# reachable by hand -- no test can dismiss an Android keyboard -- so it is fixed
	# by inspection rather than after a report.
	_raise_keyboard()


## Ask for the on-screen keyboard directly, which is what `grab_focus()` gets LineEdit
## to do for us on the first tap. Guarded by the feature check so a desktop run is a
## no-op rather than an error.
func _raise_keyboard() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	# Deliberately untyped. `LineEdit.VirtualKeyboardType` and
	# `DisplayServer.VirtualKeyboardType` list the same kinds in the same order, but they
	# are separate types to the parser, and handing one to the other is a PARSE error --
	# which on a line only Android ever reaches would have shipped as a crash on the
	# device rather than a red squiggle here. Untyped defers it to a runtime pass-through.
	var kb_type = virtual_keyboard_type
	DisplayServer.virtual_keyboard_show(text, get_global_rect(), kb_type,
			max_length, caret_column)
