## The age indicator (PLAN.md 9.1: a roman numeral in a gold circle), doubling
## for now as the only way to advance an age at all.
##
## Two halves with very different lifespans, and it is worth being clear which is
## which:
##
##   The NUMERAL is real UI. 9.1 asks for exactly this and it stays.
##   The TAP-TO-ADVANCE is a debug affordance. Real advancement (9.2) costs
##   resources, takes time and is researched at a town centre, so it will be a
##   queue entry on the town centre's panel rather than a button here. When that
##   lands, this loses its button and keeps its numeral.
##
## It exists now because the age axis became load-bearing before the mechanism
## that drives it: buildings re-skin per age (2.7), the menus gate on age, and
## the sim refuses an order above the caller's age. Without a way to advance,
## none of that is reachable in a running game -- three quarters of the roster
## and every building skin past age 1 would be untestable on a device.
##
## Emits `advance_requested` rather than submitting a command itself, the same
## division `ControlGroupsHud` and `SelectionPanel` keep: GameScene owns the
## crossing into `Net.submit_command()`.
##
## Built in `_init()`, not `_ready()`, so a bare `.new()` is fully wired for a
## headless test -- the convention `ResourceHUD` and `ControlGroupsHud` follow.
##
## MIRRORED IN THE MOCKUP at `scenes/ui_builder/HUD.tscn`, under
## AgeHeader/Margin/Box/HBoxContainer/AgeBadge, so the header can be laid out in
## the editor. That copy is PRIMITIVES -- a rounded StyleBoxFlat for the ring and
## two Labels -- rather than an instance of this script, because the ui_builder
## scenes are drawn from primitives to stay editable without running the game
## (ControlGroupsHud.tscn mocks its slot rings the same way). The constants below
## are the shared contract between the two: SIZE, RING_WIDTH, FILL_COLOR and
## RING_COLOR all appear in that StyleBoxFlat, and the label font sizes in its
## Numeral/Hint nodes. Adjust the mockup, then bring the numbers back here --
## nothing checks that they agree, because a mockup that could not be edited
## freely would not be much of a mockup.
class_name AgeBadge
extends Button

signal advance_requested(next_age: int)

## Sized to sit inside the age header's title row beside the pause button, which
## is 48 px -- not as a free-floating badge. The first version of this WAS free
## floating, at the top right, and landed straight on top of the resource
## counters; that is what running the game caught and a headless test could not.
const SIZE := 44.0
const RING_COLOR := HudStyle.GOLD
const RING_WIDTH := 3.0
const FILL_COLOR := Color(0.17, 0.11, 0.08, 0.9)
## The numeral goes grey once there is nothing left to advance to, rather than
## the button hiding: a HUD element that disappears at age 4 reads as a bug.
const MAXED_COLOR := Color(0.62, 0.58, 0.5)

var age: int = 1:
	set(value):
		if age == value:
			return
		age = value
		_refresh()

var _numeral: Label
var _hint: Label


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 10.0)
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = "Advance an age (debug -- 9.2 makes this a researched action)"
	# A Button paints its own themed StyleBox under this script's children unless
	# every state is emptied -- the trap ControlGroupSlot and ActionSlot both
	# document.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)

	_numeral = Label.new()
	_numeral.add_theme_font_size_override("font_size", 18)
	_numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numeral.size = Vector2(SIZE, SIZE)
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_numeral)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", HudStyle.GOLD)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0.0, SIZE - 4.0)
	_hint.size = Vector2(SIZE, 12.0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	pressed.connect(_on_pressed)
	_refresh()


## The age after this one, or 0 when there is none. Read from `ages.json` rather
## than assumed to be 4, so adding a fifth age is a data change.
func next_age() -> int:
	return age + 1 if age < GameDataRegistry.age_count() else 0


func _refresh() -> void:
	var def: AgeDef = GameDataRegistry.age(age)
	# Falls back to the number rather than blanking: an age with no entry in
	# ages.json is a data bug, and showing "3" says more than showing nothing.
	_numeral.text = def.numeral if def != null and not def.numeral.is_empty() else str(age)

	var has_next := next_age() != 0
	_numeral.add_theme_color_override("font_color",
			HudStyle.GOLD if has_next else MAXED_COLOR)
	_hint.text = "ADVANCE" if has_next else "MAX"
	_hint.add_theme_color_override("font_color",
			HudStyle.GOLD if has_next else MAXED_COLOR)
	queue_redraw()


func _draw() -> void:
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - RING_WIDTH
	draw_circle(centre, radius, FILL_COLOR)
	draw_arc(centre, radius, 0.0, TAU, 32,
			RING_COLOR if next_age() != 0 else MAXED_COLOR, RING_WIDTH, true)


## Silently does nothing at the last age instead of emitting an advance that the
## sim would reject anyway. DebugSetAgeCommand.validate() refuses an out-of-range
## age rather than clamping precisely so the two cannot drift apart unnoticed --
## if this ever emits past the end, that rejection is the thing that says so.
func _on_pressed() -> void:
	var next := next_age()
	if next != 0:
		advance_requested.emit(next)
