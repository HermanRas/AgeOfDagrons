## Dev check for PLAN.md 11.1: run the REAL match scene, fight the match to its end,
## and photograph what the player is left looking at.
##
## Same principle as `preview_match.gd` -- it instantiates `Game.tscn` itself, so
## what it shoots is the actual game: the real `SimHost`, the real snapshot channel,
## the real `WinConditionSystem`, and the real `ResultScreen` wired into the real
## `GameScene`. A preview that built its own overlay could show a beautiful victory
## screen while the game's own never appeared.
##
## VICTORY IS WON BY FIGHTING, through `AttackCommand`, not by setting `alive` in the
## host's world. The whole thing being checked is the round trip -- a kill lands in
## the sim, `WinConditionSystem` decides the match, the outcome rides a snapshot, and
## `GameScene._refresh_result()` puts a screen up -- and reaching into the world would
## skip the half of that which can actually break.
##
## Usage:
##   Godot --path game res://dev_preview/preview_victory.tscn
##       -- villagers hunt down the enemy squad; writes user://victory_screen.png.
##   ... -- --defeat
##       -- the local player razes their OWN settlement instead (DebugDestroyCommand,
##          which is own-entities-only), for the other branch of the same screen.
##          Writes user://defeat_screen.png.
extends Node

const SHOT_DIR := "user://"

## Long enough for the first snapshot to land and the HUD to have drawn from it.
const SETTLE_FRAMES := 30
## After the last enemy falls: the kill, the tick that decides the match, the
## snapshot back, and a frame drawn from it.
const RESULT_FRAMES := 20
## Villagers do 3 damage every 20 ticks apiece, so a 100 hp knight is ~13 s of
## whittling. A generous ceiling on that, after which it gives up loudly rather than
## hanging -- a preview that never returns reports nothing at all.
const TIMEOUT_FRAMES := 5400

enum Phase { SETTLE, FIGHTING, DECIDED, DONE }

var _game: Node = null
var _frames := 0
var _phase: Phase = Phase.SETTLE
var _decided_at := 0
var _target := 0
var _defeat := false


func _ready() -> void:
	_defeat = OS.get_cmdline_user_args().has("--defeat")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	_frames += 1

	match _phase:
		Phase.SETTLE:
			if _frames < SETTLE_FRAMES:
				return
			_report("before")
			if _defeat:
				# Straight to the wait: a razed player has nothing left to fight WITH,
				# so the fighting phase would sit ordering an empty selection onto the
				# enemy squad until it timed out.
				_raze_our_own()
				_decided_at = _frames
				_phase = Phase.DECIDED
				return
			_phase = Phase.FIGHTING

		Phase.FIGHTING:
			if _frames > TIMEOUT_FRAMES:
				push_warning("preview_victory: gave up waiting for the match to end")
				_finish()
				return
			# Re-ordered whenever the current quarry dies: CombatSystem retires an
			# attack order on the killing blow and does NOT pick a new target
			# (auto-acquire is 4.12), so somebody has to say "now that one".
			var enemy := _first_live_enemy()
			if enemy != 0:
				if enemy != _target:
					_target = enemy
					_attack(enemy)
				return
			_decided_at = _frames
			_phase = Phase.DECIDED

		Phase.DECIDED:
			if _frames - _decided_at < RESULT_FRAMES:
				return
			_finish()


func _finish() -> void:
	_report("after")
	_shoot("defeat_screen" if _defeat else "victory_screen")
	_phase = Phase.DONE
	get_tree().quit()


## Every villager onto one target, through the tap path's own command.
func _attack(target_id: int) -> void:
	var view: GameView = _game._view
	var mine: Array[int] = []
	for id in view.all_facts().keys():
		var f: Dictionary = view.facts_for(int(id))
		if int(f.get("owner_id", 0)) == Net.local_player_id() \
				and bool(f.get("is_unit", false)) and bool(f.get("alive", true)):
			mine.append(int(id))
	view.select(mine)
	Net.submit_command(AttackCommand.new(Net.local_player_id(),
			view.movable_selection(), target_id))
	print("%d unit(s) ordered onto entity %d" % [mine.size(), target_id])


## The lowest-id living entity belonging to somebody who is neither us nor gaia, or
## 0 when there are none left. Sorted, so the squad is worked through in a stable
## order rather than whatever the fact dictionary happens to iterate in.
func _first_live_enemy() -> int:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		var owner := int(f.get("owner_id", 0))
		if owner != 0 and owner != Net.local_player_id() and bool(f.get("alive", true)):
			return int(id)
	return 0


## The `--defeat` path: destroy everything WE own. `DebugDestroyCommand` is
## own-entities-only by design, which makes it exactly the wrong tool for winning and
## exactly the right one for losing -- and losing is otherwise unreachable, since
## nothing on the debug map can attack the local player back until there is an AI
## (12.2a).
func _raze_our_own() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	var razed := 0
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if int(f.get("owner_id", 0)) != Net.local_player_id() or not bool(f.get("alive", true)):
			continue
		Net.submit_command(DebugDestroyCommand.new(Net.local_player_id(), int(id)))
		razed += 1
	print("ordered %d of our own entities destroyed" % razed)


## What the sim thinks and what the screen says. Printed as well as photographed,
## because the picture cannot tell "the match is not over" from "it is over and the
## overlay never appeared".
func _report(when: String) -> void:
	var world: SimWorld = Net.host().world
	var result: ResultScreen = _game._result
	print("%s: match_over %s  winner %d  p1 defeated %s  p2 defeated %s"
			% [when, world.match_over, world.winner_id,
			world.player_for(1).defeated, world.player_for(2).defeated])
	print("    screen shown %s  title '%s'  subtitle '%s'"
			% [result.is_shown(), result.title_text(), result.subtitle_text()])
	# GEOMETRY, because a picture cannot tell a control that is missing from one drawn
	# at zero size -- both look like nothing at all. The overlay must cover the
	# viewport (it is the dim, and the thing that swallows presses) and the panel must
	# be exactly ResultScreen.PANEL_SIZE rather than however wide its text made it.
	print("    overlay %s  panel %s (want %s)" % [result.get_global_rect().size,
			result.panel_rect().size, ResultScreen.PANEL_SIZE])


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
