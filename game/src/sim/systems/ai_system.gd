## Drives every `SimPlayer.is_ai` player through `AIPlaytest.SCRIPT` (PLAN.md 12.2a).
##
## **This is the PlayTest AI, and it is deliberately not the AI that was parked.**
## Difficulty levels and real decision flow are 12.2b, and they want a game whose
## balance has been played first. What this is for is threefold: an opponent for solo
## play, something for the win condition to be won against, and -- the reason it comes
## before multiplayer -- **an automated full-match regression test**, since a match that
## ends exercises 11.1 and the result screen without anybody holding two phones.
##
## ## The four rules it is built on
##
## **It emits ordinary `Command`s and nothing else.** No privileged access, no reaching
## into `SimWorld` to make something happen. That is what makes it a real test of the
## command path rather than a puppet: every order it gives is validated exactly as a
## player's would be, and anything it cannot legally do, it cannot do.
##
## **It is deterministic.** No `randi()`, no iteration over an unordered dictionary
## without sorting. Two hosts running the same world produce the same AI, which is what
## lets a replay reproduce an AI match from the human's commands alone (7.7).
##
## **Every step has a timeout and may be skipped.** On a generated map there may be no
## berry bush within reach, or nowhere flat to put a barracks. A step that waited
## forever would take the whole match with it, so a step that cannot finish is
## abandoned and the next one starts.
##
## **It says what it is doing.** `log_line()` reports the step and why it advanced,
## which is the difference between a debuggable failed match and a mystery.
##
## Runs LAST in the tick order, after the world has settled: it looks at the finished
## tick and acts on the next one, which is what a player does. Its commands are queued
## for `tick + 1` like anybody's.
##
## Per-player progress lives on this instance rather than on `SimPlayer`, and so is NOT
## in `state_hash()`. That is deliberate: it is derived state -- two hosts stepping the
## same world compute the same progress -- and hashing it would only report a
## divergence that the resulting commands would report a tick later anyway.
class_name AISystem
extends SimSystem

## Ticks between standing orders. **They do not need 10 Hz** -- re-checking who is idle
## twice a second is already faster than a person, and each pass walks the entity list
## several times. Same reasoning as `VisionSystem.VISION_INTERVAL`, and keyed off
## `w.tick` for the same reason: it stays deterministic.
##
## Measured: two AIs on a 96x96 map cost ~30 ms a tick before this and the id cache
## below, against PLAN.md 3.1's 5 ms budget. The AI runs INSIDE the tick, so an
## expensive AI is an expensive simulation.
const STANDING_ORDER_INTERVAL := 5

## Ticks between attempts to issue the current script step.
##
## **A step that cannot be issued yet is retried, and retrying it every tick was
## pathological.** Placing a building searches a widening ring of candidate tiles, and a
## step blocked on cost or labour re-ran that whole search ten times a second for its
## entire 900-tick timeout. Two AIs doing it took the tick to **seconds** -- 300 ticks
## did not finish in ten minutes. Twice a second is far faster than a person and turns
## the cost into a rounding error.
const THINK_INTERVAL := 5

## How far from its anchor a building may be placed. A base is ~22 tiles across, so 14
## rings reaches comfortably past it; the ring scan is quadratic in this number, and it
## was 26 for no reason anybody could have named.
const MAX_PLACEMENT_RADIUS := 14

## How many candidate targets `_nearest_enemy` will path-test before settling for the
## nearest. Each probe is a full path solve, so this is a budget, not a search: the
## first candidate is reachable in almost every real case.
const REACH_PROBES := 6

## The same budget for placement, and smaller because it is spent on every think tick
## while a build step is still pending, where the targeting one is spent only when an
## army has gone idle.
## PLACEMENT IS NOT REACHABILITY-TESTED, and it was tried. A build site can be legal,
## reachable when chosen, and sealed off by the very footprint that goes on it: seed 6
## put p2's mining camp in a pocket whose neck the camp then filled, leaving thirteen
## free tiles beside it that nothing could get to. Testing the tile, and then testing
## for a route to its surroundings that avoided the footprint, each failed to prevent
## it while costing a path solve per candidate on every think tick. Parked deliberately
## on 2026-08-20 rather than carrying unproven cost in the hot path -- the remaining
## symptom is a 0% foundation that keeps its owner formally alive, and ranged units
## will change the geometry of it anyway.

