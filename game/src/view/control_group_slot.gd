## One circular control-group icon (PLAN.md 10.1/10.4). A `Button` for free
## tap/click hit-testing through Godot's UI system -- `pressed` already fires
## on release-within-bounds for both touch and mouse, the same guarantee
## `InputRouter`'s tap detection provides by hand for the world-space case --
## with a fully custom `_draw()` standing in for the theme's default look.
##
## The ring is the project's own art since 2026-08-30 (it was Kibyra's until then);
## the icon inside it is cropped straight from the entity's own baked battle sprite
## rather than separate portrait art, which does not exist. Not truly circle-clipped
## -- the icon is drawn inset enough that its square corners tuck inside the ring's
## own border, which is a compromise and reads as none.
class_name ControlGroupSlot
extends Button

const SIZE := 64.0
## Fraction of SIZE trimmed from each edge before drawing the icon, so its
## square corners land under the ring's gold border instead of poking past it.
const ICON_INSET := 0.22
const EMPTY_COLOR := Color(0.25, 0.22, 0.18, 0.6)
const COUNT_BG := Color(0.1, 0.08, 0.05, 0.85)

## The project's own dragon ring since 2026-08-30, replacing Kibyra's
## `rounded-bar-transparent.png`.
##
## SAME PICTURE, OPPOSITE DRAW ORDER. Kibyra's was transparent through the middle and
## went on TOP; this one has a filled dark recess and goes UNDER, or it covers the very
## thing the slot exists to show. `EntityPortraitView` hit the identical inversion the
## same day and its `_draw` carries the general form.
const _RING_PATH := "res://assets/ui/chrome/group_slot_ring.png"

var slot: int = 0
var icon_def_id: StringName = &""
var count: int = 0

## The owning player's skin for the cropped icon. A control group always holds
## the LOCAL player's units (SimPlayer.control_groups is per-player), so unlike
## the selection panel this is one value for the whole stack, set once by
## ControlGroupsHud rather than per slot.
var skin_age: int = 0
var skin_colour: int = -1

var _ring: Texture2D = null


## Repoint the icon's skin. Separate from set_state() because the two change on
## completely different clocks: membership changes several times a second as
## units die, the player's colour never changes and their age three times a
## match.
func set_skin(age: int, colour: int) -> void:
	if skin_age == age and skin_colour == colour:
		return
	skin_age = age
	skin_colour = colour
	queue_redraw()


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

	if _ring != null:
		draw_texture_rect(_ring, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)

	var icon := EntityPortrait.frame_for(icon_def_id, skin_age, skin_colour) \
			if icon_def_id != &"" else {}
	if icon.is_empty():
		# The ring's own recess IS the empty circle 10.4 asks for. The painted disc
		# is only needed when there is no ring art to supply one.
		if _ring == null:
			draw_circle(centre, SIZE * 0.5 - inset.x, EMPTY_COLOR)
	else:
		# Fitted rather than filled, the same as `EntityPortraitView` and for the same
		# reason -- this one simply never looked as wrong, because ICON_INSET is 0.22
		# and the square it stretches into is small enough to hide it.
		draw_texture_rect_region(icon["texture"],
				EntityPortrait.fit(icon, icon_rect), icon["rect"])

	if count > 1:
		var label := str(count)
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var badge_pos := Vector2(SIZE - text_size.x - 6.0, SIZE - text_size.y * 0.5 - 2.0)
		draw_circle(Vector2(SIZE - 8.0, SIZE - 8.0), 9.0, COUNT_BG)
		draw_string(font, badge_pos + Vector2(0.0, text_size.y * 0.5), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


