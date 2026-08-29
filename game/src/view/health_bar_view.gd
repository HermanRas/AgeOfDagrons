## An HP bar (PLAN.md 8.1a/8.1b) that fills proportionally to `fraction`.
##
## TWO PIECES OF ART NOW, WHICH IS WHAT THIS FILE ALWAYS WANTED. It used to draw the
## SAME texture twice -- once darkened to stand in for "empty", once at full
## brightness clipped by `fraction` -- and its header said why: "no such pair exists in
## the pack". One does now (asset_request.md [P8], 2026-08-30): `bar_groove` is an
## empty stone channel and `bar_fill_health` is the red liquid that goes in it. So the
## `_EMPTY_TINT` multiply is gone, and with it the thing that multiply could never fix
## -- a darkened copy of a FULL bar still has the full bar's shape, so an empty health
## bar looked like a dim full one rather than like an empty channel.
##
## BOTH ARE NINE-PATCHED, and they have to be. Stretched flat, the moulded end-caps of
## the channel would smear across the middle and a bar at 20% would show a squashed cap
## rather than a short bar. Horizontal only: neither piece has anything to say
## vertically, so both are drawn at whatever height the lane is.
class_name HealthBarView
extends Control

const _GROOVE_PATH := "res://assets/ui/chrome/bar_groove.png"
const _FILL_PATH := "res://assets/ui/chrome/bar_fill_health.png"

## The end-cap width, in source pixels, and it is 12 because
## `tools/prepare_ui_chrome.py` sized these files so that it would be.
##
## The masters are ~1000 px wide with a measured cap of 33; Godot draws a nine-patch
## margin AT 1:1, so 33 would put 66 px of cap on a 176 px bar. See
## `HudStyle.PANEL_MARGIN` for the full version of that trap -- it is the same one, and
## the fix is the same: the source is resized so the number here is the number drawn.
const _PATCH_H := 12

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
		groove.patch_margin_left = _PATCH_H
		groove.patch_margin_right = _PATCH_H
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
	_fill.stretch_margin_left = _PATCH_H
	_fill.stretch_margin_right = _PATCH_H
	_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_fill.min_value = 0.0
	_fill.max_value = 100.0
	_fill.value = fraction * 100.0
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