## player id -> {step: int, since: int, issued: bool, assigned: Array[int]}
var _progress: Dictionary = {}

## What each player last did, for the log.
var _log: Array[String] = []

## Why the last `_issue` attempt returned false, for the log.
##
## `_issue` answers a bare yes/no, and "could not be issued" was the same word for six
## different things: no villager free, nowhere to put it, cannot afford it, the age gate,
## the population cap, or a trainer that is still a hole in the ground. A full match then
## ends with a line that says a step failed and nothing about which of those to go and
## fix. Set on every false return; read once when the step finally gives up.
var _why: String = ""

## `entities.keys()` sorted, rebuilt once a tick.
##
## Every lookup here walks entity ids in sorted order -- `entities` is keyed in insertion
## order, so anything picking "the first one found" would depend on spawn order and two
## hosts could disagree, which for an AI means diverging matches. Sorting is therefore
## not optional; sorting it eight times per player per tick was.
var _ids_cache: Array = []
var _ids_tick: int = -1


func process_tick(w: SimWorld) -> void:
	for p in w.players:
		if p.is_ai and not p.defeated:
			_advance(w, p)


## The last few things the AI decided, newest last. For `dev_preview` and for a failing
## test to print -- a headless match that ends in the wrong place is otherwise silent.
func log_lines() -> Array[String]:
	return _log


func step_of(player_id: int) -> int:
	return int((_progress.get(player_id, {}) as Dictionary).get("step", 0))


func _advance(w: SimWorld, p: SimPlayer) -> void:
	var state: Dictionary = _progress.get(p.id,
			{"step": 0, "since": w.tick, "issued": false, "assigned": [] as Array[int]})
	_progress[p.id] = state

	var index: int = state["step"]
	var script_done := index >= AIPlaytest.SCRIPT.size()

	# STANDING ORDERS RUN FIRST AND ALWAYS, and getting that wrong deadlocked the AI in
	# a way only a full run showed. They used to be skipped while the current step was
	# waiting to be issued, on the reasoning that the step needed the idle villagers --
	# so an AI at "build a mill" with 10 wood left waited for wood it could no longer
	# gather, because the villagers who would have gathered it were the ones being held
	# in reserve. Five idle villagers, forever.
	#
	# It is safe now for the same reason it was needed: `_pick_units` can pull a villager
	# off gathering, so a step does not depend on anybody being idle.
	if w.tick % STANDING_ORDER_INTERVAL == 0:
		_keep_busy(w, p, script_done)
	if script_done:
		return
	var step: Dictionary = AIPlaytest.SCRIPT[index]

	# Issue once, then watch. Re-issuing every tick would spam the command queue with
	# orders for units already carrying them out, and for `train` it would empty the
	# treasury into a queue nobody asked for.
	if not state["issued"]:
		if w.tick % THINK_INTERVAL != 0:
			return          # see THINK_INTERVAL: retrying this every tick was the hang
		_why = ""
		state["issued"] = _issue(w, p, step, state)
		if state["issued"]:
			state["since"] = w.tick
			_note(w, "p%d step %d: %s" % [p.id, index, _describe(step)])
		elif w.tick - int(state["since"]) > int(step.get("timeout", 300)):
			_skip(w, p, state, index, "could not be issued -- %s"
					% (_why if _why != "" else "no reason given"))
		return

	if _is_done(w, p, step, state):
		_next(w, p, state, index, "done")
	elif w.tick - int(state["since"]) > int(step.get("timeout", 300)):
		_skip(w, p, state, index, "timed out")


