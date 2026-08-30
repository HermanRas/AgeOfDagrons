## An HP bar (PLAN.md 8.1a/8.1b) that fills proportionally to `fraction`.
##
## TWO PIECES OF ART NOW, WHICH IS WHAT THIS FILE ALWAYS WANTED. It used to draw the
## SAME texture twice -- once darkened to stand in for "empty", once at full
## brightness clipped by `fraction` -- and its header said why: "no such pair exists in
## the pack". One does now (asset_request.md [P8], 2026-08-30) -- see the note on which
## two below. So the `_EMPTY_TINT` multiply is gone, and with it the thing that multiply
## could never fix: a darkened copy of a FULL bar still has the full bar's shape, so an
## empty health bar looked like a dim full one rather than like an empty channel.
##
## BOTH ARE NINE-PATCHED, and they have to be. Stretched flat, the moulded end-caps of
## the channel would smear across the middle and a bar at 20% would show a squashed cap
## rather than a short bar. Horizontal only: neither piece has anything to say
## vertically, so both are drawn at whatever height the lane is.
class_name HealthBarView
extends Control

## THE PAIR IS `field_input` + `button_normal`, NOT `bar_groove` + `bar_fill_health`,
## on the project owner's call (2026-08-30: *"the sheet_bars first and last bar is a
## better match for unit health"*). Those are the first and last rows of the bar sheet
## rather than the two rows named for this job, and the reason they are better is
## shape: `bar_fill_health` is a capsule with rounded caps that stand proud of the
## channel, so a bar at 40 % ends in a dome floating inside a slot. The button plate is
## a flat panel inside a rectangular gold frame, and `field_input` is the matching
## recess — together they read as a bar that empties rather than a pill that shrinks.
##
## THE NAMES NO LONGER DESCRIBE THE USE and that is worth saying out loud. Reusing the
## button plate here is not a bodge; it is the same moulding as every button in the
## game, which is what "everything matches" means. `bar_fill_health` stays in the set
## unused, next to `bar_fill_progress`, which the production queue has not claimed yet.
const _GROOVE_PATH := "res://assets/ui/chrome/field_input.png"
const _FILL_PATH := "res://assets/ui/chrome/button_normal.png"

## The end-cap width, in source pixels, and it is 12 and 14 because
## `tools/prepare_ui_chrome.py` sized these files so that they would be. The two
## differ because they are prepared for different jobs -- `button_normal` is sized so a
## BUTTON's caps read at 14 px -- and using one number for both would smear whichever
## piece it was wrong for.
##
## The masters are ~1000 px wide with measured caps of 23 and 27; Godot draws a
## nine-patch margin AT 1:1, so those would put 50 px of cap on a 176 px bar. See
## `HudStyle.PANEL_MARGIN` for the full version of that trap -- it is the same one, and
## the fix is the same: the source is resized so the number here is the number drawn.
const _GROOVE_PATCH_H := 12
const _FILL_PATCH_H := 14

## The bar's own size when nobody says otherwise.
##
## NOT `texture.get_size()`, which is what this used to be and would now be 1004x102.
## The old art happened to be 176x46 and standing in for a layout decision; the new
## art is a ~1000 px master, so the size has to be stated. `SelectionPanel` overrides
## it with a shorter lane, as it always did.
const DEFAULT_SIZE := Vector2(176.0, 30.0)

var fraction: float = 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if fraction == value:
			return
		fraction = value
		if _fill != null:
			_fill.value = fraction * 100.0

var _fill: TextureProgressBar = null


func _init() -> void:
	custom_minimum_size = DEFAULT_SIZE

	# Nothing in this widget is clickable, and `mouse_filter` does not inherit --
	# a display TextureRect keeps Control's STOP default and eats presses over
	# itself. Harmless where this bar sits today, but it is the same defect that
	# made NoticeToast an invisible hole in the middle of the build grid; see
	# that file's `_init` for what it cost.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ResourceLoader.exists(_GROOVE_PATH):
		var groove := NinePatchRect.new()
		groove.texture = load(_GROOVE_PATH)
		groove.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		groove.patch_margin_left = _GROOVE_PATCH_H
		groove.patch_margin_right = _GROOVE_PATCH_H
		groove.set_anchors_preset(Control.PRESET_FULL_RECT)
		groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(groove)

	if not ResourceLoader.exists(_FILL_PATH):
		return

	# A TextureProgressBar rather than a second NinePatchRect clipped by hand: it
	# already does the left-to-right reveal, and `stretch_margin_*` gives it the same
	# nine-patch behaviour a NinePatchRect would.
	_fill = TextureProgressBar.new()
	_fill.texture_progress = load(_FILL_PATH)
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fill.nine_patch_stretch = true
	_fill.stretch_margin_left = _FILL_PATCH_H
	_fill.stretch_margin_right = _FILL_PATCH_H
	_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_fill.min_value = 0.0
	_fill.max_value = 100.0
	_fill.value = fraction * 100.0
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
