## Shared look for the HUD panels (UI_Design.md's dark-brown/gold language):
## `panel_background.png` plus the gold accent colour. `SelectionPanel`
## originated this look; `ResourceHUD` and `Minimap` now share it through here
## instead of each re-loading the texture and re-typing the colour, so the
## three read as one system rather than three one-off implementations.
class_name HudStyle
extends RefCounted

const PANEL_BG_PATH := "res://assets/ui/hud/panel_background.png"
const GOLD := Color("#E5B842")
const DARK_BG := Color("#2B1D14")

## Adds `panel_background.png` as a full-rect, mouse-ignoring backdrop behind
## `target`'s other children. Returns null (adding nothing) if the art is
## missing, the same "leave it out rather than fake it" convention every other
## optional asset load in this codebase follows.
static func add_panel_background(target: Control) -> TextureRect:
	# PanelContainer/Panel draw their own themed "panel" StyleBox regardless of
	# what children are added -- left alone, its default rectangular fill shows
	# through the art's transparent, rounded corners as a shadow-like halo (found
	# live comparing the in-editor HUD builder against the running game).
	target.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	if not ResourceLoader.exists(PANEL_BG_PATH):
		return null
	var bg := TextureRect.new()
	bg.texture = load(PANEL_BG_PATH)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	# Without this, the texture's own pixel size becomes this TextureRect's
	# minimum size, which -- for a panel whose real content is smaller than
	# the art (the age header stub is just a title and a thin bar) -- forces
	# the whole PanelContainer to balloon out to fit the background instead of
	# the background scaling down to fit the content.
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(bg)
	target.move_child(bg, 0)
	return bg