## THE STANDING ORDERS: what the AI does continuously, underneath the script.
##
## The script is an OPENING -- a sequence of one-off decisions. These three are the
## things a player does without thinking about them, and each one was added because a
## full AI-vs-AI run showed what its absence costs:
##
## **1. Nobody stands around.** A berry bush holds 80 food and takes two gatherers, so a
## pair strips one in ~16 s and then RETIRES to idle. By tick 600, all six villagers
## were idle and the AI had banked 80 food in a minute.
##
## **2. Unfinished buildings get finished.** A builder that dies, or is pulled onto
## another job, leaves a foundation nobody ever returns to -- and a build step reports
## "done" as soon as the foundation EXISTS, so the script has already moved on. One run
## ended with an AI owning a foundation house and a foundation watch tower, and no
## barracks, because the labour had drifted off. `TrainCommand` rightly refuses a
## building that is a hole in the ground.
##
## **3. Soldiers keep attacking.** The script's attack step fires ONCE, with whatever
## army exists at that moment -- which was the scout, because the train step completes
## when the queue fills and the five swordsmen were still in it. They then stood in the
## barracks for 5,000 ticks while the match went nowhere. Any idle soldier now goes at
## the nearest enemy, which also gives the AI the retargeting `CombatSystem`
## deliberately does not do (4.12): a unit whose target dies goes idle, and is sent on.
func _keep_busy(w: SimWorld, p: SimPlayer, attack: bool) -> void:
	var site := _unfinished_building(w, p)
	for id in _idle_villagers(w, p):
		if site != 0:
			w.queue_command(BuildCommand.new(p.id, [id] as Array[int], site))
			continue
		# Poorest kind first, ties broken by a fixed order, so it is deterministic and
		# self-balancing: whatever ran out is what gets worked next.
		var node := _nearest_node(w, _poorest_kind(p), id)
		if node != 0:
			w.queue_command(GatherCommand.new(p.id, [id] as Array[int], node))

	# ONLY ONCE THE SCRIPT HAS REACHED ITS END. The script decides WHEN to attack; this
	# only keeps it going afterwards. Without the gate the standing order threw the
	# starting scout at the enemy base on tick 600, which is not an opening -- it is
	# giving away a unit before the first house is up.
	if not attack:
		return
	var loiterers := _idle_military(w, p)
	if not loiterers.is_empty():
		var target := _nearest_enemy(w, p, loiterers[0])
		if target != 0:
			w.queue_command(AttackCommand.new(p.id, loiterers, target))


## The player's own building that still needs work, lowest id first, or 0.
func _unfinished_building(w: SimWorld, p: SimPlayer) -> int:
	for id in _sorted_ids(w):
		var b = w.entities[id]
		if b is SimBuilding and b.alive and b.owner_id == p.id and not b.is_complete():
			return int(id)
	return 0


func _idle_military(w: SimWorld, p: SimPlayer) -> Array[int]:
	var out: Array[int] = []
	for id in _military(w, p):
		var u: SimUnit = w.entities[id]
		if _is_free(u):
			out.append(int(id))
	return out


## Which resource the player has least of. Walked in a FIXED order so an exact tie
## resolves the same way on every machine.
static func _poorest_kind(p: SimPlayer) -> StringName:
	var kinds: Array[StringName] = [&"food", &"wood", &"gold", &"stone"]
	var poorest := kinds[0]
	var least := 1 << 40
	for kind in kinds:
		var amount := int(p.stock.get(kind, 0))
		if amount < least:
			least = amount
			poorest = kind
	return poorest


func _next(w: SimWorld, p: SimPlayer, state: Dictionary, index: int, why: String) -> void:
	state["step"] = index + 1
	state["since"] = w.tick
	state["issued"] = false
	_note(w, "p%d step %d %s" % [p.id, index, why])


func _skip(w: SimWorld, p: SimPlayer, state: Dictionary, index: int, why: String) -> void:
	# A skip is a real outcome, not a failure: the map may simply not have what the step
	# wanted. Logged distinctly from "done" so a run that skipped half its script is
	# visible rather than merely slow.
	_next(w, p, state, index, why)


func _note(w: SimWorld, line: String) -> void:
	_log.append("t%-6d %s" % [w.tick, line])
	if _log.size() > 200:
		_log.remove_at(0)


static func _describe(step: Dictionary) -> String:
	match String(step.get("do", "")):
		"gather": return "gather %s x%s" % [step.get("kind", "?"), step.get("units", 1)]
		"build": return "build %s near %s" % [step.get("def", "?"), step.get("near", "?")]
		"train": return "train %s x%d at %s" % [step.get("unit", "?"),
				int(step.get("count", 1)), step.get("at", "?")]
		"advance_age": return "advance age"
		"attack": return "attack"
		_: return String(step.get("do", "?"))


# ── issuing ─────────────────────────────────────────────────────────────────

