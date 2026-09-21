## Dev check for the TOUCH path: can a thumb work the controls, or only a mouse?
##
## **THE INSTRUMENT THIS REPO DID NOT HAVE, and the bug that says why it is needed**
## (project owner, 2026-08-30): *"on android while in game opening settings does not allow
## me to interact with volume sliders."* The three volume sliders had been inert under a
## finger from the day they landed. Every test passed, every screenshot looked right, and
## the front door's copy of the same panel worked perfectly — because **everything here is
## developed with a mouse**, and nothing in the repo had ever pushed an
## `InputEventScreenTouch` at anything.
##
## ## The one fact the whole file is about
##
## This project sets `input_devices/pointing/emulate_mouse_from_touch = false`
## ([project.godot:35]) because a touch that ALSO arrives as a mouse event drives the
## camera twice — `CameraRig` handles both `InputEventScreenDrag` and
## `InputEventMouseMotion`. `GameScene` turns emulation off on entry and hands it back in
## `_exit_tree`, so **it is off for exactly as long as a match lasts**.
##
## Godot's `Slider` drives its value from `InputEventMouseButton` and
## `InputEventMouseMotion` and from nothing else, so with emulation off it is not
## sluggish or hard to hit: it is completely inert. A `BaseButton` answers a raw touch,
## which is why every other control in the game was fine and why nobody noticed.
##
## ## Two routes, and they answer different questions
##
## `Viewport.push_input` goes straight into the GUI and MISSES the emulation layer, which
## lives in `Input::parse_input_event` upstream of it. So `parse_input_event` is the route
## a real finger takes and the only one that can tell the front door (emulation on) from
## an in-match panel (emulation off); `push_input` is the route that shows what the control
## itself understands with no help. A control that only works on the second row of the
## table is a control that only works outside a match.
##
## Usage:
##   Godot --path game res://dev_preview/preview_touch_controls.tscn
##       -- prints a table per control and quits. Exit code 1 if anything is inert.
extends Control

## Where the panel is put, and where along its sliders the finger lands. The tap is near
## the right-hand end so a control that ignores it reads as "unchanged from 0.50" rather
## than as a value that happens to be close.
const PANEL_AT := Vector2(80.0, 60.0)
const PANEL_WIDTH := 216.0
const TAP_FRACTION := 0.95

var _failures: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# THE REAL PANEL, not a bare slider standing in for one. What broke was the panel the
	# player opens, and a hand-built slider would not have caught a row buried under a
	# `MOUSE_FILTER_STOP` parent or laid out off its own hit box.
	var panel := VolumePanel.new(PANEL_WIDTH)
	panel.position = PANEL_AT
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	for row in panel.get_children():
		for child in row.get_children():
			if child is Range:
				await _probe(child as Range, _label_above(child))

	await _probe_the_destroy_dialog()

	print("")
	if _failures.is_empty():
		print("  every control answered a finger with emulation OFF -- the in-match case")
	else:
		for f in _failures:
			printerr("  INERT UNDER A FINGER: %s" % f)
	get_tree().quit(1 if not _failures.is_empty() else 0)


