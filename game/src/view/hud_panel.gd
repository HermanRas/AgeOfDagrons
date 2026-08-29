## Shared chrome for the three full-screen HUD pages behind the minimap's corner
## buttons (PLAN.md 8.2b): CHAT, the TECHNOLOGY TREE and the MARKET.
##
## Written once because the three are the same object with different insides -- a
## dimmed backdrop, a framed panel, a title, a body and a row of buttons along the
## bottom -- and three hand-rolled copies of that is three places for the margins
## to drift apart. `PauseMenu` and `ResultScreen` are deliberately NOT ported onto
## this: they are small centred boxes with a fixed 300x320, this is a page, and
## merging the two would give one class two layouts.
##
## THE CLOCK KEEPS RUNNING, which is the difference that matters between these
## pages and `PauseMenu`. A market has to show live stockpiles to be worth opening,
## and in a network match a local pause was never a pause anyway -- the host goes
## on ticking whatever this device does (see `PauseMenu`'s own header). So the
## match carries on underneath, and closing the page does not resume anything.
##
## Sized in MARGINS from the screen edge rather than in pixels, so the same page
## fills a 1152x648 desktop viewport and a phone in landscape without a second set
## of numbers. `window/stretch/mode` is `canvas_items`, so this is a real layout
## rather than a scaled bitmap.
##
## IT DOES NOT USE `panel_background.png`, and that was tried first. That texture is
## 160x192 -- a small PORTRAIT panel carrying a heavy gold dragon ornament, sized for
## the resource counter and the selection panel. Stretched across a 872x568 landscape
## page the dragon inflates into the middle of the content and reads as damage rather
## than decoration (photographed, 2026-08-21). So these pages take the line `Minimap`
## already took when the pack had no art at its shape: a flat dark fill with a DOUBLE
## GOLD BORDER, which is the nearest a plain style box gets to the look the art gives
## everything else, and is honest about being a stand-in.
##
## The mockups frame their title in a gold dragon arch and that art does not exist
## either, so the title is a gold label centred along the top edge. When the arch is
## baked it replaces `_title`, the fill becomes a `TextureRect` again, and nothing
## about the layout below has to move.
class_name HudPanel
extends Control

## Emitted when the page closes, however it closed. `GameScene` listens so it can
## drop whatever it was holding open; nothing here assumes anybody is.
signal closed()

## Distance from each screen edge. Landscape-shaped on purpose: these pages are
## read at arm's length on a phone held sideways, so the vertical margin is the
## tight one and the horizontal margin is what keeps the text off the bezel.
const MARGIN_H := 120.0
const MARGIN_V := 36.0

const TITLE_FONT_SIZE := 26
const _BUTTON_MIN := Vector2(180.0, 44.0)

## Filled by the subclass. A plain `Control` rather than a container, so a page can
## choose its own layout -- the market wants two stacked sections, the tech tree
## wants a grid, and imposing a VBox here would have both fighting it.
var body: Control

var _title: Label
var _footer: HBoxContainer
var _close_button: Button


## Built in `_init()`, the convention every widget in `src/view/` follows: a bare
## `.new()` is fully wired, so a test can press a button without a SceneTree.
##
## EVERY SUBCLASS MUST CALL `super()` FIRST, and it is worth knowing why rather than
## copying it: GDScript only calls a base `_init()` implicitly when the subclass does
## not declare one of its own. All three pages do, so without the explicit call the
## chrome is never built and the first `set_title()` fails on a null label -- which is
## exactly how this was found. It takes no arguments so there is nothing to get wrong
## in the call; the title is set afterwards with `set_title()`.
func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE. A page open over the game must swallow the taps that land on
	# it, or an order would go out to whatever unit happens to be under the panel --
	# and on this project that is not hypothetical, because `InputRouter` reaches the
	# world through `_unhandled_input` and never asks a Control's filter anything.
	# What DOES need the filter is the dim: see below.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The dim is decoration; this node above is what blocks. Left on Control's STOP
	# default it would also block, harmlessly -- but `NoticeToast` and `ResourceHUD`
	# both record what a display node left on STOP did to the controls beneath it,
	# and the habit is cheaper than the exception.
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", page_style())
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = MARGIN_H
	frame.offset_right = -MARGIN_H
	frame.offset_top = MARGIN_V
	frame.offset_bottom = -MARGIN_V
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.title(_title, TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	column.add_child(_title)

	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 12)
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_footer)


