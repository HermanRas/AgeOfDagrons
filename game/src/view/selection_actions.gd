## What the current selection can DO, and what a chosen action expands into
## (UI_Design.md selection-panel redesign).
##
## Pure and static: every function here answers from `GameView.facts_for()`
## dictionaries and `GameData` defs alone -- no nodes, no tree, no sim. That is
## what lets the whole action model be asserted in a headless test, and it
## keeps `SelectionPanel` down to "draw what this returns", the same division
## `GameView.tap_action()` already draws between deciding and doing.
##
## MVP reality check: only move, stop, gather, build, train, cancel-production
## and destroy have commands behind them (`src/sim/commands/`). Attack, repair,
## research/upgrades, garrison and formations do not -- `SimUnit.Task` declares
## ATTACK/GARRISON/STAND_GROUND/FLEE but only IDLE/MOVE/GATHER/RETURN/BUILD are
## implemented. Those are emitted here as `enabled = false` placeholders so the
## panel reads finished; see `HudAction`'s header for why that beats omitting
## them.
class_name SelectionActions
extends RefCounted

## The action column is a 4-wide grid two rows deep, and the detail grid is
## 4-wide three rows deep -- both authored in the ui_builder HUD mockup.
const MAX_ACTIONS := 8
const MAX_DETAILS := 12

## Icon filenames in `res://assets/ui/icons/`. Four of these are deliberately
## the NEAREST existing icon rather than art of their own, logged in
## ASSET_MISSING.md 1.5 for a proper bake later:
##   harvest -> res_wood.png    (a resource, not a gather verb)
##   repair  -> act_guard.png   (protect, not mend)
##   upgrade -> hud_techtree.png (the tech-tree HUD button)
## Formations have no near-enough icon at all and fall back to their label.
const ICONS := {
	&"move": "act_move.png",
	&"stop": "act_stop.png",
	&"attack": "act_attack.png",
	&"build": "act_build.png",
	&"harvest": "res_wood.png",
	&"repair": "act_guard.png",
	&"upgrade": "hud_techtree.png",
	&"destroy": "act_destroy.png",
	&"garrison": "act_garrison.png",
}

## Formation/stance choices a military unit's Move action expands into
## (UI_Design.md). No formation exists in the sim, so all four are disabled.
const FORMATIONS: Array[StringName] = [&"line", &"grid", &"vee", &"box"]


## The action column for the current selection.
##
## `facts` is the PRIMARY entity's `GameView.facts_for()` dict; `all_def_ids`
## is every selected entity's def_id (empty for a single selection). An empty
## return means "nothing this selection can be told to do" -- true for anything
## not owned by the local player, which still shows its portrait and health.
static func for_selection(facts: Dictionary, selected_count: int = 1,
		is_mine: bool = true, all_def_ids: Array = []) -> Array[HudAction]:
	if facts.is_empty() or not is_mine:
		return []

	var def_id: StringName = facts.get("def_id", &"")

	# A mixed or multi selection offers only what EVERY member can do, so a
	# group order never silently applies to half of it (UI_Design.md). Move,
	# stop and destroy hold for any owned entity; attack is listed for the
	# same reason it is on a single unit, and is equally not implemented.
	if selected_count > 1:
		return _capped([
			_act(&"move"), _act(&"stop"), _act(&"attack", false), _act(&"destroy"),
		])

	if GameDataRegistry.building(def_id) != null:
		return _capped(_building_actions(def_id))
	return _capped(_unit_actions(def_id))


## What tapping an `expands` action fills the detail grid with; `[]` for an
## action that just issues its order.
##
## Called with `action_id = &""` for "nothing expanded", which is when the grid
## shows the selection's own default detail -- a building's production queue,
## or a group's roster.
static func details_for(action_id: StringName, facts: Dictionary,
		selected_count: int = 1, all_def_ids: Array = []) -> Array[HudAction]:
	if facts.is_empty():
		return []

	if action_id == &"build":
		return _capped_details(_buildable_details())
	if action_id == &"move":
		return _capped_details(_formation_details())

	# Nothing expanded: the grid falls back to whatever the selection itself
	# has to show.
	if selected_count > 1:
		return _roster_details(all_def_ids)
	if GameDataRegistry.building(facts.get("def_id", &"")) != null:
		return _capped_details(_queue_details(facts))
	return []


