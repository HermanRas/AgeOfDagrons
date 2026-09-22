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

## Roughly what the short banner holds -- `GameScene._SHORT_ALERT_CHARS`, restated here
## rather than reached for across scenes, because it is a measurement of the same widget.
const _SHORT_NOTE_CHARS := 44

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
##
## ⚠️ **IT IS `SoundOverlay` SINCE 2026-09-22, AND IT USED TO BE 100 LINES OF THIS FILE.**
## `PauseMenu` needed the same page when 2.4c's sixth button pushed the sliders out of it, so
## the builder moved to its own class rather than being copied -- with every comment in it,
## each of which records a layout mistake somebody already paid for. Both SETTINGS buttons in
## the game now open the same page, which is what `VolumePanel`'s header always said was the
## intent.
var _settings_overlay: SoundOverlay = null


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

	# WHY YOU ARE BACK HERE, when something sent you (12.4). A saved match ends for every
	# player and drops all of them on this screen, and without a word that is indistinguishable
	# from the game having thrown them out -- especially on the devices that did not press
	# anything. `Net.take_parting_note()` clears as it reads, so it says its piece once and a
	# later visit to the front door is silent.
	#
	# THIS IS THE TOAST THE COMMENT ABOVE KEPT A NODE FOR. It had no caller from the day HOW
	# TO became a real screen, and the reason given for keeping it was that the front door
	# would want to say something in passing again.
	#
	# THE LONG BANNER FOR A SENTENCE, THE SHORT ONE FOR A LABEL, on `GameScene`'s measurement:
	# the 320 px banner's dark field holds about 44 characters. "Saved: Skirmish, 20 Sep 14:32
	# (tick 4120)" is a label and fits; what a JOINED player is told is prose and does not.
	var note := Net.take_parting_note()
	if not note.is_empty():
		if note.length() > _SHORT_NOTE_CHARS:
			_toast.show_long_message(note)
		else:
			_toast.show_message(note)


## SETTINGS: the volume panel, in a dim-backed overlay built on first use.
##
## Built lazily and kept, rather than authored into MainMenu.tscn, for the reason
## §6 of AGENT_GAME_CODER.md gives: Godot rewrites `.tscn` layout properties when
## the project is open, and MainMenu.tscn is one of the authored mockups that
## should not drift. A panel made in code cannot be silently reformatted.
func _on_settings_pressed() -> void:
	if _settings_overlay == null:
		_settings_overlay = SoundOverlay.new()
		add_child(_settings_overlay)
	_settings_overlay.open()


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
