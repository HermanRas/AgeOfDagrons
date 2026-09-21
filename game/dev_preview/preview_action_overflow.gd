extends Node

## Which rows ask `SelectionActions` for more than its eight slots, and what
## `_capped()` throws away when they do. Board card `8.x-action-column-overflow`.
## **THE EXIT CODE IS THE ANSWER** -- headless, no screenshots.
##
##     godot --headless --path game res://dev_preview/preview_action_overflow.tscn
##
## ## ⛔ WHY A PREVIEW AND NOT ONLY A TEST: THE TEST THAT COVERS THIS CANNOT FAIL
##
## `test_a_train_row_never_overflows_its_grid_at_any_age` asserts
## `for_selection(...).size() <= MAX_ACTIONS`. That is not an assertion about the
## roster, it is an assertion about `_capped()`, which slices to exactly that
## number -- so the test is green for every building that has ever existed and
## would stay green if a building emitted forty actions. The thing worth asserting
## is the UNCAPPED row, and nothing was reading it.
##
## Its fixture made the blind spot worse: `_building_facts` carries no `phase`, so
## `int(facts.get("phase", -1)) != COMPLETE` and the gate, garrison and research
## branches never ran at all. Every building was measured in its THINNEST state.
##
## ## WHAT THIS ENUMERATES
##
## Every building x age 1..4 x the state axes that change the row's LENGTH --
## phase, whether a rally point is set, garrison occupancy, gate state and the
## owner's tech set. Occupancy, gate and techs turn out to move only `enabled` and
## `badge`, never the count; they are enumerated anyway rather than reasoned about,
## because that is the assumption this card was filed for getting wrong.
##
## For each combination it compares `_building_actions()` -- uncapped -- against
## what `for_selection()` returns, and names what fell off.
##
## ## THE VERDICT IT APPLIES, AND THE DISTINCTION THAT MATTERS
##
## A dropped **enabled** action is a verb the player has lost and is a PROBLEM.
## A dropped **disabled** placeholder is the cap working as intended -- Repair is
## last in `_building_actions` precisely so it is the one that goes -- and is a
## NOTE. Both are printed; only the first sets the exit code.

const _AGES := [1, 2, 3, 4]

var _problems: Array[String] = []
var _notes: Array[String] = []
var _overflows := 0
var _rows := 0


func _ready() -> void:
	print("=== action column overflow ===")
	print("MAX_ACTIONS = %d\n" % SelectionActions.MAX_ACTIONS)

	_check_the_warning_fires()
	_check_buildings()
	_check_units()
	_finish()


## ⚠️ **THE WARNING IS PROVEN HERE RATHER THAN ASSUMED, BECAUSE NOTHING IN THE GAME
## TRIPS IT.** Every real row fits today, so `_capped`'s new complaint would never run
## and a typo in it would sit undetected until the day a verb was added -- which is
## precisely the day somebody is relying on it. §5's rule: a check verified against the
## fault it is for, not against the absence of one.
##
## A warning cannot be asserted, so this prints the row and says what to look for. The
## line should appear on stderr immediately above the buildings table.
func _check_the_warning_fires() -> void:
	var row: Array[HudAction] = []
	for i in range(SelectionActions.MAX_ACTIONS + 3):
		row.append(HudAction.new(&"synthetic:%d" % i, "Slot %d" % i))
	var kept := SelectionActions._capped(row, "a synthetic row (preview self-check)")
	if kept.size() != SelectionActions.MAX_ACTIONS:
		_fail("_capped returned %d for an %d-action row" % [kept.size(), row.size()])
	print("  self-check: %d actions in, %d out -- a warning naming synthetic:8..10"
			% [row.size(), kept.size()])
	print("  should have just printed above. If it did not, `_capped` is silent again.\n")


func _check_buildings() -> void:
	print("-- buildings --")
	for building_id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(building_id)
		if bd == null:
			continue
		var worst := 0
		var worst_row: Array[HudAction] = []
		var worst_state := ""

		for age in _AGES:
			for phase in [SimBuilding.Phase.FOUNDATION, SimBuilding.Phase.COMPLETE]:
				for rally in [false, true]:
					for full in [false, true]:
						for locked in [false, true]:
							for done in [false, true]:
								var facts := _facts(building_id, bd, phase, rally, full, locked)
								var researched := _researched(bd, age) if done else {}
								var row := SelectionActions._building_actions(
										building_id, age, facts, researched)
								_rows += 1
								if row.size() > worst:
									worst = row.size()
									worst_row = row
									worst_state = _describe(age, phase, rally, full, locked, done)

		_tally(building_id, worst, worst_row, worst_state)