## True once the step's orders are away. False means "not yet" -- no units free, no
## target in sight -- and the step is retried next tick until its timeout.
func _issue(w: SimWorld, p: SimPlayer, step: Dictionary, state: Dictionary) -> bool:
	state["assigned"] = [] as Array[int]
	match String(step.get("do", "")):
		"gather":
			return _issue_gather(w, p, step, state)
		"build":
			return _issue_build(w, p, step, state)
		"train":
			return _issue_train(w, p, step)
		"advance_age":
			var cmd := AdvanceAgeCommand.new(p.id)
			if not cmd.validate(w):
				_why = "cannot advance from age %d yet (stock %s)" % [p.age, p.stock]
				return false
			w.queue_command(cmd)
			return true
		"attack":
			return _issue_attack(w, p)
		_:
			return true          # an unknown verb is skipped rather than fatal


func _issue_gather(w: SimWorld, p: SimPlayer, step: Dictionary, state: Dictionary) -> bool:
	var units := _pick_units(w, p, step.get("units", 1))
	if units.is_empty():
		_why = "no villager could be freed for it"
		return false
	var node := _nearest_node(w, StringName(step.get("kind", &"food")), units[0])
	if node == 0:
		_why = "no %s node left on the map" % step.get("kind", &"food")
		return false
	w.queue_command(GatherCommand.new(p.id, units, node))
	state["assigned"] = units
	return true


func _issue_build(w: SimWorld, p: SimPlayer, step: Dictionary, state: Dictionary) -> bool:
	var units := _pick_units(w, p, step.get("units", 1))
	if units.is_empty():
		_why = "no villager could be freed for it"
		return false
	state["assigned"] = units
	var def_id := StringName(step.get("def", &""))
	var anchor := _anchor_tile(w, p, StringName(step.get("near", &"self")), units[0])
	if anchor.x < 0:
		_why = "nothing to anchor near=%s to" % step.get("near", &"self")
		return false
	var origin := _find_spot(w, p, def_id, anchor)
	if origin.x < 0:
		var bd: BuildingDef = GameDataRegistry.building(def_id)
		_why = "no legal %s spot within %d tiles of %s" % [
				"%dx%d" % [bd.footprint.x, bd.footprint.y] if bd != null else "?",
				MAX_PLACEMENT_RADIUS, anchor]
		return false
	var cmd := PlaceBuildingCommand.new(p.id, def_id, origin, units)
	if not cmd.validate(w):
		# cannot afford it yet, or the age gate; retry until timeout
		var bd2: BuildingDef = GameDataRegistry.building(def_id)
		_why = "cannot place %s: %s" % [def_id,
				"cost %s vs stock %s" % [bd2.cost, p.stock] if bd2 != null \
				and not p.can_afford(bd2.cost) else "age gate or footprint"]
		return false
	w.queue_command(cmd)
	return true


func _issue_train(w: SimWorld, p: SimPlayer, step: Dictionary) -> bool:
	var at := StringName(step.get("at", &""))
	var trainer := _own_building(w, p, at)
	if trainer == 0:
		_why = "no %s standing" % at
		return false
	# A FOUNDATION IS NOT A TRAINER. `_own_building` returns one in any phase, which is
	# right for "did the build step work" and wrong here; `TrainCommand` refuses it
	# either way, so this changes no behaviour. It is the difference between a step that
	# failed and a step that failed BECAUSE NOBODY EVER FINISHED THE BUILDING.
	var b := w.entities[trainer] as SimBuilding
	if not b.is_complete():
		_why = "%s is still a foundation (%d%% built)" % [at, int(b.build_fraction() * 100.0)]
		return false
	var unit_def := StringName(step.get("unit", &""))
	var count := int(step.get("count", 1))
	var queued := 0
	for i in range(count):
		var cmd := TrainCommand.new(p.id, trainer, unit_def)
		if not cmd.validate(w):
			break          # out of resources or out of population; take what we got
		w.queue_command(cmd)
		queued += 1
	if queued == 0:
		var ud: UnitDef = w.unit_def(unit_def)
		if ud == null:
			_why = "no such unit %s" % unit_def
		elif not p.can_afford(ud.cost):
			_why = "cannot afford %s: cost %s vs stock %s" % [unit_def, ud.cost, p.stock]
		elif not PopulationSystem.has_room_for(w, p.id, ud.pop_cost):
			_why = "population capped at %d/%d" % [p.pop_used, p.pop_cap]
		else:
			_why = "%s refused %s (own age %d, unit needs %d)" % [at, unit_def, p.age,
					ud.age_required]
	return queued > 0


