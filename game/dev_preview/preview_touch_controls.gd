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

	print("")
	if _failures.is_empty():
		print("  every control answered a finger with emulation OFF -- the in-match case")
	else:
		for f in _failures:
			printerr("  INERT UNDER A FINGER: %s" % f)
	get_tree().quit(1 if not _failures.is_empty() else 0)


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
