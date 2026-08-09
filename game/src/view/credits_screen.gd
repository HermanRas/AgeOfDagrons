## Credits screen (PLAN.md 1.4). Surfacing this is a licence obligation, not a
## courtesy -- CREDITS.md §"Adding an entry" requires the 0 A.D./Wildfire
## Games and Kibyra lines to be reproduced, and `art/LICENSE.txt` requires the
## CC-BY-SA 3.0 link, "Wildfire Games", and wildfiregames.com verbatim, not
## abbreviated. That text lives as `%CreditsText`'s `text` property in
## Credits.tscn now, not hardcoded here -- CREDITS.md itself documents that
## whoever adds a new credited asset must update both in the same change.
##
## Layout is authored in Credits.tscn (editable in the Godot editor) rather
## than built in code -- this screen is the proof-of-concept for moving UI
## scenes off the `_init()`-built convention gameplay/HUD widgets still use.
## This script only wires the one thing the scene can't express: leaving the
## screen.
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

@onready var _back_button: TextureButton = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
