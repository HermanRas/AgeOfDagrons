## The CAMPAIGN screen (PLAN.md 12.3), which is a placeholder and says so.
##
## WHY THIS EXISTS AT ALL. PLAY and MULTIPLAYER both opened the skirmish screen,
## because 1.6's whole design is one screen where a lobby is that screen with a slot
## set to Open -- so the two buttons genuinely had nowhere different to go. That
## made PLAY the button with no meaning of its own: whichever one you pressed, you
## got the same page, and nothing on the front door led to the campaign the plan has
## always had a row for. PLAY is now the campaign and MULTIPLAYER is the
## skirmish/lobby screen, so each button leads somewhere only it leads.
##
## A REAL SCREEN RATHER THAN A TOAST, and that is the difference from SETTINGS and
## HOW TO, which answer a press with a `NoticeToast` line. Those are features with no
## shape yet. A campaign is a list of missions, and this screen is the frame that
## list will appear in -- so it takes a scene change, it has a way back, and when
## 12.3 lands it is a body replacing a placeholder rather than a new screen.
##
## Layout is authored in `Campaign.tscn`, the `.tscn`-first convention `Credits.tscn`
## moved to first: this script only wires the one thing a scene cannot express,
## which is leaving it.
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
