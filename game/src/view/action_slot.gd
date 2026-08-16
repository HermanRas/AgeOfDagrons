## One 72x72 cell of the selection panel -- an action in the left column or an
## entry in the right detail grid (UI_Design.md selection-panel redesign).
##
## A `Button` for the same reason `ControlGroupSlot` is one: `pressed` already
## resolves tap/click-within-bounds for touch and mouse alike, so nothing here
## re-implements hit testing. Its theme styleboxes are emptied out and the look
## is drawn from children instead, the same trick that file documents.
##
## Draws, in order of preference: the action's own icon file; failing that the
## portrait cropped from `payload`'s baked sprite (`EntityPortrait`, which is
## how train/place/roster cells show what they are without dedicated art);
## failing that the label text alone. Every fallback still reads as something,
## which is what lets a not-yet-drawn icon ship greyed rather than blank.
class_name ActionSlot
extends Button

const SIZE := 72.0
const EMPTY_COLOR := Color(0.25, 0.22, 0.18, 0.6)
const DISABLED_ALPHA := 0.4

const _ICON_DIR := "res://assets/ui/icons/"
const _FRAME_PATH := "res://assets/ui/hud/panel_background.png"

## Emitted instead of the bare `pressed` so a listener gets the action back
## without having to remember which slot index held what.
signal action_pressed(action: HudAction)

var action: HudAction = null

## Skin for the portrait fallback below, when a slot has no icon file and crops
## the entity's own sprite instead. Whoever's building is selected is whoever
## would own what it trains, so this is the SELECTION OWNER's skin -- a captured
## enemy barracks offering units in their colour would be a lie about what
## pressing the button produces.
##
## Plain fields rather than setters: `set_action()` re-runs on every refresh and
## rebuilds the crop from scratch, so there is nothing to invalidate. The panel
## assigns these immediately before it, and the pair is documented as an
## ordering requirement there rather than enforced here, because enforcing it
## would mean a setter that re-crops without an action to crop.
var portrait_age: int = 0
var portrait_colour: int = -1

var _icon_rect: TextureRect
var _label: Label
var _badge: Label


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	flat = true
	clip_contents = true
	# A Button paints its own themed StyleBox under this script's children
	# unless every state is explicitly emptied -- exactly what ControlGroupSlot
	# documents, and the same reason HudStyle.add_panel_background() now clears
	# the "panel" box on PanelContainers.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)

	var bg := ColorRect.new()
	bg.color = EMPTY_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The frame goes UNDER the icon, unlike ControlGroupSlot's ring which is a
	# transparent-centred overlay: `panel_background.png` is a filled panel, so
	# drawn on top it simply hides whatever the slot is meant to show.
	if ResourceLoader.exists(_FRAME_PATH):
		var frame := TextureRect.new()
		frame.texture = load(_FRAME_PATH)
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset so the icon sits inside the frame's gold border rather than over it,
	# the same reasoning as ControlGroupSlot.ICON_INSET.
	_icon_rect.offset_left = 10.0
	_icon_rect.offset_top = 10.0
	_icon_rect.offset_right = -10.0
	_icon_rect.offset_bottom = -10.0
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	# Sits over the frame: it is the readable fallback when there is no art, so
	# it must not be hidden behind the border.
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 4.0
	_label.offset_right = -4.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 11)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badge.offset_right = -5.0
	_badge.offset_bottom = -3.0
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	pressed.connect(_on_pressed)


## Repoints this slot at `p_action`, or empties it for `null`. Slots are
## rebuilt in place rather than freed and recreated so a selection changing
## every snapshot does not churn nodes (the same reason `EntityViewPool`
## exists for the world layer).
func set_action(p_action: HudAction) -> void:
	action = p_action
	if p_action == null:
		visible = false
		return

	visible = true
	disabled = not p_action.enabled
	# Greyed rather than hidden: a not-yet-implemented action still shows where
	# it WILL be, see HudAction's own header.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if p_action.enabled else DISABLED_ALPHA)
	_badge.text = p_action.badge

	var icon_path := _ICON_DIR + p_action.icon
	if not p_action.icon.is_empty() and ResourceLoader.exists(icon_path):
		_icon_rect.texture = load(icon_path)
		_icon_rect.visible = true
		_label.text = ""
		return

	# No icon file: crop the entity's own baked sprite, the same standing-in-for
	# portrait art trick `EntityPortrait` already serves ControlGroupSlot. Wrapped
	# in an AtlasTexture rather than an `EntityPortraitView` so this slot keeps
	# ONE frame (its own) instead of stacking the portrait ring on top of it.
	var def_id: StringName = p_action.payload if p_action.payload is StringName else &""
	var crop := EntityPortrait.frame_for(def_id, portrait_age, portrait_colour) \
			if def_id != &"" else {}
	if not crop.is_empty():
		var atlas := AtlasTexture.new()
		atlas.atlas = crop["texture"]
		atlas.region = crop["rect"]
		_icon_rect.texture = atlas
		_icon_rect.visible = true
		_label.text = ""
		return

	# Nothing drawable -- the label carries the whole slot.
	_icon_rect.visible = false
	_label.text = p_action.label


func _on_pressed() -> void:
	if action != null and action.enabled:
		action_pressed.emit(action)
