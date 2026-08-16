## Dev check for the age/colour skin work: run the REAL match scene, drive it the
## way a player would, and screenshot each step.
##
## The distinction preview_world.gd already draws applies double here -- it draws
## nothing of its own and checks the real render path rather than a copy. This
## goes one further and instantiates `Game.tscn` itself, so what it photographs
## is the actual game: the real `SimHost`, the real command path, the real HUD.
## A preview that rebuilt any of that could show a working age badge while the
## game's own was broken.
##
## Drives rather than merely launching: it selects a villager, opens the build
## menu, pages it, and advances the age -- because "it started" is not evidence
## that the build grid pages or that a town centre re-skins.
##
## Usage:
##   Godot --path game res://dev_preview/preview_match.tscn
##       -- writes user://match_age1.png ... user://match_age4.png and quits.
##   ... -- --interactive     -- leaves it running to play with instead.
extends Node

const SHOT_DIR := "user://"

## Ticks to let the match settle before touching anything. The first snapshot
## only arrives after SimHost has stepped, and a screenshot taken before that is
## a photograph of an empty map.
const SETTLE_FRAMES := 30
## Between steps -- long enough for a command to land, be applied, and come back
## in a snapshot the HUD has drawn from.
const STEP_FRAMES := 12

var _game: Node = null
var _frames := 0
var _step := 0
var _interactive := false


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance_script()


## One action per step, and the SHOT IS A STEP OF ITS OWN. Screenshotting in the
## same frame as the action photographs the state before it: an advance goes out
## as a command, and the HUD only moves when the next snapshot comes back. The
## first version of this shot immediately and produced an "age 4" image showing
## age 3 -- a lie about the thing it existed to check.
func _advance_script() -> void:
	match _step:
		0:
			_select_a_villager()
			_open_build_menu()
		1:
			_shoot("match_age1")
		2:
			_advance_age()
		3:
			_shoot("match_age2")
		4:
			_advance_age()
		5:
			_shoot("match_age3")
		6:
			_advance_age()
		7:
			_select_a_villager()
			_open_build_menu()
		8:
			_shoot("match_age4")
		9:
			_page_build_menu()
		10:
			_shoot("match_age4_page2")
		_:
			get_tree().quit()
			return
	_step += 1


func _select_a_villager() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if bool(f.get("is_unit", false)) and StringName(f.get("def_id", &"")) == &"unit.villager":
			view.select([int(id)] as Array[int])
			_game._refresh_panel()
			return
	push_warning("preview_match: no villager to select")


## Idempotent, because the panel's Build action is a TOGGLE. Calling this twice
## across a script that reselects the same villager closed the menu instead of
## reopening it, and the age-4 shot came out with no build grid at all -- an
## empty grid photographed as though it were the finished thing.
func _open_build_menu() -> void:
	var panel: SelectionPanel = _game._panel
	if panel._active_action == &"build":
		return
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"build":
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_match: no build action on the panel")


func _page_build_menu() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._detail_slots:
		if slot.visible and slot.action != null and slot.action.id == SelectionActions.PAGE_NEXT:
			panel._on_detail_pressed(slot.action)
			return
	push_warning("preview_match: build menu does not page at this age")


## Through the badge's own signal path, not by poking SimPlayer -- the point is
## to check the button works, and a preview that set the age directly would pass
## with the button unwired.
func _advance_age() -> void:
	_game._age_badge._on_pressed()


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
