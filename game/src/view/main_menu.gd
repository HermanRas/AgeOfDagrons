## The literal front door of the product (PLAN.md 1.1/1.2). Layout is
## authored in MainMenu.tscn (editable in the Godot editor), the same
## `.tscn`-first convention `Credits.tscn` moved to first -- this script only
## wires the buttons to what pressing them does.
##
## PLAY, MULTIPLAYER and CREDITS have real behaviour.
##
## THE TWO USED TO GO TO THE SAME PLACE, and that was the honest consequence of 1.6's
## design: a lobby is the skirmish screen with a slot set to Open, so there was exactly one
## screen and PLAY had nowhere of its own to lead. What it cost was the front door -- either
## button did the same thing, and the campaign 12.3 has always had a row for was reachable
## from nothing. PLAY now opens the CAMPAIGN screen (a placeholder that says so, and the
## frame 12.3's mission list will appear in) and MULTIPLAYER opens the skirmish/lobby
## screen, so each button leads somewhere only it leads.
##
## WHICH MEANS A SOLO SKIRMISH IS BEHIND "MULTIPLAYER", and that is the wrinkle worth
## knowing about. The screen is both -- all-local slots is a skirmish, an Open slot is a
## lobby -- so nothing is unreachable, but a player wanting a game against the AI presses a
## button labelled multiplayer to get there. The fix is a label, not a screen, and the
## project owner has the menu art in hand.
##
## SETTINGS IS REAL NOW, and holds exactly one thing: volume (PLAN.md 8.2b, 13.2 item
## 11). It used to answer with a `NoticeToast` saying settings were not available, which
## was true until audio existed and is the kind of line that outlives its reason -- a
## player who wants the music down looks here first, and the in-match SETTINGS page is
## behind starting a match. It is the same `VolumePanel` that page uses.
##
## HOW TO IS REAL SINCE 2026-08-30, and was a toast saying the guide did not exist for
## as long as no guide did. It opens `Help.tscn`, the six annotated captures the owner
## drew over this game's own HUD -- see `help_screen.gd` for why they are a pager and
## not a scroll. Every front-door button now leads to a screen except QUIT.
extends Control

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _CREDITS_SCENE := "res://scenes/menu/Credits.tscn"
const _HELP_SCENE := "res://scenes/menu/Help.tscn"
const _SKIRMISH_SCENE := "res://scenes/menu/Skirmish.tscn"
const _CAMPAIGN_SCENE := "res://scenes/menu/Campaign.tscn"
## The same panel art `PauseMenu` uses, so the two SETTINGS pages match.
const _PANEL_BG_PATH := "res://assets/ui/chrome/panel_hud.png"

## THE SIX BUTTONS ARE `Button`s WITH TEXT, and were six `TextureButton`s with the word
## painted into the art until 2026-08-30. Nine files in `assets/ui/menu/` differed only
## in which word was on them, which meant a new menu entry cost a piece of art, a
## renamed one cost a re-render, and there was no pressed or disabled state at all
## because nobody was going to draw twenty-seven files.
##
## One plate in three states lives in `assets/ui/aod_theme.tres` and reaches every
## Button in the project, so this scene carries no button art of its own and the
## SETTINGS overlay's CLOSE button -- built in code, below -- matches the front door
## without asking to.

@onready var _play_button: Button = %PlayButton
@onready var _multiplayer_button: Button = %MultiplayerButton
@onready var _settings_button: Button = %SettingsButton
@onready var _credits_button: Button = %CreditsButton
@onready var _how_to_button: Button = %HowToButton
@onready var _quit_button: Button = %QuitButton
## NOTHING PRESSES THIS ANY MORE, as of 2026-08-30: HOW TO was the last button that
## answered with a toast instead of a screen. Kept, with its node in the .tscn, because
## the front door will want a way to say something in passing again -- and because a
## toast that has to be re-authored is how a button ends up doing nothing at all.
@onready var _toast: NoticeToast = %Toast
## The game's name, authored in the .tscn because that is where the layout is. The
## FACE is set here rather than there for the reason `_build_settings_overlay`'s header
## gives about `.tscn` files: Godot rewrites their properties when the project is open,
## and a theme override is exactly the sort of property that drifts. It is also the one
## label in the game most obviously a NAME, which is what `UiFont.title` is for.
@onready var _title: Label = $PanelRoot/Title

## The SETTINGS overlay, built on first press and kept. See `_on_settings_pressed`.
var _settings_overlay: CanvasLayer = null
var _volume: VolumePanel = null


func _ready() -> void:
	UiFont.title(_title, 40, true)
	_play_button.pressed.connect(_on_play_pressed)
	# THE SKIRMISH AND LOBBY SCREEN, which is one screen because a skirmish and a lobby
	# differ only in what fills a player slot (1.6): all-local slots plays at once, and
	# setting a slot to Open opens the socket. There is no separate host button to forget.
	#
	# It used to open the throwaway 12.1g entry point, which was deleted once this screen
	# had hosted a real two-device match (confirmed 2026-08-21: phone joined a PC host
	# over WiFi, reviewed the map, pressed READY and played).
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_how_to_button.pressed.connect(_on_how_to_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())

	# The front door's music. `play_music` is a no-op if this track is already
	# playing, so coming back from Credits or a finished match does not restart
	# it mid-phrase; leaving for a MATCH is what replaces it, because
	# `MatchAudio` calls `play_music` with the age's track on its first snapshot.
	AudioManager.play_music(&"menu.theme")


