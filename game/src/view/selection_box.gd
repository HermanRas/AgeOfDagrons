## The rectangle drawn while a two-finger box select is in progress (PLAN.md 8.3).
##
## Lives on the HUD CanvasLayer and works in SCREEN coordinates, because that is
## where the fingers are. Converting to world space to draw it would make the box
## slide around under the fingers holding it if the camera moved.
class_name SelectionBox
extends Control

const LINE_COLOR := Color(0.35, 1.0, 0.45, 0.95)
const FILL_COLOR := Color(0.35, 1.0, 0.45, 0.12)
const LINE_WIDTH := 2.0

var _rect := Rect2()


func _ready() -> void:
	# Never eat input: the fingers drawing this box are still being read by the
	# router underneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_box(screen_rect: Rect2) -> void:
	_rect = screen_rect
	visible = true
	queue_redraw()


func hide_box() -> void:
	visible = false
	_rect = Rect2()
	queue_redraw()


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	draw_rect(_rect, FILL_COLOR, true)
	draw_rect(_rect, LINE_COLOR, false, LINE_WIDTH)
