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

## The name strip over a cropped portrait. Inset to clear the frame art's gold
## border, though by less than the icon is (10): the strip is opaque, so it hides
## the border it overlaps rather than clashing with it, and those few pixels are
## the difference between "Town Center" fitting and reading "Town Cen...".
const CAPTION_HEIGHT := 14.0
const CAPTION_INSET := 6.0
const CAPTION_BG := Color(0.0, 0.0, 0.0, 0.62)
const CAPTION_TEXT := Color(0.96, 0.90, 0.75)
## Room left at the right end when a badge ("84%") shares the bottom edge, so
## the two do not print over each other.
const CAPTION_BADGE_GAP := 26.0

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
var _caption_bg: ColorRect
var _caption: Label
var _cost_bg: ColorRect
var _cost: Label
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

	# A caption strip across the bottom of the ART, for the slots that show a
	# cropped portrait -- a build or train grid is 12 near-identical brown
	# buildings otherwise, and telling a barracks from a stable at 72 px is not
	# something the sprite alone does.
	#
	# An overlay rather than a row beneath the icon, deliberately: the grid is
	# fixed 72x72 cells and giving each one a text row would either shrink every
	# portrait or grow the panel. This costs the bottom ~22 px of the image,
	# which for an isometric building is its foundation and the least
	# identifying part of it.
	#
	# Added BEFORE the badge so a queue slot's "84%" stays on top of the strip
	# rather than under it.
	_caption_bg = ColorRect.new()
	_caption_bg.color = CAPTION_BG
	_caption_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_bg.offset_left = CAPTION_INSET
	_caption_bg.offset_right = -CAPTION_INSET
	_caption_bg.offset_top = -(CAPTION_INSET + CAPTION_HEIGHT)
	_caption_bg.offset_bottom = -CAPTION_INSET
	_caption_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_bg.visible = false
	add_child(_caption_bg)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 8)
	_caption.add_theme_color_override("font_color", CAPTION_TEXT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A long name is trimmed with an ellipsis rather than wrapped or overflowing:
	# the strip is one line tall by construction, and "Siege Worksho..." still
	# identifies the slot where a second wrapped line would be clipped anyway.
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.clip_text = true
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_left = CAPTION_INSET
	_caption.offset_right = -CAPTION_INSET
	_caption.offset_top = -(CAPTION_INSET + CAPTION_HEIGHT)
	_caption.offset_bottom = -CAPTION_INSET
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	add_child(_caption)

	# WHAT IT COSTS, along the TOP of the tile (project owner, 2026-08-22). Top,
	# because the other three edges are taken: the caption names the thing along the
	# bottom, the badge puts a queue percentage bottom-right, and the middle is the
	# portrait. It is also the least identifying part of an isometric sprite -- the
	# sky above the roof -- which is the same argument the caption makes for the
	# foundation at the other end.
	_cost_bg = ColorRect.new()
	_cost_bg.color = CAPTION_BG
	_cost_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cost_bg.offset_left = CAPTION_INSET
	_cost_bg.offset_right = -CAPTION_INSET
	_cost_bg.offset_top = CAPTION_INSET
	_cost_bg.offset_bottom = CAPTION_INSET + CAPTION_HEIGHT
	_cost_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_bg.visible = false
	add_child(_cost_bg)

	_cost = Label.new()
	_cost.add_theme_font_size_override("font_size", 9)
	_cost.add_theme_color_override("font_color", HudStyle.GOLD)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_cost.clip_text = true
	_cost.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cost.offset_left = CAPTION_INSET
	_cost.offset_right = -CAPTION_INSET
	_cost.offset_top = CAPTION_INSET
	_cost.offset_bottom = CAPTION_INSET + CAPTION_HEIGHT
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost.visible = false
	add_child(_cost)

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
	_set_cost(p_action.cost)

	var icon_path := _ICON_DIR + p_action.icon
	if not p_action.icon.is_empty() and ResourceLoader.exists(icon_path):
		_icon_rect.texture = load(icon_path)
		_icon_rect.visible = true
		_label.text = ""
		# NOT captioned. An icon file means a verb -- Move, Stop, Destroy -- whose
		# icon is already a picture OF the word, so printing "Move" across it adds
		# nothing and costs a fifth of the tile. The caption exists for portraits,
		# where the picture is of a thing and the thing needs naming.
		_set_caption("")
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
		# The name over the picture. A build grid is a dozen brown isometric
		# buildings and a train row several similar soldiers; the sprite says
		# which KIND of thing it is and the caption says which one.
		_set_caption(p_action.label)
		return

	# Nothing drawable -- the centred label carries the whole slot, and a caption
	# strip as well would print the same word twice.
	_icon_rect.visible = false
	_label.text = p_action.label
	_set_caption("")


## Single letters for the four resources, in `ResourceHUD.DISPLAY_ORDER`.
##
## LETTERS RATHER THAN THE ICONS, which is a real loss and bought something. The icons
## exist (`res_wood.png` and friends) and would read faster, but a 72 px tile has room
## for about eighteen characters along its top edge and an icon costs the width of
## three of them -- a stone gate at "40W 75S" fits as text and does not fit as two
## icons, two numbers and a gap. The letters are also unambiguous here in a way they
## would not be in prose: there are exactly four, and no two share a first letter.
const _COST_LETTERS := {&"stone": "S", &"gold": "G", &"wood": "W", &"food": "F"}


## "30W", "60F 20G" -- the price along the top of the tile, or nothing at all for
## something free.
##
## Ordered by `ResourceHUD.DISPLAY_ORDER` rather than by the dictionary, so every cost
## in the game lists its kinds the same way round and in the same order as the counter
## the player reads them off. Dictionary order here would be JSON authoring order,
## which differs entry to entry.
func _set_cost(cost: Dictionary) -> void:
	if cost.is_empty():
		_cost.visible = false
		_cost_bg.visible = false
		return
	var parts: Array[String] = []
	for kind in ResourceHUD.DISPLAY_ORDER:
		if cost.has(kind) and int(cost[kind]) > 0:
			parts.append("%d%s" % [int(cost[kind]), _COST_LETTERS.get(kind, "?")])
	_cost.text = " ".join(parts)
	_cost.visible = not parts.is_empty()
	_cost_bg.visible = _cost.visible


## Show or hide the name strip. Empty text hides both halves, so a slot with no
## portrait never draws a black bar over nothing.
##
## Shortens itself when the slot also carries a badge -- a queue slot shows both
## the unit's name and its "84%" along the same bottom edge, and they would
## otherwise print over each other.
func _set_caption(text: String) -> void:
	var shown := not text.is_empty()
	_caption.text = text
	_caption.visible = shown
	_caption_bg.visible = shown
	if not shown:
		return
	var right := -CAPTION_INSET
	if not _badge.text.is_empty():
		right -= CAPTION_BADGE_GAP
	_caption.offset_right = right
	_caption_bg.offset_right = right


func _on_pressed() -> void:
	if action != null and action.enabled:
		action_pressed.emit(action)
