## One circular control-group icon (PLAN.md 10.1/10.4). A `Button` for free
## tap/click hit-testing through Godot's UI system -- `pressed` already fires
## on release-within-bounds for both touch and mouse, the same guarantee
## `InputRouter`'s tap detection provides by hand for the world-space case --
## with a fully custom `_draw()` standing in for the theme's default look.
##
## The ring frame is Kibyra art (see game/assets/LICENCES.md); the icon inside
## it is cropped straight from the entity's own baked battle sprite rather
## than separate portrait art, which does not exist yet (ASSET_MISSING.md
## 1.5). Not truly circle-clipped -- the icon is drawn inset enough that its
## square corners mostly tuck under the ring's own border, a placeholder
## compromise in the same spirit as everywhere else art is not final yet.
class_name ControlGroupSlot
extends Button

const SIZE := 64.0
## Fraction of SIZE trimmed from each edge before drawing the icon, so its
## square corners land under the ring's gold border instead of poking past it.
const ICON_INSET := 0.22
const EMPTY_COLOR := Color(0.25, 0.22, 0.18, 0.6)
const COUNT_BG := Color(0.1, 0.08, 0.05, 0.85)

const _RING_PATH := "res://assets/ui/control_groups/group_slot_ring.png"

var slot: int = 0
var icon_def_id: StringName = &""
var count: int = 0

var _ring: Texture2D = null


func _init(p_slot: int = 0) -> void:
	slot = p_slot
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	flat = true
	# A Button draws its own theme StyleBox before this script's _draw() runs
	# on top -- unlike EntityView's bare Node2D, there IS a default look
	# underneath here unless every state is explicitly emptied out.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	if ResourceLoader.exists(_RING_PATH):
		_ring = load(_RING_PATH)


## Empty icon_def_id draws an empty circle (10.4: "reverts to empty circle
## when emptied").
func set_state(p_icon_def_id: StringName, p_count: int) -> void:
	if icon_def_id == p_icon_def_id and count == p_count:
		return
	icon_def_id = p_icon_def_id
	count = p_count
	queue_redraw()


func _draw() -> void:
	var centre := Vector2(SIZE, SIZE) * 0.5
	var inset := Vector2(SIZE, SIZE) * ICON_INSET
	var icon_rect := Rect2(inset, Vector2(SIZE, SIZE) - inset * 2.0)

	var icon := EntityPortrait.frame_for(icon_def_id) if icon_def_id != &"" else {}
	if icon.is_empty():
		draw_circle(centre, SIZE * 0.5 - inset.x, EMPTY_COLOR)
	else:
		draw_texture_rect_region(icon["texture"], icon_rect, icon["rect"])

	if _ring != null:
		draw_texture_rect(_ring, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)

	if count > 1:
		var label := str(count)
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var badge_pos := Vector2(SIZE - text_size.x - 6.0, SIZE - text_size.y * 0.5 - 2.0)
		draw_circle(Vector2(SIZE - 8.0, SIZE - 8.0), 9.0, COUNT_BG)
		draw_string(font, badge_pos + Vector2(0.0, text_size.y * 0.5), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