## A building trains units (5.4, real), and would repair/upgrade/be destroyed.
## Destroy is debug-only until combat exists (PLAN.md 5.5) but is a real
## command today, so it is enabled.
static func _building_actions(def_id: StringName) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd == null:
		return out

	for unit_def_id in bd.trains:
		var ud: UnitDef = GameDataRegistry.unit(unit_def_id)
		var a := HudAction.new(&"train:%s" % unit_def_id,
				ud.name if ud != null and not ud.name.is_empty() else String(unit_def_id))
		a.payload = unit_def_id          # ActionSlot crops the unit's own portrait
		out.append(a)

	out.append(_act(&"upgrade", false))
	out.append(_act(&"repair", false))
	out.append(_act(&"destroy"))
	return out


## A unit's own verbs. Harvest and Build are gated on the def actually being a
## gatherer -- MVP's only unit is the villager, so this is the closest thing to
## a "is a worker" flag until one exists; a soldier def with no `gather_rate`
## correctly gets neither.
static func _unit_actions(def_id: StringName) -> Array[HudAction]:
	var out: Array[HudAction] = [_act(&"move"), _act(&"stop"), _act(&"attack", false)]
	var ud: UnitDef = GameDataRegistry.unit(def_id)
	if ud == null:
		return out

	if not ud.gather_rate.is_empty():
		var build := _act(&"build")
		build.expands = true             # offers the buildings to place
		out.append(build)
		out.append(_act(&"harvest"))
	elif ud.attack_damage > 0:
		# Formations hang off Move for a military unit only (UI_Design.md).
		# "Military" is fights INSTEAD of working, not merely "can fight": the
		# villager carries attack.damage 3 to defend itself (data/units.json)
		# and would otherwise be offered formations it has no business in.
		(out[0] as HudAction).expands = true
	out.append(_act(&"destroy"))
	return out


## Every building in the data set, as placement choices. There is no
## per-builder restriction in `BuildingDef` yet (nor an age gate wired to a
## real age), so a villager is offered all of them -- `PlaceBuildingCommand`
## still refuses one it cannot afford.
static func _buildable_details() -> Array[HudAction]:
	var out: Array[HudAction] = []
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		var a := HudAction.new(&"place:%s" % id,
				bd.name if bd != null and not bd.name.is_empty() else String(id))
		a.payload = id
		out.append(a)
	return out


## Formation choices for a military unit's Move (UI_Design.md). No formation
## system exists, so every one is a disabled placeholder, and none has icon art
## -- they read by label alone.
static func _formation_details() -> Array[HudAction]:
	var out: Array[HudAction] = []
	for f in FORMATIONS:
		out.append(HudAction.new(&"formation:%s" % f, String(f).capitalize(), "", false))
	return out


## A building's production queue, one slot per queued unit (5.4). Tapping one
## cancels it, which `CancelProductionCommand` already supports.
static func _queue_details(facts: Dictionary) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var queue: Array = facts.get("queue", [])
	var queue_len := int(facts.get("queue_len", queue.size()))

	for i in range(queue_len):
		var unit_def_id: StringName = queue[i] if i < queue.size() else &""
		var ud: UnitDef = GameDataRegistry.unit(unit_def_id)
		var a := HudAction.new(&"cancel:%d" % i,
				ud.name if ud != null and not ud.name.is_empty() else "Queued")
		a.payload = unit_def_id
		# The front entry is the one actually building; show its progress.
		if i == 0:
			a.badge = "%d%%" % roundi(float(facts.get("queue_fraction", 0.0)) * 100.0)
		out.append(a)
	return out


## Every selected entity as a portrait. Past `MAX_DETAILS` the LAST slot
## becomes a "+N" counter rather than a portrait, so the grid never lies about
## how many are selected (UI_Design.md: "if they are more than 11 the last
## block shows +x overflow").
static func _roster_details(all_def_ids: Array) -> Array[HudAction]:
	var out: Array[HudAction] = []
	if all_def_ids.is_empty():
		return out

	var shown := all_def_ids.size()
	var overflow := 0
	if shown > MAX_DETAILS:
		shown = MAX_DETAILS - 1
		overflow = all_def_ids.size() - shown

	for i in range(shown):
		var a := HudAction.new(&"member:%d" % i, "")
		a.payload = all_def_ids[i]
		out.append(a)

	if overflow > 0:
		var more := HudAction.new(&"overflow", "+%d" % overflow, "", false)
		more.badge = ""
		out.append(more)
	return out


static func _act(id: StringName, enabled: bool = true) -> HudAction:
	return HudAction.new(id, String(id).capitalize(), ICONS.get(id, ""), enabled)


static func _capped(actions: Array[HudAction]) -> Array[HudAction]:
	return actions.slice(0, MAX_ACTIONS)


static func _capped_details(details: Array[HudAction]) -> Array[HudAction]:
	return details.slice(0, MAX_DETAILS)
