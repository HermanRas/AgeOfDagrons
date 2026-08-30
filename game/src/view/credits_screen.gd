## Credits screen (PLAN.md 1.4). Surfacing this is a licence obligation, not a
## courtesy -- `art/LICENSE.txt` requires the CC-BY-SA 3.0 link, "Wildfire
## Games", and wildfiregames.com verbatim, not abbreviated, and the two OFL
## faces require their licence texts to ship. That text lives as
## `%CreditsText`'s `text` property in Credits.tscn now, not hardcoded here --
## CREDITS.md itself documents that whoever adds a new credited asset must
## update both in the same change.
##
## THE REVERSE ALSO APPLIES, and it happened on 2026-08-30: the Kibyra UI packs
## were credited here from 2026-08-08, were replaced by project-owned art, and
## the entry was struck once nothing from them remained in the repository --
## no file, no load path, no tracked directory. Their terms asked for no
## attribution in the first place. **Do not strike an entry because the art was
## replaced; strike it when the art is GONE**, which is a question for
## `game/assets/LICENCES.md` and `tools/licence_audit.py`, not for memory.
##
## Layout is authored in Credits.tscn (editable in the Godot editor) rather
## than built in code -- this screen is the proof-of-concept for moving UI
## scenes off the `_init()`-built convention gameplay/HUD widgets still use.
## This script only wires the one thing the scene can't express: leaving the
## screen.
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
