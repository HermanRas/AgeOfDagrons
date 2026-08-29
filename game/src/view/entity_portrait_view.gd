## A small portrait crop of an entity's def, framed (PLAN.md 8.1a/8.1c). Reused for
## both `SelectionPanel`'s single-unit portrait and each cell of its multi-select
## grid -- pure display, no interaction, unlike `ControlGroupSlot` which is the same
## crop-and-frame trick wrapped in a `Button`.
##
## The frame was Kibyra's avatar ring until 2026-08-30 and is now the project's own
## `chrome/portrait_frame.png` -- a studded gold square rather than a ring, which is
## why the inset below changed with it.
class_name EntityPortraitView
extends Control

const SIZE := 72.0
const EMPTY_COLOR := Color(0.25, 0.22, 0.18, 0.6)
const _FRAME_PATH := "res://assets/ui/chrome/portrait_frame.png"

## How far inside the frame the picture is drawn, as a fraction of SIZE.
##
## SMALLER THAN THE 0.14 IT REPLACES, and the reason is the shape of the new frame
## rather than taste. The old one was a ring: a square crop inside a circle has to
## clear the circle at the CORNERS, where the border is furthest in, so it needed a
## fat inset and lost a fifth of the portrait to it. The new frame is a square with an
## even border, so the crop only has to clear that border -- measured at 53 px of a
## 254 px source, which is 0.21 of it, but the inner rebate is dark and the picture is
## meant to sit on it. 0.10 puts the crop just inside the gold.
const FRAME_INSET := 0.10

var def_id: StringName = &"":
	set(value):
		if def_id == value:
			return
		def_id = value
		queue_redraw()

## The skin of whoever OWNS what is portrayed -- not of the local player. A
## selected enemy unit shows its own colour here, which is the whole reason the
## portrait carries one (PLAN.md 1). Defaults to unaged/untinted so a caller that
## has not been updated draws exactly what it drew before.
var skin_age: int = 0:
	set(value):
		if skin_age == value:
			return
		skin_age = value
		queue_redraw()

var skin_colour: int = -1:
	set(value):
		if skin_colour == value:
			return
		skin_colour = value
		queue_redraw()

var _frame: Texture2D = null


## Both axes at once, so a caller cannot leave the portrait half-re-skinned --
## the same pairing EntityView.set_skin() makes for the world sprite.
func set_skin(age: int, colour: int) -> void:
	skin_age = age
	skin_colour = colour


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	if ResourceLoader.exists(_FRAME_PATH):
		_frame = load(_FRAME_PATH)


## THE FRAME GOES UNDER THE PORTRAIT NOW, AND IT DID NOT USED TO.
##
## Kibyra's avatar frame was a RING -- transparent in the middle -- so drawing it last
## put a border over the crop and was right. `chrome/portrait_frame.png` is a plate:
## gold moulding around a filled dark recess. Drawn last it covers the portrait
## completely, which is exactly what the first run of `preview_match` after the swap
## showed: a town centre selected, and an empty brown square where its picture goes.
##
## Worth keeping as a class, because it is not obvious from a filename: SWAPPING ONE
## FRAME FOR ANOTHER CAN INVERT THE DRAW ORDER, and the question to ask of any
## replacement is whether its middle is transparent. `ActionSlot` and
## `ControlGroupSlot` sit on opposite sides of the same question and both say so.
func _draw() -> void:
	if _frame != null:
		draw_texture_rect(_frame, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)

	var inset := SIZE * FRAME_INSET
	var icon_rect := Rect2(Vector2(inset, inset), Vector2(SIZE, SIZE) - Vector2(inset, inset) * 2.0)

	var icon := EntityPortrait.frame_for(def_id, skin_age, skin_colour) if def_id != &"" else {}
	if icon.is_empty():
		# Nothing at all when the frame is there: the plate's own recess IS the empty
		# state, and a flat swatch painted over it only hides the moulding. The
		# swatch stays for the no-art case, where without it the widget is invisible.
		if _frame == null:
			draw_rect(icon_rect, EMPTY_COLOR)
	else:
		# FITTED, NOT FILLED. A baked idle frame is taller than it is wide -- a villager
		# is about 40x70 -- and painted straight into this square she comes out a third
		# too wide. See `EntityPortrait.fit`.
		draw_texture_rect_region(icon["texture"],
				EntityPortrait.fit(icon, icon_rect), icon["rect"])
