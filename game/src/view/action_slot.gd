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

## The ring around the one slot of a set that is currently in force -- the stance a unit
## is on, the formation its moves use (`HudAction.selected`).
##
## A BORDER RATHER THAN A FILL OR A TINT, and the choice is forced by what is already in
## the tile. A fill would sit under or over the icon, and every other visual state here is
## already spent: `modulate`'s alpha says enabled, the top strip says cost, the bottom
## strip says name and the corner says badge. The frame's own edge is the last unused
## surface, and a thick gold line on it reads at 72 px on a phone.
##
## DRAWN BY HAND ONLY WHEN THE FRAME ART IS MISSING, since [P8] (2026-08-30). The set
## ships a lit `tile_frame_selected`, which is the same decision made in paint rather
## than in a StyleBox and is a better ring than a flat line. This stays as the fallback,
## because "no art" is a state this file has always drawn something for.
const SELECTED_BORDER := 3
const SELECTED_COLOR := Color(1.0, 0.84, 0.42)

## The name strip over a cropped portrait. Inset to clear the frame art's gold
## border, though by less than the icon is (10): the strip is opaque, so it hides
## the border it overlaps rather than clashing with it, and those few pixels are
## the difference between "Town Center" fitting and reading "Town Cen...".
const CAPTION_HEIGHT := 14.0
const CAPTION_INSET := 6.0
const CAPTION_BG := Color(0.0, 0.0, 0.0, 0.62)
const CAPTION_TEXT := Color(0.96, 0.90, 0.75)
## The least room left at the right end when a badge shares the bottom edge with a
## caption, and the padding between the two.
##
## MEASURED PER BADGE NOW, NOT ASSUMED, and 26 was a literal until 2026-08-30. Two
## things broke it the same day. A research tile gained a caption and its prerequisite
## badge ("Leather Armour") printed straight through it -- that one is fixed properly,
## by moving the prerequisite to `HudAction.requirement` and the top strip, because no
## gap fits two names on a 72 px tile. But the SHORT badges broke it too: the game had
## no typeface at all until that day, and MedievalSharp draws "60%" wider than Godot's
## built-in default did, so a training villager printed its own name through its own
## progress. The general form is that a fixed gap is a guess about a font, and this
## file now has a font it did not choose.
const CAPTION_BADGE_MIN_GAP := 20.0
const CAPTION_BADGE_PAD := 6.0

## `HudAction.requirement`, printed where a cost would go. Muted stone rather than
## gold: gold in that strip has meant "this is the price" since 2026-08-22, and a
## prerequisite is not a price.
##
## NO LOCK GLYPH IN FRONT OF IT, which was tried and pulled the same hour. There is no
## font loaded that has one -- the game draws in Godot's built-in default -- so it
## would have rendered as a tofu box, and the strip is about 60 px at font size 9,
## which is four characters that "Leather Armour" cannot spare. What actually
## disambiguates it is that the tile carries BOTH: the requirement along the top and
## the technology's own name in the caption along the bottom.
const REQUIREMENT_COLOR := Color(0.72, 0.66, 0.56)

const _ICON_DIR := "res://assets/ui/icons/"

## The tile's own chrome, in its three states ([P8], 2026-08-30).
##
## THIS USED TO BE `hud/panel_background.png` -- ONE FILE, AND THE WRONG ONE. It was a
## general-purpose HUD panel pressed into service as a tile frame, and because every
## icon in the old set carried a gold frame drawn INTO it, every action tile in the
## running game was double-framed: a plate inside a plate, with about 30 px of the 52
## left for the picture. The overhaul settled it (owner, 2026-08-30) -- the frame is
## chrome, the icon is a bare glyph, and the glyph gets the whole inset.
##
## THREE FILES RATHER THAN ONE TINTED ONE, and that is what makes them worth having:
## `selected` is lit from behind and `disabled` is drained to grey stone, neither of
## which is a colour multiply of the other. It also means the state costs nothing at
## draw time -- one texture assignment, no shader, no second overlay node.
const _FRAME_PATH := "res://assets/ui/chrome/tile_frame.png"
const _FRAME_SELECTED_PATH := "res://assets/ui/chrome/tile_frame_selected.png"
const _FRAME_DISABLED_PATH := "res://assets/ui/chrome/tile_frame_disabled.png"

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

