## The literal front door of the product (PLAN.md 1.1/1.2). Layout is
## authored in MainMenu.tscn (editable in the Godot editor), the same
## `.tscn`-first convention `Credits.tscn` moved to first -- this script only
## wires the buttons to what pressing them does.
##
## PLAY, MULTIPLAYER and CREDITS have real behaviour. PLAY and MULTIPLAYER both open the
## skirmish screen, which is 11.1's whole design: one screen, and a lobby is that screen
## with a slot set to Open.
##
## SETTINGS is still a placeholder (1.5, not `[MVP]`), and HOW TO a placeholder for an
## in-game walkthrough that does not exist. Both answer a tap with a `NoticeToast` rather
## than doing nothing, so the button does not read as broken.
extends Control

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _CREDITS_SCENE := "res://scenes/menu/Credits.tscn"
const _SKIRMISH_SCENE := "res://scenes/menu/Skirmish.tscn"

@onready var _play_button: TextureButton = %PlayButton
@onready var _multiplayer_button: TextureButton = %MultiplayerButton
@onready var _settings_button: TextureButton = %SettingsButton
@onready var _credits_button: TextureButton = %CreditsButton
@onready var _how_to_button: TextureButton = %HowToButton
@onready var _quit_button: TextureButton = %QuitButton
@onready var _toast: NoticeToast = %Toast


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	# MULTIPLAYER AND PLAY GO TO THE SAME PLACE, and that is the point of 11.1's one
	# screen: a skirmish and a lobby differ only in what fills a player slot, so there is
	# nowhere else for this button to go. Kept rather than removed because it is what
	# somebody looking for multiplayer will press, and it now lands on the screen where
	# setting a slot to Open opens the socket.
	#
	# It used to open the throwaway 12.1g entry point, which was deleted once this screen
	# had hosted a real two-device match (confirmed 2026-08-21: phone joined a PC host
	# over WiFi, reviewed the map, pressed READY and played).
	_multiplayer_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(
			func() -> void: _toast.show_message("Settings are not available in this build"))
	_credits_button.pressed.connect(_on_credits_pressed)
	# Placeholder for a future in-game HUD walkthrough (no such screen exists
	# yet) -- a toast rather than doing nothing, same convention as
	# Multiplayer/Settings above.
	_how_to_button.pressed.connect(
			func() -> void: _toast.show_message("How-to guide is not available yet"))
	_quit_button.pressed.connect(func() -> void: get_tree().quit())


## PLAY now goes through the SKIRMISH SETTINGS screen (1.6) rather than straight into
## a match on the fixed debug map.
##
## That is one extra tap before playing, and it is the right one: the map, the colours,
## the opponent and the victory condition are all real choices now, and a PLAY button
## that silently picked for you would make the generator unreachable. The screen opens
## on defaults that are one press from a match, so the cost is a tap and not a form.
##
## `Game.tscn` still starts a debug skirmish if reached any other way -- a dev preview,
## or `run/main_scene` pointed at it -- because `Net.pending_match` is null then.
func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(_SKIRMISH_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(_CREDITS_SCENE)