## The page's fill and border. A DOUBLE gold edge -- an outer band with a thinner
## line set in from it -- which is exactly what `Minimap._draw` does with two
## `draw_rect` calls, and for the same reason: it is the nearest a plain style box
## gets to the gold-on-dark edge `panel_background.png` gives every other panel.
## Godot's `StyleBoxFlat` draws one border, so the inner line is a second box the
## caller lays under the content; here it is the border plus a generous content
## margin, which reads the same at this size and costs one node instead of two.
##
## Static so `ColourPickerPopup` can wear the same skin without inheriting a page.
static func page_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Not fully opaque: the match is still running underneath (these pages do not
	# stop the clock) and a sliver of it showing through says so.
	style.bg_color = Color(HudStyle.DARK_BG, 0.97)
	style.border_color = HudStyle.GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	return style


func title() -> String:
	return _title.text


func set_title(text: String) -> void:
	_title.text = text


func open() -> void:
	# EVERY PAGE CLOSES. A subclass adds its own buttons and then calls
	# `add_close_button()` last, so the row reads the way its mockup does -- but a
	# page that forgot is a page a phone cannot leave, because there is no Escape
	# key on a phone (the same dead end the build-mode cancel button exists to fix,
	# BUGS.md). Checked here rather than trusted: this is the moment it would matter.
	if _close_button == null:
		add_close_button()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## The bottom button row, for a subclass that needs to reorder it. Exposed as a
## function rather than by reaching for `_footer`, so "the footer is an HBox built
## left to right" stays a fact about this class and not one every page depends on.
func footer() -> HBoxContainer:
	return _footer


## A button along the bottom row. Returned so a caller can hold it, disable it, or
## have a preview press the real thing rather than call its handler.
func add_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = _BUTTON_MIN
	b.add_theme_font_size_override("font_size", 18)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	_footer.add_child(b)
	return b


func add_close_button() -> Button:
	if _close_button == null:
		_close_button = add_button("CLOSE", close)
	return _close_button


func close_button() -> Button:
	return _close_button


## Gold body text, which is what every label on these pages is. Here rather than
## repeated per page so one font-size change moves all three.
static func text_label(text: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	return label


## A dimmer label for the things a page says ABOUT itself -- a wireframe notice, a
## precondition that is not met, a price. Distinguished by weight rather than by
## another colour, since gold-on-brown is the whole palette.
static func note_label(text: String, font_size: int = 14) -> Label:
	var label := text_label(text, font_size)
	label.add_theme_color_override("font_color", Color(HudStyle.GOLD, 0.65))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A player's colour as a small square.
##
## SHRINK ON BOTH AXES, which is the whole reason this is shared rather than three
## lines inlined per page: a `ColorRect` in an `HBoxContainer` fills the row's height
## by default, so the first version of this came out as a tall thin bar rather than a
## chip (photographed, 2026-08-21). `custom_minimum_size` does not prevent it -- it is
## a minimum, and filling is what the container does with the rest.
static func colour_chip(colour_index: int, px: float = 16.0) -> ColorRect:
	var chip := ColorRect.new()
	chip.color = GameDataRegistry.colour(colour_index) if GameDataRegistry != null \
			else Color.WHITE
	chip.custom_minimum_size = Vector2(px, px)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


## One resource's icon as a texture, or null when the art has not landed -- the
## "leave it out rather than fake it" convention every optional asset load here
## follows. Separate from `resource_icon()` because a `Button.icon` wants the
## texture and building a throwaway `TextureRect` to reach `.texture` leaks a node.
static func resource_texture(kind: StringName) -> Texture2D:
	var path := "res://assets/ui/icons/res_%s.png" % kind
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## One resource's icon at label height, or null when the art is absent -- callers
## add it only if it came back, the convention `ResourceHUD._add_badge` follows.
## Shared with the market page, which draws one of these per exchange row.
static func resource_icon(kind: StringName, px: float = 20.0) -> TextureRect:
	var texture := resource_texture(kind)
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Without this the icon pack's own 100x100 becomes the minimum size regardless
	# of what is asked for below -- the bug that ballooned `ResourceHUD` to 532 px
	# and off the bottom of the viewport.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(px, px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