var _frame: TextureRect
var _icon_rect: TextureRect
var _label: Label
var _caption_bg: ColorRect
var _caption: Label
var _cost_bg: ColorRect
var _cost: Label
var _badge: Label
var _ring: Panel


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
	# transparent-centred overlay: `tile_frame.png` has a filled dark centre, so
	# drawn on top it simply hides whatever the slot is meant to show.
	#
	# NOT NINE-PATCHED, and it does not want to be: this tile is SIZE x SIZE and
	# nothing else, so there is one scale factor and a plain STRETCH_SCALE is exact.
	# A NinePatchRect would also be wrong art-wise -- the corners carry dragons that
	# meet in the middle of each edge, and `tools/measure_ninepatch.py` reports NO
	# CLEAN RUN on two of the three states for exactly that reason.
	if ResourceLoader.exists(_FRAME_PATH):
		_frame = TextureRect.new()
		_frame.texture = load(_FRAME_PATH)
		# LINEAR: the source is 256 px of smooth painted metal drawn at 72, so NEAREST
		# -- correct for every pixel-art asset this file was written against -- turns
		# the moulding into stair-steps. See the sweep of 2026-08-30.
		_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame.stretch_mode = TextureRect.STRETCH_SCALE
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_frame)

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# LINEAR. The icon is 100 px drawn at 52 and the portrait fallback is a crop out
	# of a baked atlas at whatever scale the entity happens to be -- neither is ever
	# at 1:1, and NEAREST at those ratios is what made the old tiles crunchy.
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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

	# LAST, so it draws over the caption and cost strips rather than under them: those
	# are opaque bars running the full width of the tile, and a ring hidden behind two
	# of its own four sides is not a ring. A transparent-centred border, which is why it
	# can sit on top of everything without hiding the thing it is marking -- the same
	# trick `ControlGroupSlot`'s ring uses, and the reason this one is NOT the panel
	# frame above (that one is filled, and on top it would hide the whole slot).
	var ring_box := StyleBoxFlat.new()
	ring_box.bg_color = Color(0, 0, 0, 0)
	ring_box.set_border_width_all(SELECTED_BORDER)
	ring_box.border_color = SELECTED_COLOR
	_ring = Panel.new()
	_ring.add_theme_stylebox_override("panel", ring_box)
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)

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
	# Set before the early returns below, all three of which are "how do I draw the
	# middle of the tile" and none of which should decide whether the ring shows.
	_apply_frame(p_action)
	disabled = not p_action.enabled
	# Greyed rather than hidden: a not-yet-implemented action still shows where
	# it WILL be, see HudAction's own header.
	modulate = Color(1.0, 1.0, 1.0, 1.0 if p_action.enabled else DISABLED_ALPHA)
	_badge.text = p_action.badge
	_set_cost(p_action.cost, p_action.requirement)

	var icon_path := _ICON_DIR + p_action.icon
	if not p_action.icon.is_empty() and ResourceLoader.exists(icon_path):
		_icon_rect.texture = load(icon_path)
		_icon_rect.visible = true
		_label.text = ""
		# NOT captioned, unless the action asks. An icon file means a verb -- Move,
		# Stop, Destroy -- whose icon is already a picture OF the word, so printing
		# "Move" across it adds nothing and costs a fifth of the tile. The caption
		# exists for portraits, where the picture is of a thing and the thing needs
		# naming -- and for `HudAction.captioned`, which is the same case arriving
		# from the other direction: one of four near-identical pictures, where the
		# glyph says what kind of choice this is and only the word says which.
		_set_caption(p_action.label if p_action.captioned else "")
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


