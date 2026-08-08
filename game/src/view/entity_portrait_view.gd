## A small portrait crop of an entity's def, framed by the Kibyra avatar ring
## (PLAN.md 8.1a/8.1c). Reused for both `SelectionPanel`'s single-unit
## portrait and each cell of its multi-select grid -- pure display, no
## interaction, unlike `ControlGroupSlot` which is the same crop-and-frame
## trick wrapped in a `Button`.
class_name EntityPortraitView
extends Control

const SIZE := 72.0
const EMPTY_COLOR := Color(0.25, 0.22, 0.18, 0.6)
const _FRAME_PATH := "res://assets/ui/hud/portrait_frame.png"

var def_id: StringName = &"":
	set(value):
		if def_id == value:
			return
		def_id = value
		queue_redraw()

var _frame: Texture2D = null


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	if ResourceLoader.exists(_FRAME_PATH):
		_frame = load(_FRAME_PATH)


func _draw() -> void:
	var inset := SIZE * 0.14
	var icon_rect := Rect2(Vector2(inset, inset), Vector2(SIZE, SIZE) - Vector2(inset, inset) * 2.0)

	var icon := EntityPortrait.frame_for(def_id) if def_id != &"" else {}
	if icon.is_empty():
		draw_circle(Vector2(SIZE, SIZE) * 0.5, SIZE * 0.5 - inset, EMPTY_COLOR)
	else:
		draw_texture_rect_region(icon["texture"], icon_rect, icon["rect"])

	if _frame != null:
		draw_texture_rect(_frame, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