## Every military unit at the nearest enemy town centre, else any enemy building, else
## any enemy unit. Buildings first on purpose: it is the win condition that matters
## here (11.1's last-man-standing), and a town centre does not run away.
func _issue_attack(w: SimWorld, p: SimPlayer) -> bool:
	var army := _military(w, p)
	if army.is_empty():
		_why = "no military unit to attack with"
		return false
	var target := _nearest_enemy(w, p, army[0])
	if target == 0:
		_why = "no enemy entity found"
		return false
	w.queue_command(AttackCommand.new(p.id, army, target))
	return true


# ── completion ──────────────────────────────────────────────────────────────

func _is_done(w: SimWorld, p: SimPlayer, step: Dictionary, state: Dictionary) -> bool:
	match String(step.get("do", "")):
		"gather":
			# THE UNITS THIS STEP ORDERED are working -- not "anybody is working", which
			# is what this asked first and it made the whole script race: once one
			# villager gathered, every later gather step reported done on the same tick
			# and the AI was nine steps in by tick 600 with nothing built.
			#
			# The order being ACCEPTED is the completion, not the resource being banked;
			# gathering never ends on its own.
			return _all_working(w, state.get("assigned", []) as Array)
		"build":
			return _own_building(w, p, StringName(step.get("def", &""))) != 0
		"train":
			return _has_queue(w, p, StringName(step.get("at", &""))) \
					or _count_of(w, p, StringName(step.get("unit", &""))) > 0
		"advance_age":
			return p.is_advancing() or p.age > 1
		"attack":
			return true          # the last step; issuing it is finishing it
		_:
			return true


# ── reading the world ───────────────────────────────────────────────────────
#
# Everything here walks entity ids in SORTED order. `entities` is keyed in insertion
# order, so anything that picked "the first one found" would depend on spawn order and
# two hosts could disagree -- which for an AI means diverging matches.

func _sorted_ids(w: SimWorld) -> Array:
	if _ids_tick != w.tick:
		_ids_cache = w.entities.keys()
		_ids_cache.sort()
		_ids_tick = w.tick
	return _ids_cache


## `count` idle villagers, lowest id first; "newest" the highest-id idle one; "all"
## every idle one; "military" every non-villager unit.
func _pick_units(w: SimWorld, p: SimPlayer, spec: Variant) -> Array[int]:
	if typeof(spec) == TYPE_STRING or typeof(spec) == TYPE_STRING_NAME:
		match String(spec):
			"military":
				return _military(w, p)
			"newest":
				var idle := _idle_villagers(w, p)
				return [idle[idle.size() - 1]] as Array[int] if not idle.is_empty() \
						else [] as Array[int]
			_:
				return _idle_villagers(w, p)

	var wanted := int(spec)
	var pool := _idle_villagers(w, p)
	if pool.size() < wanted:
		# PULL LABOUR OFF GATHERING rather than waiting for someone to come free, which
		# is what a person does: you grab a villager off wood to put a house up.
		#
		# Without this the AI deadlocks, and it took a full AI-vs-AI run to see it.
		# `_keep_busy` sends every idle villager to a resource, so after the first few
		# seconds NOBODY is idle -- and every remaining build and train step starved,
		# timed out and was skipped. Both AIs finished their scripts having never
		# trained a soldier, and the match ran 20,000 ticks to no conclusion.
		#
		# A villager already BUILDING is never taken: pulling it would abandon a
		# foundation, which is the one job that does not survive being interrupted.
		pool.append_array(_gathering_villagers(w, p))
	if pool.size() < wanted:
		return [] as Array[int]
	return pool.slice(0, wanted)