## SETTINGS: the volume panel, in a dim-backed overlay built on first use.
##
## Built lazily and kept, rather than authored into MainMenu.tscn, for the reason
## §6 of AGENT_GAME_CODER.md gives: Godot rewrites `.tscn` layout properties when
## the project is open, and MainMenu.tscn is one of the authored mockups that
## should not drift. A panel made in code cannot be silently reformatted.
func _on_settings_pressed() -> void:
	if _settings_overlay == null:
		_settings_overlay = _build_settings_overlay()
		add_child(_settings_overlay)
	_volume.refresh()
	_settings_overlay.visible = true


## A CanvasLayer, not a Control, and every bit of that matters -- the first
## version of this was a plain `Control` child of the menu and produced a
## screenshot with the volume labels sitting on top of fully-lit PLAY and
## MULTIPLAYER buttons, unreadable.
##
## TWO SEPARATE MISTAKES, both worth naming because both look like z-order and
## neither is:
##
## 1. **`set_anchors_preset` does not resize anything.** It sets the anchors and
##    then adjusts the OFFSETS to preserve the control's current rect -- and a
##    fresh `Control.new()` has a rect of zero. So the overlay was 0x0, its dim
##    `ColorRect` was 0x0 and invisible, while the centered `VBoxContainer` still
##    drew, because Godot does not clip children to a parent's rect unless asked.
##    Content with no backdrop. `set_anchors_and_offsets_preset` sets both.
## 2. **There was no panel behind the content.** `PauseMenu` draws
##    `panel_background.png`; this drew straight onto the menu. A dim alone is not
##    enough when what is underneath is bright gold lettering.
##
## A `CanvasLayer` on top of that makes the stacking explicit rather than
## dependent on being the last child added, which is the sort of thing a later
## `add_child` quietly breaks.
func _build_settings_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 10

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the overlay has to swallow taps, or a thumb landing
	# beside the panel presses the menu button behind it.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# DERIVED, not guessed. The first attempt hardcoded 300 and the screenshot
	# showed the Effects slider and the CLOSE button hanging out of the bottom of
	# the frame -- the same class of mistake as PauseMenu's original 320. The
	# panel is whatever its contents need, so adding a fourth row cannot repeat it.
	const _TITLE_H := 24.0
	const _SEP := 16.0
	const _CLOSE_H := 44.0
	const _CONTENT_TOP := 28.0
	# 28, DOWN FROM 72, AND THE OLD NUMBER'S REASONING IS WORTH KEEPING because the
	# trap it describes is real and this art simply does not have it. Kibyra's
	# `panel_background.png` carried transparent padding, so its visible gold border
	# sat roughly 36 px inside the rect it was stretched into: content that stayed
	# inside the RECT still landed on top of the border, and the number had to be
	# measured off a screenshot rather than reasoned about. `chrome/panel_hud.png` is
	# a nine-patch with a 12 px border and no padding, so what content must clear is
	# 12 -- and 28 leaves a comfortable gutter inside it at every panel size.
	const _BOTTOM_MARGIN := 28.0
	var content_height := (_TITLE_H + _SEP + VolumePanel.height()
			+ _SEP + _CLOSE_H)
	var panel_size := Vector2(
		340.0, _CONTENT_TOP + content_height + _BOTTOM_MARGIN)

	# ANCHORS AND OFFSETS SET BY HAND, not via PRESET_CENTER. Setting `position`
	# and `size` after a preset does not stick: the preset has already written
	# offsets for a zero-size rect and the next layout pass re-derives the rect
	# from those, so the panel came out 308 px tall instead of the 379 asked for
	# and the CLOSE button fell through the bottom of the frame. Four offsets
	# against a 0.5/0.5 anchor fully determine the rect and nothing recomputes it.
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
		# The panel art was gitignored third-party until 2026-08-30 and a fresh
		# checkout genuinely had none. It commits now, so this branch has stopped
		# being a routine state -- it is kept because it is one line and because
		# without it the sliders draw straight onto the menu, which is the bug this
		# whole comment is about.
		var solid := ColorRect.new()
		solid.color = Color(0.12, 0.10, 0.08, 0.98)
		solid.size = panel_size
		panel.add_child(solid)

	var content_width := 240.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_SEP))
	box.position = Vector2((panel_size.x - content_width) * 0.5, _CONTENT_TOP)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SOUND"
	UiFont.title(title, 20)
	box.add_child(title)

	_volume = VolumePanel.new(content_width)
	box.add_child(_volume)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(content_width, _CLOSE_H)
	close.pressed.connect(func() -> void: _settings_overlay.visible = false)
	box.add_child(close)

	return layer


## PLAY is the campaign (12.3), which does not exist -- and the screen it opens says so
## in words and points at MULTIPLAYER for the game that does. A `NoticeToast` was the
## other option and is what SETTINGS and HOW TO get; a campaign is a list of missions and
## a screen is the frame that list goes in, so this one is worth having early and empty.
func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(_CAMPAIGN_SCENE)


## The SKIRMISH SETTINGS screen (1.6), which is also the lobby.
##
## That is one extra tap before playing, and it is the right one: the map, the colours,
## the opponent and the victory condition are all real choices now, and a button that
## silently picked for you would make the generator unreachable. The screen opens on
## defaults that are one press from a match, so the cost is a tap and not a form.
##
## `Game.tscn` still starts a debug skirmish if reached any other way -- a dev preview,
## or `run/main_scene` pointed at it -- because `Net.pending_match` is null then.
func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(_SKIRMISH_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(_CREDITS_SCENE)


func _on_how_to_pressed() -> void:
	get_tree().change_scene_to_file(_HELP_SCENE)
