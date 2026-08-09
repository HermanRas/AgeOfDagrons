## The literal front door of the product (PLAN.md 1.1/1.2). Layout is
## authored in MainMenu.tscn (editable in the Godot editor), the same
## `.tscn`-first convention `Credits.tscn` moved to first -- this script only
## wires the buttons to what pressing them does.
##
## PLAY and CREDITS are the only buttons with real behaviour in MVP.
## MULTIPLAYER and SETTINGS are placeholders per 1.1's own wording (their
## screens are 1.5/1.6, explicitly not `[MVP]`); HOW TO is a placeholder for a
## future in-game HUD walkthrough that does not exist yet either. All three
## answer a tap with a `NoticeToast` rather than doing nothing, so the button
## does not read as broken.
extends Control

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _CREDITS_SCENE := "res://scenes/menu/Credits.tscn"

@onready var _play_button: TextureButton = %PlayButton
@onready var _multiplayer_button: TextureButton = %MultiplayerButton
@onready var _settings_button: TextureButton = %SettingsButton
@onready var _credits_button: TextureButton = %CreditsButton
@onready var _how_to_button: Button = %HowToButton
@onready var _quit_button: TextureButton = %QuitButton
@onready var _toast: NoticeToast = %Toast


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_multiplayer_button.pressed.connect(
			func() -> void: _toast.show_message("Multiplayer is not available in this build"))
	_settings_button.pressed.connect(
			func() -> void: _toast.show_message("Settings are not available in this build"))
	_credits_button.pressed.connect(_on_credits_pressed)
	# Placeholder for a future in-game HUD walkthrough (no such screen exists
	# yet) -- a toast rather than doing nothing, same convention as
	# Multiplayer/Settings above.
	_how_to_button.pressed.connect(
			func() -> void: _toast.show_message("How-to guide is not available yet"))
	_quit_button.pressed.connect(func() -> void: get_tree().quit())


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(_GAME_SCENE)


func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(_CREDITS_SCENE)
