## The SOUND page -- the three volume sliders in a dim-backed overlay, over whatever
## raised it.
##
## ## WHY THIS IS ITS OWN CLASS (2026-09-22, card 2.4c-save-button)
##
## It was `MainMenu._build_settings_overlay()` until the pause menu needed the same page.
## `PauseMenu` used to EMBED a `VolumePanel` directly, and that stopped being possible when
## 2.4c added a fifth button: the volume block costs 185 px of a 300x631 panel, and five
## 76 px buttons under it came to 721 px in a 648 px viewport -- a panel taller than the
## screen it centres on, with the sliders off the top and QUIT off the bottom. The owner's
## call was to move the sliders out rather than shrink the thumb targets.
##
## So this is the front door's overlay, lifted whole rather than copied: both SETTINGS
## buttons now open the same page, and `VolumePanel`'s header already said that was the
## intent ("shared with the front door's SETTINGS button rather than built twice"). What
## was lifted with it is every comment below, each of which records a mistake somebody
## already paid for.
##
## ## A CanvasLayer, NOT A Control, AND EVERY BIT OF THAT MATTERS
##
## The first version of this was a plain `Control` child of the menu and produced a
## screenshot with the volume labels sitting on top of fully-lit PLAY and MULTIPLAYER
## buttons, unreadable.
##
## TWO SEPARATE MISTAKES, both worth naming because both look like z-order and neither is:
##
## 1. **`set_anchors_preset` does not resize anything.** It sets the anchors and then
##    adjusts the OFFSETS to preserve the control's current rect -- and a fresh
##    `Control.new()` has a rect of zero. So the overlay was 0x0, its dim `ColorRect` was
##    0x0 and invisible, while the centered `VBoxContainer` still drew, because Godot does
##    not clip children to a parent's rect unless asked. Content with no backdrop.
##    `set_anchors_and_offsets_preset` sets both.
## 2. **There was no panel behind the content.** `PauseMenu` draws its panel art; this drew
##    straight onto the menu. A dim alone is not enough when what is underneath is bright
##    gold lettering.
##
## A `CanvasLayer` on top of that makes the stacking explicit rather than dependent on
## being the last child added, which is the sort of thing a later `add_child` quietly
## breaks -- and it is why this works unchanged over the pause menu, which is itself a
## full-rect overlay that would otherwise draw over it.
class_name SoundOverlay
extends CanvasLayer

const _PANEL_BG_PATH := "res://assets/ui/chrome/panel_hud.png"

## DERIVED, not guessed. The first attempt hardcoded 300 and the screenshot showed the
## Effects slider and the CLOSE button hanging out of the bottom of the frame -- the same
## class of mistake as `PauseMenu`'s original 320. The panel is whatever its contents need,
## so adding a fourth row cannot repeat it.
const _TITLE_H := 24.0
const _SEP := 16.0
const _CLOSE_H := 44.0
const _CONTENT_TOP := 28.0

## 28, DOWN FROM 72, AND THE OLD NUMBER'S REASONING IS WORTH KEEPING because the trap it
## describes is real and this art simply does not have it. Kibyra's `panel_background.png`
## carried transparent padding, so its visible gold border sat roughly 36 px inside the rect
## it was stretched into: content that stayed inside the RECT still landed on top of the
## border, and the number had to be measured off a screenshot rather than reasoned about.
## `chrome/panel_hud.png` is a nine-patch with a 12 px border and no padding, so what
## content must clear is 12 -- and 28 leaves a comfortable gutter inside it at every size.
const _BOTTOM_MARGIN := 28.0

const _CONTENT_WIDTH := 240.0
const _PANEL_WIDTH := 340.0

## Total height this page needs. A function rather than a literal for `PauseMenu`'s reason:
## a number restated is a number that drifts from the thing it describes.
static func height() -> float:
	return _CONTENT_TOP + _TITLE_H + _SEP + VolumePanel.height() \
			+ _SEP + _CLOSE_H + _BOTTOM_MARGIN


## Held so `open()` can re-read the buses, and so a preview can reach the real sliders.
var _volume: VolumePanel


func _init() -> void:
	layer = 10
	visible = false

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the overlay has to swallow taps, or a thumb landing beside the
	# panel presses the menu button behind it.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var panel_size := Vector2(_PANEL_WIDTH, height())

	# ANCHORS AND OFFSETS SET BY HAND, not via PRESET_CENTER. Setting `position` and `size`
	# after a preset does not stick: the preset has already written offsets for a zero-size
	# rect and the next layout pass re-derives the rect from those, so the panel came out
	# 308 px tall instead of the 379 asked for and the CLOSE button fell through the bottom
	# of the frame. Four offsets against a 0.5/0.5 anchor fully determine the rect and
	# nothing recomputes it.
	var panel := Control.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5
	overlay.add_child(panel)

	if ResourceLoader.exists(_PANEL_BG_PATH):
		var bg := NinePatchRect.new()
		bg.texture = load(_PANEL_BG_PATH)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.patch_margin_left = HudStyle.PANEL_MARGIN
		bg.patch_margin_right = HudStyle.PANEL_MARGIN
		bg.patch_margin_top = HudStyle.PANEL_MARGIN
		bg.patch_margin_bottom = HudStyle.PANEL_MARGIN
		bg.size = panel_size
		panel.add_child(bg)
	else:
		# The panel art was gitignored third-party until 2026-08-30 and a fresh checkout
		# genuinely had none. It commits now, so this branch has stopped being a routine
		# state -- it is kept because it is one line and because without it the sliders draw
		# straight onto what is behind them, which is the bug this whole comment is about.
		var solid := ColorRect.new()
		solid.color = Color(0.12, 0.10, 0.08, 0.98)
		solid.size = panel_size
		panel.add_child(solid)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_SEP))
	box.position = Vector2((panel_size.x - _CONTENT_WIDTH) * 0.5, _CONTENT_TOP)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SOUND"
	UiFont.title(title, 20)
	box.add_child(title)

	_volume = VolumePanel.new(_CONTENT_WIDTH)
	box.add_child(_volume)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(_CONTENT_WIDTH, _CLOSE_H)
	close.pressed.connect(_on_close_pressed)
	box.add_child(close)


## Show the page, with the sliders re-read.
##
## RE-READ RATHER THAN TRUSTED, on `PauseMenu.open()`'s rule: there are two of these pages
## in the game now -- the front door's and the pause menu's -- and whichever was touched
## last is the truth. A page built once and never refreshed shows the volumes as they were
## when it was constructed.
func open() -> void:
	if _volume != null:
		_volume.refresh()
	visible = true


func _on_close_pressed() -> void:
	visible = false
