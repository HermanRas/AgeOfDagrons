## The [X] that drops the current selection (PLAN.md 8.8), sitting at the top-left
## of `SelectionPanel`.
##
## It exists because a GESTURE DOES NOT SURVIVE A THUMB. Double-tap on empty ground
## clears the selection and misfires on the phone -- the second tap wobbles, so
## `InputRouter` scores it as a small drag and `DoubleTapDetector` never sees it
## (BUGS.md 2026-08-23). **The gesture stays**, and so does desktop's right-click;
## this is the discoverable version of the same verb, and it does not wait on the
## router's tap/pan discrimination getting better, which is the real root and a
## separate job.
##
## Drawn rather than textured, like `AgeBadge` and `ControlGroupSlot`: a dark disc,
## a gold ring and two strokes. There is no close/X icon in `assets/ui/icons/` and
## commissioning one to reproduce two lines would be the same trade `AgeBadge._draw`
## refuses for its ring.
##
## Emits nothing of its own beyond `Button.pressed` -- `SelectionPanel` turns that
## into `clear_requested` and `GameScene` is what actually clears, the same route
## every other widget here takes into the view's state.
class_name ClearSelectionButton
extends Button

## THIS NUMBER IS THE WHOLE LAYOUT AND IT HAS EXACTLY 40 PX TO LIVE IN.
##
## The left edge of the HUD is fully committed on the 648 px canvas the project
## targets (`window/stretch/aspect = "expand"` keeps the vertical base size on a
## phone, so this is the real budget on hardware too):
##
##   control groups   12 + 5*64 + 4*8  = bottom at y 364
##   selection panel  20 + 72 + 4 + 148 = 244 tall, bottom-anchored -> top at 404
##
## which leaves 40 px between them, and a full 8-verb action row (a castle) is what
## spends the panel's half. At `SIZE` 40 with **zero** separation above the portrait
## row, the worst-case panel top lands on 364 -- flush under the control-group stack,
## no overlap either way. Anything larger, or any separation added below, pushes this
## button under the fifth group slot, which is added to the HUD later and therefore
## hit-tested FIRST: the overlapping strip would go quietly dead. That is the same
## trap the minimap's corner buttons sprang (`GameScene`'s minimap_buttons header).
##
## `MAX_ACTIONS` is what caps the panel at two rows, so 244 is a ceiling by
## construction rather than the tallest panel anyone happened to measure.
const SIZE := 40.0
const RING_COLOR := HudStyle.GOLD
const RING_WIDTH := 2.0
const RING_SEGMENTS := 24
const FILL_COLOR := Color(0.17, 0.11, 0.08, 0.9)
const CROSS_COLOR := HudStyle.GOLD
const CROSS_WIDTH := 3.0
## Fraction of SIZE from the centre to each arm's tip, so the strokes stay inside
## the ring rather than crossing it.
const CROSS_REACH := 0.22


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	# Never grows to the panel's full width: the VBox it sits in would stretch it
	# edge to edge otherwise, and a 320 px wide X is not what a corner close button
	# looks like.
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = "Clear the selection"
	# A Button paints its own themed StyleBox under this script's _draw() unless
	# every state is emptied -- the trap ControlGroupSlot and AgeBadge document.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)


func _draw() -> void:
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - RING_WIDTH
	draw_circle(centre, radius, FILL_COLOR)
	draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS, RING_COLOR, RING_WIDTH, true)

	var reach := SIZE * CROSS_REACH
	draw_line(centre + Vector2(-reach, -reach), centre + Vector2(reach, reach),
			CROSS_COLOR, CROSS_WIDTH, true)
	draw_line(centre + Vector2(-reach, reach), centre + Vector2(reach, -reach),
			CROSS_COLOR, CROSS_WIDTH, true)