## `ConfirmOverlay` inside a match (board `8.x-destroy-confirm`, 2026-09-21).
##
## ⚠️ **A `Button` ANSWERS A FINGER AND THAT IS NOT THE QUESTION HERE.** The header's rule
## would let this widget through untested: both controls are `BaseButton`s, which is the
## class that was always fine. What is new is what they are UNDER -- a full-rect
## `MOUSE_FILTER_STOP` root with a `MOUSE_FILTER_STOP` backdrop, whose whole job is to
## swallow presses aimed at the match behind it. **A backdrop that swallows too much is a
## dialog nobody can answer**, and on a phone that is strictly worse than the accidental
## demolition it was added to prevent: the match is still running underneath and the
## player cannot get back to it.
##
## `_probe` is written for a `Range` and its "did it move" test is a value change, so this
## is a second probe rather than a generalisation of the first. Same two routes, same two
## emulation settings, same row that decides.
func _probe_the_destroy_dialog() -> void:
	var overlay := ConfirmOverlay.new()
	add_child(overlay)
	# ⛔ **SIZED EXPLICITLY, BECAUSE `PRESET_FULL_RECT` RESOLVES AGAINST A PARENT AND THIS
	# PARENT IS A PREVIEW ROOT.** `ConfirmOverlay` centres its frame inside itself with
	# `PRESET_CENTER`; against a zero-sized parent that centres it about the ORIGIN, which
	# put CANCEL's rect at `P: (-209.0, 14.0)` — off the left edge — while DESTROY, at
	# `P: (9.0, 14.0)`, landed on screen by arithmetic accident.
	#
	# ⚠️ **AND THE TOUCH ROWS PASSED ANYWAY, WHICH IS THE PART WORTH KNOWING**: a raw
	# `InputEventScreenTouch` at a negative coordinate still reached the button, where a
	# mouse click at the same point did not. So the probe was green for CANCEL for a reason
	# that had nothing to do with what it claims to measure. In the real game the overlay
	# is a child of the HUD `CanvasLayer` and none of this arises — `preview_destroy_confirm`
	# drives that one.
	#
	# 📝 `set_deferred` rather than a plain assignment: a `Control` with non-equal opposite
	# anchors has its size overridden after `_ready`, and the engine warns about it.
	overlay.set_deferred("size", get_viewport_rect().size)
	await get_tree().process_frame
	overlay.open("Destroy Villager?", "This cannot be undone.", "DESTROY")
	await get_tree().process_frame
	await get_tree().process_frame

	# ⚠️ **RE-OPENED BEFORE EACH ROW, BECAUSE A SUCCESSFUL PRESS CLOSES THE DIALOG.**
	# `ConfirmOverlay` closes before it emits, so the second button was being probed on a
	# hidden overlay -- and a hidden control answers nothing, which reads as the touch bug.
	for button in [overlay.cancel_button(), overlay.confirm_button()]:
		await _probe_button(overlay, button, "confirm dialog %s" % button.text)

	overlay.queue_free()


## One button, four ways. Counts real `pressed` signals rather than reading a property,
## because that is what the caller is wired to -- `GameScene` submits the destroy command
## from `pressed`, so a button that highlights under a finger and never emits is exactly
## as useless as one that ignores it.
## ⛔ **THE COUNTER IS AN ARRAY AND THAT IS NOT A STYLE CHOICE.** GDScript lambdas capture
## a local by VALUE, so `var n := 0` with `func(): n += 1` increments the lambda's own copy
## and the outer `n` stays 0 forever. The first version of this probe did exactly that and
## reported all four rows AND the mouse row as `presses 0` — a complete false alarm about a
## dialog that was working perfectly. What gave it away is the diagnostic this file's
## header insists on: **the mouse row failing too means the harness, not the control.**
## An Array is a reference, so the captured copy points at the same object.
func _probe_button(overlay: ConfirmOverlay, button: Button, label: String) -> void:
	print("")
	print("  %s (%s)" % [label, "ConfirmOverlay"])

	var hits := [0]
	var counter := func() -> void: hits[0] += 1
	button.pressed.connect(counter)

	var touch_worked := false
	for route in ["push_input", "parse_input_event"]:
		for emulate in [false, true]:
			Input.set_emulate_mouse_from_touch(emulate)
			hits[0] = 0
			var at := await _reopen(overlay, button)

			# PRESS AND RELEASE, both. A `Button` fires on the release by default, so a
			# probe that only pushed the down event would report every button in the game
			# as inert and send the next reader hunting a bug that is in this file.
			_touch(route, at, true)
			await get_tree().process_frame
			_touch(route, at, false)
			await get_tree().process_frame
			await get_tree().process_frame

			print("    %-18s emulate=%-5s presses %d  %s"
					% [route, emulate, hits[0], "ok" if hits[0] > 0 else "NOTHING"])
			if route == "parse_input_event" and not emulate and hits[0] > 0:
				touch_worked = true

	# THE MOUSE ROW, for the reason `_probe`'s header gives: without it, a button inert
	# because it is covered, unparented or zero-sized reads as the touch bug. It earned
	# its keep on the first run — see this function's own header.
	Input.set_emulate_mouse_from_touch(false)
	hits[0] = 0
	var mouse_at := await _reopen(overlay, button)
	for pressed in [true, false]:
		_click(mouse_at, pressed)
		await get_tree().process_frame
	print("    %-18s              presses %d%s" % ["mouse", hits[0],
			"" if hits[0] > 0 else "  <- THE HARNESS IS WRONG, not the control"])

	button.pressed.disconnect(counter)
	overlay.close()
	if not touch_worked:
		_failures.append("%s -- a finger cannot press it inside a match" % label)