## Point the frame at the state this action is in, and fall back to the drawn ring
## when there is no frame art at all.
##
## SELECTED BEATS DISABLED, and the one place they collide says why: a researched
## technology is `selected = true, enabled = false` (9.3), and it is not a broken
## button -- it is a thing you own. The lit frame says so; `modulate` still drains it,
## which is what stops it reading as pressable.
##
## THE HAND-DRAWN RING IS NOT REDUNDANT and is not removed. `_ring` covers the case
## where `_FRAME_PATH` did not load, which is the same "leave it out rather than fake
## it" convention every optional asset load in this codebase follows -- and with no
## frame art there is nothing else in the tile marking which of four is in force.
func _apply_frame(p_action: HudAction) -> void:
	if _frame == null:
		_ring.visible = p_action.selected
		return
	_ring.visible = false
	var path := _FRAME_PATH
	if p_action.selected:
		path = _FRAME_SELECTED_PATH
	elif not p_action.enabled:
		path = _FRAME_DISABLED_PATH
	if ResourceLoader.exists(path):
		_frame.texture = load(path)


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
##
## `requirement` SHARES THIS STRIP and is a fallback, not a second row: a tech you
## cannot buy yet is shown no price, so the two are never both set and there is nothing
## to lay out. It prints in a different colour, because "60F 20G" is something you
## spend and "Iron Casting" is something you go and get -- and it is prefixed with a
## lock rather than left bare, so a two-word name in the cost strip does not read as an
## exotic currency.
func _set_cost(cost: Dictionary, requirement: String = "") -> void:
	if cost.is_empty():
		_cost.text = requirement
		_cost.add_theme_color_override("font_color", REQUIREMENT_COLOR)
		_cost.visible = not requirement.is_empty()
		_cost_bg.visible = _cost.visible
		return
	var parts: Array[String] = []
	for kind in ResourceHUD.DISPLAY_ORDER:
		if cost.has(kind) and int(cost[kind]) > 0:
			parts.append("%s%s" % [_short_amount(int(cost[kind])),
					_COST_LETTERS.get(kind, "?")])
	_cost.text = " ".join(parts)
	_cost.add_theme_color_override("font_color", HudStyle.GOLD)
	_cost.visible = not parts.is_empty()
	_cost_bg.visible = _cost.visible


## A price in as few characters as it can be said in: "30", "1k", "1.5k".
##
## Only the wonder needs this, and it needed it badly -- at 1000 stone and 1000 wood it
## came out as "1000S 1000…", with the ellipsis eating the one digit that was load
## bearing. Eleven characters do not fit the top of a 72 px tile and seven do.
##
## The threshold is 1000 rather than something tuned, because that is exactly where a
## cost stops fitting, and everything else in the game is three digits or fewer and is
## printed in full. A rounded "1.5k" would be a lie about a price if anything ever cost
## 1550 -- nothing does, and the day something might, this is the one place to notice.
static func _short_amount(v: int) -> String:
	if v < 1000:
		return str(v)
	if v % 1000 == 0:
		return "%dk" % (v / 1000)
	return "%.1fk" % (float(v) / 1000.0)


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
		right -= maxf(CAPTION_BADGE_MIN_GAP, _badge_width() + CAPTION_BADGE_PAD)
	_caption.offset_right = right
	_caption_bg.offset_right = right


## How wide the badge's own text actually draws, in this theme, at this size.
##
## ASKED OF THE LABEL RATHER THAN OF `ThemeDB`, so it follows whatever font the project
## is set to -- which is the entire point, since the number this replaced was a guess
## about a typeface the game did not have when it was written.
##
## Returns 0 when there is no font yet, which happens for a slot built outside a
## SceneTree (every headless test does this). The caller then falls back on
## `CAPTION_BADGE_MIN_GAP`, which is what the old fixed number was.
func _badge_width() -> float:
	var font := _badge.get_theme_font("font")
	if font == null:
		return 0.0
	var size := _badge.get_theme_font_size("font_size")
	return font.get_string_size(_badge.text, HORIZONTAL_ALIGNMENT_RIGHT, -1, size).x


func _on_pressed() -> void:
	if action != null and action.enabled:
		action_pressed.emit(action)
