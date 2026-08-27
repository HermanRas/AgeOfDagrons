## The idle-villager badge in the age header: a crimson ring with a headcount in
## it, and the word "Idle" beside it. Tapping walks the player through their idle
## units one at a time (PLAN.md 7.1's counter, made actionable).
##
## VILLAGERS ONLY, and nothing else in the roster. An idle soldier is a garrison
## rather than a mistake, and this badge is a button that walks to whatever it
## counts -- so counting one would send the camera off to a knight standing guard.
## `GameView._is_own_living_villager()` is the definition, and it asks the def for
## a gather rate rather than naming `unit.villager`.
##
## This is NOT the resource panel's bottom row. That one is population: units on
## the map against the limit their buildings provide (PLAN.md 4.11). The two were
## briefly driven off one signal, which made that row report idle-vs-total units
## and this badge count soldiers; they are separate signals now, for separate
## questions (project owner, 2026-08-17).
##
## What the badge adds over a number is somewhere to press: an idle villager is a
## mistake the player wants to fix, and a counter that only reports it leaves them
## to go and find the villager themselves.
##
## Reads ONLY from `EventBus`, the separation `ResourceHUD` and `ControlGroupsHud`
## both keep, and emits `cycle_requested` rather than acting: choosing WHICH unit
## is next, selecting it and moving the camera are `GameScene`'s job, exactly as
## `ControlGroupsHud` leaves reselect-and-recentre to it.
##
## Built in `_init()`, not `_ready()`, so a bare `.new()` is fully wired for a
## headless test -- the convention every other HUD widget here follows.
##
## MIRRORED IN THE MOCKUP at `scenes/ui_builder/HUD.tscn`, under
## AgeHeader/Margin/Box/HBoxContainer/VillagersIdle/Circle, as a rounded
## StyleBoxFlat and two Labels -- the same primitives-not-instances arrangement
## `AgeBadge` documents. SIZE, RING_WIDTH, RING_COLOR, FILL_COLOR and the two
## font sizes are the shared contract between the two copies, and
## `test_idle_villager_badge` is the only thing that notices when they drift. Both
## copies were moved together on 2026-08-27.
##
## ONE PIECE OF DRIFT IS LEFT AND IT IS DELIBERATE: the mockup's `VillagersIdle`
## VBox still contains a `PauseButton` above the circle. That button was retired
## from the game on 2026-08-21 (`GameScene` records why -- its actions live behind
## the SETTINGS corner button now), and it is left alone here because the ui_builder
## scenes are the owner's authored design source rather than a mirror this file gets
## to prune. It is why the mockup's column is taller than the game's.
class_name IdleVillagerBadge
extends Button

signal cycle_requested

## 34 px (project owner, 2026-08-27: *"make the circle bigger but still smaller
## than age"*), against the age badge's 44.
##
## IT WAS 22, AND THE REASON IT WAS 22 HAD ALREADY EXPIRED. The note here read
## "half the age badge's 44, because this shares that height with the pause button
## above it" -- and the pause button was retired on 2026-08-21 (`GameScene`, which
## says so), leaving the badge alone in the row with 54 px of header to itself and
## no reason to be half-height. So this is not a resize against a constraint; it is
## a constraint that stopped existing and a number nobody had revisited.
##
## Still deliberately SMALLER than the age badge, which is the owner's wording and
## the right hierarchy: the age is the thing you press to advance the game, and a
## count of idle villagers must not compete with it.
const SIZE := 34.0
const RING_COLOR := Color(0.898039, 0.0, 0.258824, 1.0)
## 2 px, between the old 1 and the age badge's 3 -- a 1 px ring that read as a
## hairline at 22 px reads as a mistake at 34.
const RING_WIDTH := 2.0
const RING_SEGMENTS := 24
const FILL_COLOR := Color(0.17, 0.11, 0.08, 0.9)
## Greyed rather than hidden when there is nothing to walk to, the same choice
## `AgeBadge` makes at the last age: a HUD element that disappears reads as a bug.
const IDLE_NONE_COLOR := Color(0.45, 0.42, 0.38)