func _check_units() -> void:
	print("\n-- units --")
	for unit_id in GameDataRegistry.unit_ids():
		var ud: UnitDef = GameDataRegistry.unit(unit_id)
		if ud == null:
			continue
		var worst := 0
		var worst_row: Array[HudAction] = []
		var worst_state := ""
		for stance in [SimUnit.Stance.AGGRESSIVE, SimUnit.Stance.DEFENSIVE,
				SimUnit.Stance.STAND_GROUND, SimUnit.Stance.PASSIVE]:
			for cooldown in [0, 120]:
				var facts := {
					"id": 1, "def_id": unit_id, "owner_id": 1, "hp": 30, "max_hp": 30,
					"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0,
					"stance": stance, "ability_cooldown": cooldown,
				}
				var row := SelectionActions._unit_actions(unit_id, facts)
				_rows += 1
				if row.size() > worst:
					worst = row.size()
					worst_row = row
					worst_state = "stance %d, cooldown %d" % [stance, cooldown]
		_tally(unit_id, worst, worst_row, worst_state)


## One entity's `GameView.facts_for()` dict, in the state the axes name.
##
## `waypoint` is OMITTED rather than set to `NO_WAYPOINT` in the no-rally case, because
## both reach `_has_rally_point` and only the absent one matches what arrives for a
## building that predates the field or for a remembered enemy entry.
func _facts(building_id: StringName, bd: BuildingDef, phase: int, rally: bool,
		full: bool, locked: bool) -> Dictionary:
	var facts := {
		"id": 6, "def_id": building_id, "owner_id": 1, "hp": 1000, "max_hp": 1000,
		"alive": true, "queue_len": 0, "queue_fraction": 0.0, "phase": phase,
		"garrison_count": bd.garrison_cap if full else 0,
		"gate_locked": locked,
	}
	if rally:
		facts["waypoint"] = Vector2i(5, 5)
	return facts


## Every technology this building offers at this age, marked done.
func _researched(bd: BuildingDef, age: int) -> Dictionary:
	var out := {}
	for id in GameDataRegistry.techs_at(bd.id):
		var t: TechDef = GameDataRegistry.tech(id)
		if t != null and t.age_required <= age:
			out[t.id] = true
	return out


func _describe(age: int, phase: int, rally: bool, full: bool, locked: bool,
		done: bool) -> String:
	var bits: Array[String] = ["age %d" % age]
	bits.append("complete" if phase == SimBuilding.Phase.COMPLETE else "foundation")
	if rally:
		bits.append("rally point set")
	if full:
		bits.append("garrison full")
	if locked:
		bits.append("gate locked")
	if done:
		bits.append("techs researched")
	return ", ".join(bits)


## Every row's WORST case, printed whether or not it overflows.
##
## ⚠️ **THE HEADROOM IS THE POINT AND IT IS WHY NOTHING IS FILTERED OUT HERE.** This
## file was written expecting overflows and found none; a report that printed only
## the failures would have been a blank page, which says "no problem" and not "the
## castle is one tile from the edge". `8.x-build-menu-modal` wants to add a tile to
## these rows, and the number it needs is this column.
func _tally(def_id: StringName, worst: int, row: Array[HudAction], state: String) -> void:
	var room := SelectionActions.MAX_ACTIONS - worst
	var flag := "   "
	if room < 0:
		flag = "⛔ "
	elif room == 0:
		flag = "!! "
	print("  %s%-28s %d/%d  (%s)" % [flag, def_id, worst,
			SelectionActions.MAX_ACTIONS, state])
	if room <= 0:
		var ids: Array[String] = []
		for a in row:
			ids.append(String(a.id) if a.enabled else "(%s)" % a.id)
		print("      %s" % ", ".join(ids))
	if room == 0:
		_notes.append("%s is FULL at %d actions (%s) -- no room for another tile"
				% [def_id, worst, state])
	if worst > SelectionActions.MAX_ACTIONS:
		_report(def_id, row, state)


## What the cap throws away for this row, and whether any of it was a live verb.
func _report(def_id: StringName, row: Array[HudAction], state: String) -> void:
	_overflows += 1
	var kept: Array[String] = []
	var lost_enabled: Array[String] = []
	var lost_placeholder: Array[String] = []
	for i in row.size():
		var a: HudAction = row[i]
		if i < SelectionActions.MAX_ACTIONS:
			kept.append(String(a.id))
		elif a.enabled:
			lost_enabled.append(String(a.id))
		else:
			lost_placeholder.append(String(a.id))

	print("  %s -- %d actions (%s)" % [def_id, row.size(), state])
	print("      kept: %s" % ", ".join(kept))
	if not lost_placeholder.is_empty():
		print("      dropped (disabled placeholder): %s" % ", ".join(lost_placeholder))
		_notes.append("%s drops the disabled %s at %d actions (%s)"
				% [def_id, ", ".join(lost_placeholder), row.size(), state])
	if not lost_enabled.is_empty():
		print("      ⛔ DROPPED A LIVE VERB: %s" % ", ".join(lost_enabled))
		_problems.append("%s silently loses %s with %s"
				% [def_id, ", ".join(lost_enabled), state])


func _fail(message: String) -> void:
	_problems.append(message)


func _finish() -> void:
	print("\n%d rows enumerated, %d over the cap." % [_rows, _overflows])
	for n in _notes:
		print("NOTE: %s" % n)
	if _problems.is_empty():
		print("\nOK -- nothing enabled is sliced off any row.")
		get_tree().quit(0)
		return
	print("\n%d PROBLEM(S):" % _problems.size())
	for p in _problems:
		print("  - %s" % p)
	get_tree().quit(1)