## Villagers with genuinely nothing to do.
##
## **A unit waiting for a path is not idle**, and treating it as such was expensive in a
## way that took a while to see. `PathService` solves a budgeted handful of searches per
## tick (4.2), so a freshly ordered villager sits at `task == IDLE` with `path_pending`
## for a few ticks -- and the standing orders, running every 5 ticks, kept issuing it
## ANOTHER order, which cancelled its queued search and requested a new one. Six
## villagers doing that indefinitely floods the path queue, so the budget is spent
## re-planning the same walks forever and nobody ever arrives anywhere. The test suite
## went from 30 seconds to over ten minutes.
func _idle_villagers(w: SimWorld, p: SimPlayer) -> Array[int]:
	var out: Array[int] = []
	for id in _sorted_ids(w):
		var u = w.entities[id]
		if u is SimUnit and u.alive and u.owner_id == p.id \
				and u.def_id == &"unit.villager" and _is_free(u):
			out.append(int(id))
	return out


## Idle, and not already on its way somewhere.
static func _is_free(u: SimUnit) -> bool:
	return u.task == SimUnit.Task.IDLE and not u.path_pending and not u.has_waypoint()


## Villagers currently gathering or carrying home -- the labour a step may pull from
## when nobody is idle. Deliberately NOT builders: see `_pick_units`.
func _gathering_villagers(w: SimWorld, p: SimPlayer) -> Array[int]:
	var out: Array[int] = []
	for id in _sorted_ids(w):
		var u = w.entities[id]
		if u is SimUnit and u.alive and u.owner_id == p.id \
				and u.def_id == &"unit.villager" \
				and (u.task == SimUnit.Task.GATHER or u.task == SimUnit.Task.RETURN):
			out.append(int(id))
	return out


func _military(w: SimWorld, p: SimPlayer) -> Array[int]:
	var out: Array[int] = []
	for id in _sorted_ids(w):
		var u = w.entities[id]
		if u is SimUnit and u.alive and u.owner_id == p.id and u.def_id != &"unit.villager":
			out.append(int(id))
	return out


## Whether every unit in `ids` that is still alive is gathering or carrying home.
##
## A dead unit is ignored rather than blocking the step: it cannot be waited for, and a
## villager killed on the way to a tree should not hold the whole script up.
static func _all_working(w: SimWorld, ids: Array) -> bool:
	var alive := 0
	for id in ids:
		var u = w.entities.get(int(id))
		if u == null or not (u is SimUnit) or not u.alive:
			continue
		alive += 1
		if u.task != SimUnit.Task.GATHER and u.task != SimUnit.Task.RETURN:
			return false
	return alive > 0


func _count_of(w: SimWorld, p: SimPlayer, def_id: StringName) -> int:
	var n := 0
	for e in w.entities.values():
		if e.alive and e.owner_id == p.id and e.def_id == def_id:
			n += 1
	return n


## The player's own building of `def_id`, or 0. Any phase -- a foundation counts as
## "the build step worked", and a trainer must be complete, which `TrainCommand`
## already refuses on its own.
func _own_building(w: SimWorld, p: SimPlayer, def_id: StringName) -> int:
	for id in _sorted_ids(w):
		var b = w.entities[id]
		if b is SimBuilding and b.alive and b.owner_id == p.id and b.def_id == def_id:
			return int(id)
	return 0


func _has_queue(w: SimWorld, p: SimPlayer, def_id: StringName) -> bool:
	var id := _own_building(w, p, def_id)
	if id == 0:
		return false
	return not (w.entities[id] as SimBuilding).queue.is_empty()


## The nearest gatherable node of `kind` to `from_unit`, ties broken by lowest id.
func _nearest_node(w: SimWorld, kind: StringName, from_unit: int) -> int:
	var from = w.entities.get(from_unit)
	if from == null:
		return 0
	var best := 0
	var best_d := 1 << 40
	for id in _sorted_ids(w):
		var n = w.entities[id]
		if not (n is SimResourceNode) or not n.alive:
			continue
		if (n as SimResourceNode).kind != kind or (n as SimResourceNode).is_depleted():
			continue
		var d: int = (n.tile() - from.tile()).length_squared()
		if d < best_d:
			best_d = d
			best = int(id)
	return best