const CAPTION := "Idle"
## Vertical gap between the ring and the word now, not horizontal (project owner,
## 2026-08-27: *"move the idle text below the circle"*).
const CAPTION_GAP := 2.0
## The band under the ring the caption is drawn into, so the control's height is
## `SIZE + CAPTION_BAND` rather than a number that has to be kept in step by hand.
## 10 matches `AgeBadge`'s own `SIZE + 10.0`, which puts MAX/ADVANCE under its
## numeral -- the two badges now stack the same way, which is the whole point of
## the change.
const CAPTION_BAND := 10.0
## 14 rather than 10: a 10 px digit centred in a 34 px ring reads as an error.
const COUNT_FONT_SIZE := 14
## 8, the same size `AgeBadge` draws MAX/ADVANCE at, so the two captions under the
## two circles are one typographic row rather than two sizes side by side.
const CAPTION_FONT_SIZE := 8

## Which player this reports on, same filter and same reason as `ResourceHUD`'s.
var player_id: int = 0

var count: int = 0


func _init() -> void:
	# TALLER THAN IT IS WIDE NOW, because the caption is inside the box rather than
	# drawn past its right edge. Same shape as `AgeBadge`'s `SIZE + 10.0`, and it is
	# what lets the header's HBox reserve a column the width of the ring alone --
	# which is what keeps the two badges reading as two circles in a row.
	custom_minimum_size = Vector2(SIZE, SIZE + CAPTION_BAND)
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = "Jump to the next idle villager"
	# A Button paints its own themed StyleBox under this script's _draw() unless
	# every state is emptied -- the trap AgeBadge and ControlGroupSlot both
	# document.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)

	pressed.connect(_on_pressed)
	EventBus.idle_villagers_changed.connect(_on_idle_villagers_changed)


func _exit_tree() -> void:
	EventBus.idle_villagers_changed.disconnect(_on_idle_villagers_changed)


## The whole box -- ring AND the caption band under it -- is pressable.
##
## This override used to exist for the opposite reason: the caption was drawn PAST
## the right edge, outside the control, so the hit test had to be widened sideways
## to make the word pressable. Now that the caption is below and inside
## `custom_minimum_size`, the default `Control` behaviour would very nearly do --
## the override stays because the container stretches this control to the header's
## full 54 px and the default would make that dead space pressable too, so the
## explicit rect is the tighter and more honest answer.
func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, Vector2(SIZE, SIZE + CAPTION_BAND)).has_point(point)


func _on_idle_villagers_changed(p_id: int, idle: int) -> void:
	if p_id != player_id or count == idle:
		return
	count = idle
	queue_redraw()


## Silently does nothing with nothing to walk to, rather than asking GameScene
## for a unit it would then have to refuse. The greyed ring is what says so; a
## toast for a tap on a badge that already reads 0 would be telling the player
## what they just looked at.
func _on_pressed() -> void:
	if count > 0:
		cycle_requested.emit()


func _draw() -> void:
	var tint := HudStyle.GOLD if count > 0 else IDLE_NONE_COLOR
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - RING_WIDTH
	draw_circle(centre, radius, FILL_COLOR)
	draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS,
			RING_COLOR if count > 0 else IDLE_NONE_COLOR, RING_WIDTH, true)

	var font := get_theme_default_font()
	# Three digits do not fit the ring even at 34 px, and a clipped "1" reading as
	# part of the next number is worse than an approximation. A hundred idle
	# villagers is a long way from likely, and this costs one comparison to never be
	# wrong.
	var label := str(count) if count < 100 else "99+"
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, COUNT_FONT_SIZE)
	# draw_string's y is the BASELINE, not the top of the box -- centring on the
	# box height and forgetting that sits the digit a half-line low.
	draw_string(font, Vector2(centre.x - text_size.x * 0.5,
			centre.y + font.get_ascent(COUNT_FONT_SIZE) * 0.5 - 1.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, tint)

	# BELOW THE RING AND CENTRED UNDER IT (project owner, 2026-08-27). Centred by
	# measuring the word rather than by handing `draw_string` a width and an
	# alignment, because the width it would need is the caption band's and the word
	# is narrower than the ring -- so the two ways of centring agree here and
	# measuring is the one that keeps agreeing if the word ever gets longer.
	var caption_size := font.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1,
			CAPTION_FONT_SIZE)
	draw_string(font, Vector2(centre.x - caption_size.x * 0.5,
			SIZE + CAPTION_GAP + font.get_ascent(CAPTION_FONT_SIZE)),
			CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE, tint)
