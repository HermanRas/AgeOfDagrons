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
## font sizes are the shared contract between the two copies; nothing checks that
## they agree.
class_name IdleVillagerBadge
extends Button

signal cycle_requested

## 22 px, half the age badge's 44, because the two stack differently: the age
## badge is one item in a 54 px-tall row and this shares that height with the
## pause button above it. Small for a finger -- which is why `_has_point()` below
## hands the caption's width to the hit test as well.
const SIZE := 22.0
const RING_COLOR := Color(0.898039, 0.0, 0.258824, 1.0)
const RING_WIDTH := 1.0
const RING_SEGMENTS := 24
const FILL_COLOR := Color(0.17, 0.11, 0.08, 0.9)
## Greyed rather than hidden when there is nothing to walk to, the same choice
## `AgeBadge` makes at the last age: a HUD element that disappears reads as a bug.
const IDLE_NONE_COLOR := Color(0.45, 0.42, 0.38)

const CAPTION := "Idle"
const CAPTION_GAP := 4.0
const COUNT_FONT_SIZE := 10
const CAPTION_FONT_SIZE := 8

## Which player this reports on, same filter and same reason as `ResourceHUD`'s.
var player_id: int = 0

var count: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
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


## The caption sits OUTSIDE this control's own 22x22 box -- it is drawn past the
## right edge so the badge stays one square cell in the header's column, which is
## what keeps the pause button above it centred over the ring rather than over a
## ring-plus-word. That would leave "Idle" unpressable, and on a phone 22 px is
## already a small target, so the hit test is widened to cover the word too.
func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, Vector2(SIZE + CAPTION_GAP + _caption_width(), SIZE)) \
			.has_point(point)


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
	# Three digits do not fit a 22 px ring, and a clipped "1" reading as part of
	# the next number is worse than an approximation. A hundred idle villagers is
	# a long way from likely, and this costs one comparison to never be wrong.
	var label := str(count) if count < 100 else "99+"
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, COUNT_FONT_SIZE)
	# draw_string's y is the BASELINE, not the top of the box -- centring on the
	# box height and forgetting that sits the digit a half-line low.
	draw_string(font, Vector2(centre.x - text_size.x * 0.5,
			centre.y + font.get_ascent(COUNT_FONT_SIZE) * 0.5 - 1.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE, tint)

	draw_string(font, Vector2(SIZE + CAPTION_GAP,
			centre.y + font.get_ascent(CAPTION_FONT_SIZE) * 0.5 - 1.0),
			CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE, tint)


func _caption_width() -> float:
	var font := get_theme_default_font()
	if font == null:
		return 0.0
	return font.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1,
			CAPTION_FONT_SIZE).x
