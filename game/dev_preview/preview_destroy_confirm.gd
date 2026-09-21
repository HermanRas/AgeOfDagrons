extends Node

## Does Destroy ASK before it destroys, and does CANCEL actually save the thing?
## Board `8.x-destroy-confirm`. **THE EXIT CODE IS THE ANSWER**, and there is a
## screenshot of the dialog because whether it reads as a warning is a question for a
## person.
##
##     godot --path game res://dev_preview/preview_destroy_confirm.tscn
##
## ## ⛔ WHY THIS IS NOT A UNIT TEST
##
## The wiring is the whole feature and `GameScene` is not built in the suite -- every
## `tests/view/` file constructs one widget with `.new()`. `ConfirmOverlay` itself is
## already covered that way (`test_confirm_overlay`, eleven cases including the one that
## matters: CANCEL must never confirm). What nothing covers is the CHAIN -- an action tile
## press reaching `debug_destroy_requested`, that opening this dialog instead of a command,
## and the command going out on confirm and NOT on cancel.
##
## So this drives `Game.tscn` itself, the way `preview_match` does, and presses the real
## tiles and the real buttons.
##
## ## ⚠️ THE ASSERTION THAT MATTERS IS THE NEGATIVE ONE
##
## Anybody can check that DESTROY destroys. The regression worth guarding is **CANCEL
## leaving the unit alive** -- a wiring slip that connected both buttons to the same
## handler would look completely correct in a screenshot of the dialog, and would destroy
## the thing the player just declined to destroy. `test_confirm_overlay` makes that point
## about the widget; this makes it about the game.
##
## Step 2 therefore cancels and then waits several ticks before believing it: a unit that
## dies one tick later is a unit CANCEL did not save, and checking in the same frame as the
## press would report the sim's state from before the command would have applied anyway.

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 90
const STEP_FRAMES := 30
## Long enough that a destroy command submitted on the cancelled press would have
## round-tripped and applied several times over. See the header.
const PATIENCE_FRAMES := 120

var _game: Node
var _frames := 0
var _step := 0
var _target := 0
var _problems: Array[String] = []


func _ready() -> void:
	print("=== destroy confirmation ===\n")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance()


func _advance() -> void:
	match _step:
		0:
			_select_a_villager()
			_press_destroy()
		1:
			_check_it_asked()
			_shoot("destroy_confirm")
		2:
			_press_cancel()
		3:
			# Deliberately idle. The gap is the check -- see PATIENCE_FRAMES.
			_frames -= PATIENCE_FRAMES
		4:
			_check_cancel_saved_it()
			_press_destroy()
		5:
			_press_confirm()
		6:
			_frames -= PATIENCE_FRAMES
		7:
			_check_confirm_destroyed_it()
			_finish()
	_step += 1


func _select_a_villager() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if bool(f.get("is_unit", false)) \
				and StringName(f.get("def_id", &"")) == &"unit.villager":
			_target = int(id)
			view.select([_target] as Array[int])
			_game._refresh_panel()
			print("  target: villager #%d" % _target)
			return
	_fail("no villager to select -- the preview never got started")


## The REAL tile, not the handler. `GameScene.corner_buttons` records why: on these
## screens a control wired to nothing has looked exactly like a working one more than once.
func _press_destroy() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"destroy":
			panel._on_action_pressed(slot.action)
			return
	_fail("no Destroy tile on the panel")


func _check_it_asked() -> void:
	var overlay: ConfirmOverlay = _game._destroy_confirm
	if not overlay.is_open():
		_fail("Destroy did not ask -- the dialog never opened")
		return
	print("  asked: %s / %s / [%s] [%s]" % [overlay.title_text(), overlay.body_text(),
			overlay.cancel_button().text, overlay.confirm_button().text])
	# The dialog must name the thing, or it is a generic "are you sure" about nothing --
	# which is the kind people learn to tap through.
	if not overlay.title_text().to_lower().contains("villager"):
		_fail("the dialog does not name what is about to be destroyed: %s"
				% overlay.title_text())
	if _still_alive():
		print("  and the villager is still standing while the question is up")
	else:
		_fail("the villager died just from being ASKED about")


func _press_cancel() -> void:
	_game._destroy_confirm.cancel_button().pressed.emit()


func _check_cancel_saved_it() -> void:
	if _still_alive():
		print("  CANCEL: villager #%d is alive %d frames later" % [_target, PATIENCE_FRAMES])
	else:
		_fail("CANCEL DESTROYED IT -- the two buttons are wired to the same handler")
	if _game._destroy_confirm.is_open():
		_fail("the dialog is still up after CANCEL")
	# Re-select: cancelling does not change the selection, but the panel may have been
	# refreshed by a snapshot in between and the tile has to be there to press again.
	var view: GameView = _game._view
	view.select([_target] as Array[int])
	_game._refresh_panel()


func _press_confirm() -> void:
	var overlay: ConfirmOverlay = _game._destroy_confirm
	if not overlay.is_open():
		_fail("the dialog did not reopen for the second press")
		return
	overlay.confirm_button().pressed.emit()


func _check_confirm_destroyed_it() -> void:
	if _still_alive():
		_fail("DESTROY did not destroy -- the confirm button sends nothing")
	else:
		print("  DESTROY: villager #%d is gone" % _target)


## Whether the target is still in the world the CLIENT can see.
##
## Read off `GameView`, not the sim, because that is what the player is looking at and
## what the panel is drawn from -- and because a preview reaching into `SimHost` would be
## checking a different question from the one the dialog is about.
func _still_alive() -> bool:
	var view: GameView = _game._view
	var f: Dictionary = view.facts_for(_target)
	return not f.is_empty() and bool(f.get("alive", false))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("  wrote ", ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_problems.append(message)


func _finish() -> void:
	print("")
	if _problems.is_empty():
		print("OK -- Destroy asks, CANCEL saves it, DESTROY destroys it.")
		get_tree().quit(0)
		return
	print("%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)
