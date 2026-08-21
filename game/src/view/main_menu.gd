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
## SETTINGS is still a placeholder (1.5, not `[MVP]`), and HOW TO a placeholder for an
## in-game walkthrough that does not exist. Both answer a tap with a `NoticeToast` rather
## than doing nothing, so the button does not read as broken.
extends Control

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _CREDITS_SCENE := "res://scenes/menu/Credits.tscn"
const _SKIRMISH_SCENE := "res://scenes/menu/Skirmish.tscn"
const _CAMPAIGN_SCENE := "res://scenes/menu/Campaign.tscn"

@onready var _play_button: TextureButton = %PlayButton
@onready var _multiplayer_button: TextureButton = %MultiplayerButton
@onready var _settings_button: TextureButton = %SettingsButton
@onready var _credits_button: TextureButton = %CreditsButton
@onready var _how_to_button: TextureButton = %HowToButton
@onready var _quit_button: TextureButton = %QuitButton
@onready var _toast: NoticeToast = %Toast


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	# THE SKIRMISH AND LOBBY SCREEN, which is one screen because a skirmish and a lobby
	# differ only in what fills a player slot (1.6): all-local slots plays at once, and
	# setting a slot to Open opens the socket. There is no separate host button to forget.
	#
	# It used to open the throwaway 12.1g entry point, which was deleted once this screen
	# had hosted a real two-device match (confirmed 2026-08-21: phone joined a PC host
	# over WiFi, reviewed the map, pressed READY and played).
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_settings_button.pressed.connect(
			func() -> void: _toast.show_message("Settings are not available in this build"))
	_credits_button.pressed.connect(_on_credits_pressed)
	# Placeholder for a future in-game HUD walkthrough (no such screen exists
	# yet) -- a toast rather than doing nothing, same convention as
	# Multiplayer/Settings above.
	_how_to_button.pressed.connect(
			func() -> void: _toast.show_message("How-to guide is not available yet"))
	_quit_button.pressed.connect(func() -> void: get_tree().quit())


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