func _nearest_enemy(w: SimWorld, p: SimPlayer, from_unit: int) -> int:
	var from = w.entities.get(from_unit)
	if from == null:
		return 0
	var candidates: Array = []          # [distance, id, is_building]
	for id in _sorted_ids(w):
		var e = w.entities[id]
		if not e.alive or e.owner_id == 0 or e.owner_id == p.id:
			continue
		if not (e is SimUnit or e is SimBuilding):
			continue
		candidates.append([int((e.tile() - from.tile()).length_squared()), int(id),
				1 if e is SimBuilding else 0])
	if candidates.is_empty():
		return 0

	# Buildings first, then nearest, then lowest id -- a TOTAL order, so the sort is
	# the same on every host even though `sort_custom` is not stable.
	candidates.sort_custom(func(a, b):
		if a[2] != b[2]:
			return a[2] > b[2]
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])

	# AND IT HAS TO BE SOMEWHERE THE ARMY CAN ACTUALLY GET TO.
	#
	# Preferring buildings unconditionally deadlocked a whole match (seed 6, found
	# 2026-08-20). p2 was down to one mining camp that no route reached, with six of
	# its villagers standing 11 steps from p1's army -- so the army was sent at the
	# camp, `_close_in` got an empty path, `set_path([])` retired it, and the standing
	# order sent it again five ticks later. Six soldiers idled beside a beaten
	# opponent for 24,000 ticks and the match never ended.
	#
	# Probing costs a path solve per candidate, so it is capped: the first candidate
	# is reachable in almost every real case, and a match where the nearest several
	# are all cut off is one where the answer hardly matters. If nothing in the cap
	# can be reached, the nearest is returned anyway -- an army that walks at the
	# wrong thing is still better than one that refuses to walk at all.
	var probes := mini(candidates.size(), REACH_PROBES)
	for i in range(probes):
		var target = w.entities[candidates[i][1]]
		if _can_reach(w, from.tile(), target.tile()):
			return int(candidates[i][1])
	return int(candidates[0][1])


## Whether a route exists from `from` to `to`, treating "already standing there" as
## reachable -- `find_path` answers both of those with an empty array (see
## `PathService.process`), and reading "I have arrived" as "I cannot get there"
## would make an army refuse the thing it is standing on.
func _can_reach(w: SimWorld, from: Vector2i, to: Vector2i) -> bool:
	if w.paths == null:
		return true          # a world with no pathing; nothing to filter on
	if w.paths.goal_for(w.map, to) == from:
		return true
	return not w.paths.find_path(w.map, from, to).is_empty()


## Where a `near` clause points. `self` is the player's town centre; anything else is
## the nearest entity of that def id -- a resource for a drop-off camp, a building for
## an adjacency-gated field.
func _anchor_tile(w: SimWorld, p: SimPlayer, near: StringName, from_unit: int) -> Vector2i:
	if near == &"self":
		var tc := _own_building(w, p, &"building.town_center")
		return (w.entities[tc] as SimBuilding).tile() if tc != 0 else Vector2i(-1, -1)

	var own := _own_building(w, p, near)
	if own != 0:
		return (w.entities[own] as SimBuilding).tile()

	var rd: ResourceDef = GameDataRegistry.resource_def(near)
	if rd != null:
		var node := _nearest_node(w, rd.kind, from_unit)
		return (w.entities[node] as SimResourceNode).tile() if node != 0 else Vector2i(-1, -1)
	return Vector2i(-1, -1)


## A legal origin for `def_id` near `anchor`, searched as a widening ring in a FIXED
## order so two hosts pick the same tile.
##
## Asks the same two questions the placement ghost does -- `adjacency_allows()` for a
## field's mill, `can_place_building()` for the ground -- rather than guessing, which is
## why a field lands beside its mill without the script having to say where.
func _find_spot(w: SimWorld, p: SimPlayer, def_id: StringName, anchor: Vector2i) -> Vector2i:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd == null:
		return Vector2i(-1, -1)
	var footprint := bd.footprint
	# `adjacency_allows()` COUNTS ABUTTING BUILDINGS, so it walks the entity list. Only
	# a field needs it (`requires_adjacent`), and asking it per candidate tile for
	# everything else was most of what made this the hottest thing in the sim.
	var needs_adjacency := not bd.requires_adjacent.is_empty()

	for radius in range(2, MAX_PLACEMENT_RADIUS):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue          # only the new ring; inner ones were searched
				var origin := anchor + Vector2i(dx, dy)
				if not w.map.can_place_building(SimMap.footprint_rect(origin, footprint)):
					continue
				if needs_adjacency and not w.adjacency_allows(def_id, p.id, origin):
					continue
				return origin
	return Vector2i(-1, -1)
