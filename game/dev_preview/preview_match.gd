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
## Set by _wait_for_progress(); the script stalls until the advance ring reaches
## it. -1.0 means "not waiting on anything".
var _await_progress := -1.0
var _interactive := false


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1

	# A progress wait outranks the frame gate: it is waiting on sim time, which
	# the frame counter knows nothing about.
	if _await_progress >= 0.0:
		var view: GameView = _game._view
		if view.age_progress_of(Net.local_player_id()) < _await_progress:
			return
		_await_progress = -1.0
		# Re-base the frame gate, or every step after a wait fires immediately
		# because the counter has run far past its threshold.
		_frames = SETTLE_FRAMES + _step * STEP_FRAMES

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
			# The real button: a timed research, so the ring starts filling. Held
			# for half of `advance_time_ticks` before the shot, or the photograph
			# is of a ring 2% round and says nothing.
			_press_advance()
			_wait_for_progress(0.5)
		3:
			_shoot("match_advancing")
		4:
			# The rest of the ladder uses the INSTANT debug jump. Sitting through
			# three more real researches would add 30 s to every preview run for
			# nothing -- the ring is already photographed, and what these shots
			# are for is the building skins.
			_jump_age(2)
		5:
			_shoot("match_age2")
		6:
			_jump_age(3)
		7:
			_shoot("match_age3")
		8:
			_jump_age(4)
			_select_a_villager()
			_open_build_menu()
		9:
			_shoot("match_age4")
		10:
			_page_build_menu()
		11:
			_shoot("match_age4_page2")
		12:
			# The town centre's own panel: its train row, and its queue once
			# something is in it. The queue slots crop the unit's portrait, which
			# needs the def ids to have survived the snapshot.
			_select_a_town_centre()
		13:
			_train_from_selection()
		14:
			_train_from_selection()
		15:
			_shoot("match_queue")
		_:
			get_tree().quit()
			return
	_step += 1


## Hold the script until the local player's advance ring is at least this far
## round, then carry on.
##
## Waits on the SIM's own reported progress rather than on a frame count. The
## first version of this converted seconds to frames via
## `Engine.get_frames_per_second()` and hung the preview -- frames and sim ticks
## are different clocks (SimClock runs at a fixed 10 Hz whatever the frame rate
## does), so any frame count is a guess about a quantity the sim will happily
## tell you. This asks it.
func _wait_for_progress(fraction: float) -> void:
	_await_progress = fraction


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


func _select_a_town_centre() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		if StringName(view.facts_for(int(id)).get("def_id", &"")) == &"building.town_center":
			view.select([int(id)] as Array[int])
			_game._refresh_panel()
			return
	push_warning("preview_match: no town centre to select")


## Presses the first train button on the panel, the way a player would, rather
## than submitting a TrainCommand directly -- the queue slots are what is being
## checked and they only fill if the whole round trip works.
func _train_from_selection() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and String(slot.action.id).begins_with("train:"):
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_match: nothing to train on the selected building")


## Through the badge's own signal path, not by poking SimPlayer -- the point is
## to check the BUTTON works, and a preview that set the age directly would pass
## with it unwired. Starts a timed research; the age lands seconds later.
func _press_advance() -> void:
	_game._age_badge._on_pressed()


## The instant debug jump, for getting to an age quickly. Deliberately NOT the
## button: it skips the research entirely, so a preview that used it everywhere
## would never exercise the thing the button does.
func _jump_age(to_age: int) -> void:
	Net.submit_command(DebugSetAgeCommand.new(Net.local_player_id(), to_age))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