## Re-open the dialog (a press closes it) and give it back the frames it needs to lay
## itself out, then say where to aim.
##
## ⛔ **RE-SHOWING A HIDDEN `Control` DOES NOT POSITION IT UNTIL THE NEXT LAYOUT PASS, AND
## ONE `process_frame` IS NOT ENOUGH.** `ConfirmOverlay` centres its frame with
## `PRESET_CENTER`, so a rect read too early is measured about the origin: CANCEL came back
## at `P: (-209.0, 14.0)`, putting its centre at **x = -109**, off the left edge of the
## screen. The click went into empty space and the row read `presses 0` — reported, of
## course, as the control being inert.
##
## ⚠️ **IT COST TWO WRONG DIAGNOSES BEFORE THE RECT WAS SIMPLY PRINTED**, and both were
## plausible: that `open()` grabbing focus for CANCEL ate the first click (a mouse MOTION
## first did not help), and that the `emulate=true` rows left a synthetic mouse button held
## (a release first did not help either). §6's rule, arriving on schedule — **measure the
## thing rather than reasoning about which mechanism would explain it.** The measurement
## was one `print` of `get_global_rect()`.
func _reopen(overlay: ConfirmOverlay, button: Button) -> Vector2:
	overlay.open("Destroy Villager?", "This cannot be undone.", "DESTROY")
	await get_tree().process_frame
	await get_tree().process_frame
	var rect := button.get_global_rect()
	return rect.position + rect.size * 0.5


func _click(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at
	get_viewport().push_input(ev)


## The label sitting above a slider in its row, which is what the player reads.
func _label_above(slider: Node) -> String:
	for sibling in slider.get_parent().get_children():
		if sibling is Label:
			return (sibling as Label).text
	return slider.name


## One control, four ways, plus the mouse as the control that proves the harness works.
##
## THE MOUSE ROW IS NOT DECORATION. Without it, a control that is inert for some entirely
## different reason -- covered by something, disabled, zero-sized -- reads as the touch bug
## and sends the next person after the wrong fix.
func _probe(control: Range, label: String) -> void:
	print("")
	print("  %s (%s)" % [label, control.get_class() if control.get_script() == null
			else control.get_script().resource_path.get_file()])

	var rect := control.get_global_rect()
	var at := Vector2(rect.position.x + rect.size.x * TAP_FRACTION,
			rect.position.y + rect.size.y * 0.5)
	var start := Vector2(rect.position.x + rect.size.x * 0.05, at.y)

	var touch_worked := false
	for route in ["push_input", "parse_input_event"]:
		for emulate in [false, true]:
			Input.set_emulate_mouse_from_touch(emulate)
			control.set_value_no_signal(0.5)
			await get_tree().process_frame

			_touch(route, at, true)
			await get_tree().process_frame
			await get_tree().process_frame
			var tapped := control.value
			_drag(route, start, at)
			await get_tree().process_frame
			await get_tree().process_frame
			var dragged := control.value
			_touch(route, at, false)
			await get_tree().process_frame

			var moved := absf(tapped - 0.5) > 0.001 or absf(dragged - 0.5) > 0.001
			print("    %-18s emulate=%-5s tap %.2f  drag %.2f  %s"
					% [route, emulate, tapped, dragged, "ok" if moved else "NOTHING"])
			# THE ROW THAT MATTERS is a real finger with emulation off, which is what a
			# match runs under. The other three are context for reading it.
			if route == "parse_input_event" and not emulate and moved:
				touch_worked = true

	Input.set_emulate_mouse_from_touch(false)
	control.set_value_no_signal(0.5)
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	get_viewport().push_input(click)
	await get_tree().process_frame
	print("    %-18s              tap %.2f%s" % ["mouse", control.value,
			"" if absf(control.value - 0.5) > 0.001
			else "  <- THE HARNESS IS WRONG, not the control"])

	if not touch_worked:
		_failures.append("%s -- a finger moves it nowhere inside a match" % label)


func _send(route: String, ev: InputEvent) -> void:
	if route == "push_input":
		get_viewport().push_input(ev)
	else:
		Input.parse_input_event(ev)


func _touch(route: String, at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = at
	_send(route, ev)


func _drag(route: String, from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = to
	ev.relative = to - from
	_send(route, ev)
