## What the current selection can DO, and what a chosen action expands into
## (UI_Design.md selection-panel redesign).
##
## Pure and static: every function here answers from `GameView.facts_for()`
## dictionaries and `GameData` defs alone -- no nodes, no tree, no sim. That is
## what lets the whole action model be asserted in a headless test, and it
## keeps `SelectionPanel` down to "draw what this returns", the same division
## `GameView.tap_action()` already draws between deciding and doing.
##
## Reality check, kept current: move, stop, gather, build, train,
## cancel-production, attack, upgrade, gate, GARRISON and destroy all have commands
## behind them (`src/sim/commands/`). **Repair and formations do not**, and
## `SimUnit.Task` still declares STAND_GROUND and FLEE with no verb here. Those are
## emitted as `enabled = false` placeholders so the panel reads finished; see
## `HudAction`'s header for why that beats omitting them.
##
## This list said garrison was unimplemented until 2026-08-27, when 4.8 landed. Note
## which side of it is here: the GARRISON order itself is issued by a TAP on the
## building (`GameView.tap_action`), exactly as gather and build-assist are, so the
## action in this file is the one on the BUILDING -- who is inside, and letting them
## out again.
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
## Formations and the two page arrows have no near-enough icon at all and fall
## back to their label, which for the arrows is the whole point -- "<" and ">"
## read as navigation at 72 px in a way no icon in the pack does.
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
	# A GATE'S TWO STATES SHARE THE ENTER/EXIT PAIR, which is the nearest thing the
	# pack has to a door -- and it is the same "nearest existing icon" call the three
	# above make. It also puts PLAN.md 13.2 item 4b to some use: that open item asks
	# whether act_enter/act_garrison and act_exit/act_leave are two pairs covering one
	# concept each, and a gate is a second real consumer of one half of them.
	&"enter": "act_enter.png",
	&"exit": "act_exit.png",
}

## The two page-navigation slots. They are real HudActions in the grid rather
## than chrome around it, because the grid IS the 12 slots -- an arrow drawn
## outside it would need layout the panel does not have, and one drawn over a
## slot would cover a building.
const PAGE_PREV := &"page:prev"
const PAGE_NEXT := &"page:next"

## Formation/stance choices a military unit's Move action expands into
## (UI_Design.md). No formation exists in the sim, so all four are disabled.
const FORMATIONS: Array[StringName] = [&"line", &"grid", &"vee", &"box"]


## The action column for the current selection.
##
## `facts` is the PRIMARY entity's `GameView.facts_for()` dict; `all_def_ids`
## is every selected entity's def_id (empty for a single selection). An empty
## return means "nothing this selection can be told to do" -- true for anything
## not owned by the local player, which still shows its portrait and health.
## `age` is the SELECTION OWNER's age (SimPlayer.age, arriving via
## GameView.age_of), and it gates the train and build rows: a building lists only
## the units its owner has reached the age for, and a villager only the buildings
## they may place. Defaults to 1 so a caller that has no age yet still gets the
## age-1 menu rather than an empty one.
static func for_selection(facts: Dictionary, selected_count: int = 1,
		is_mine: bool = true, all_def_ids: Array = [], age: int = 1) -> Array[HudAction]:
	if facts.is_empty() or not is_mine:
		return []

	var def_id: StringName = facts.get("def_id", &"")

	# A mixed or multi selection offers only what EVERY member can do, so a
	# group order never silently applies to half of it (UI_Design.md). Move,
	# stop and destroy hold for any owned entity; attack is listed for the
	# same reason it is on a single unit, and is equally not implemented.
	if selected_count > 1:
		# Attack is enabled without checking every member: AttackCommand accepts a
		# mixed selection and tasks whoever in it can actually fight, so a group
		# with one trade cart in it is not a group that may not be sent to war.
		return _capped([
			_act(&"move"), _act(&"stop"), _act(&"attack"), _act(&"destroy"),
		])

	if GameDataRegistry.building(def_id) != null:
		return _capped(_building_actions(def_id, age, facts))
	return _capped(_unit_actions(def_id))


## What tapping an `expands` action fills the detail grid with; `[]` for an
## action that just issues its order.
##
## Called with `action_id = &""` for "nothing expanded", which is when the grid
## shows the selection's own default detail -- a building's production queue,
## or a group's roster.
static func details_for(action_id: StringName, facts: Dictionary,
		selected_count: int = 1, all_def_ids: Array = [], age: int = 1) -> Array[HudAction]:
	if facts.is_empty():
		return []

	# NOT capped: the build list is the one detail list that can outgrow the grid,
	# and it is the caller's `page_of()` that slices it. Capping here would throw
	# away the buildings page 2 exists to show.
	if action_id == &"build":
		return _buildable_details(age)
	# The garrison is the SECOND list that can outgrow the grid, and it is why this
	# one is uncapped too: a full castle is 15 occupants plus the Empty slot, which is
	# 16 against MAX_DETAILS' 12. Capped, the last four archers would be silently
	# un-ejectable -- the exact failure `_buildable_details` records having had with
	# the town centre falling off the end of the build list.
	if action_id == &"garrison":
		return _garrison_details(facts)
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
## `bd.trains` is the building's WHOLE roster across every age; each unit carries
## its own `age_required` (units.json). Units above the owner's age are OMITTED
## rather than shown disabled, unlike the unimplemented verbs below -- a disabled
## Attack tells the player the button exists and does not work yet, but a
## disabled Crossbowman in age 2 would be a promise about a future age, and the
## tech tree (9.4) is where that belongs. It also keeps the row inside its 8
## slots: a castle trains four things and an age-4 dock four more.
static func _building_actions(def_id: StringName, age: int = 1,
		facts: Dictionary = {}) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd == null:
		return out

	# A GATE OPENS AND SHUTS (PLAN.md 5.8), and the button says which of the two it is
	# about to do rather than being labelled "gate". Read off the snapshot, so a gate
	# somebody else's command just locked reads correctly the next tick.
	#
	# ONLY WHEN COMPLETE: `ToggleGateCommand` refuses a gate that is still a
	# foundation, and offering the button anyway would be a button that does nothing.
	if bd.is_gate and int(facts.get("phase", -1)) == SimBuilding.Phase.COMPLETE:
		var locked := bool(facts.get("gate_locked", false))
		out.append(HudAction.new(&"gate", "Open Gate" if locked else "Close Gate",
				ICONS.get(&"exit" if locked else &"enter", ""), true))

	# WHO IS INSIDE, AND A WAY OUT (PLAN.md 4.8). Only for a building that can hold
	# anybody at all -- three of the 31 -- so 28 buildings are unchanged and the
	# castle's row stays inside its 8 slots (4 trains + this + upgrade + repair +
	# destroy = 8 exactly; `_capped` would have dropped Destroy at 9).
	#
	# The badge is the count against the cap, which is the only place in the HUD that
	# says how full a tower is. Disabled at 0 rather than hidden, so the slot does not
	# move under the player's thumb as archers walk in and out -- the same reasoning
	# `HudAction`'s header gives for showing unimplemented verbs disabled.
	#
	# `expands`, so tapping it lists the occupants and one of them can be picked out
	# individually; the ORDER goes out from the detail grid, not from this button.
	if bd.garrison_cap > 0 and int(facts.get("phase", -1)) == SimBuilding.Phase.COMPLETE:
		var inside := int(facts.get("garrison_count", 0))
		var g := HudAction.new(&"garrison", "Garrison",
				ICONS.get(&"garrison", ""), inside > 0)
		g.badge = "%d/%d" % [inside, bd.garrison_cap]
		g.expands = true
		out.append(g)

	for unit_def_id in bd.trains:
		var ud: UnitDef = GameDataRegistry.unit(unit_def_id)
		if ud != null and ud.age_required > age:
			continue
		var a := HudAction.new(&"train:%s" % unit_def_id,
				ud.name if ud != null and not ud.name.is_empty() else String(unit_def_id))
		a.payload = unit_def_id          # ActionSlot crops the unit's own portrait
		# What it costs, along the top of the tile (project owner, 2026-08-22). Handed
		# over as the def's own dictionary rather than a formatted string; `ActionSlot`
		# is what knows how to abbreviate one.
		if ud != null:
			a.cost = ud.cost
		out.append(a)

	out.append(_upgrade_action(bd, age, facts))
	out.append(_act(&"repair", false))
	out.append(_act(&"destroy"))
	return out


## Upgrade, which is a REAL verb for anything declaring `upgrades_to` and the same
## disabled placeholder it has always been for everything else (PLAN.md 5.8).
##
## Only the three long wall segments qualify today, and each becomes its tier's gate.
## The label is the TARGET's own name -- "Palisade Gate", not "Upgrade" -- because
## "Upgrade" on a wall says nothing about what you are about to get, and the player is
## being asked to spend on it. Same reason a train button says "Archer".
##
## Age is checked here as well as in `UpgradeBuildingCommand.validate()`, so a player
## holding an age-2 wall does not get a live button for a gate they cannot buy yet.
## Affordability deliberately is NOT: the panel shows what a building can do, the
## command refuses what the player cannot pay for, and a button that vanishes when
## your wood dips is harder to find than one that says no.
static func _upgrade_action(bd: BuildingDef, age: int, facts: Dictionary) -> HudAction:
	if bd.upgrades_to == &"" or int(facts.get("phase", -1)) != SimBuilding.Phase.COMPLETE:
		return _act(&"upgrade", false)
	var to: BuildingDef = GameDataRegistry.building(bd.upgrades_to)
	if to == null or to.age_required > age:
		return _act(&"upgrade", false)
	# NO ICON, deliberately, where the disabled placeholder above keeps one. `ICONS`
	# maps upgrade to `hud_techtree.png`, which its own note admits is the nearest
	# thing in the pack rather than art for this -- and `ActionSlot` prefers an icon
	# file over the payload portrait, so passing it would draw a tech-tree glyph on
	# top of a perfectly good picture of the gate. Left blank, the slot crops the
	# gate's own sprite exactly as the train and place cells do.
	var a := HudAction.new(&"upgrade",
			to.name if not to.name.is_empty() else String(to.id), "", true)
	a.payload = to.id
	return a


## A unit's own verbs. Harvest and Build are gated on the def actually being a
## gatherer -- MVP's only unit is the villager, so this is the closest thing to
## a "is a worker" flag until one exists; a soldier def with no `gather_rate`
## correctly gets neither.
static func _unit_actions(def_id: StringName) -> Array[HudAction]:
	var ud: UnitDef = GameDataRegistry.unit(def_id)
	# Enabled by whether this unit HAS an attack, which is damage and nothing
	# else (4.13). That deliberately includes the villager -- she carries damage 3
	# to defend herself, and a peasant that may not be told to fight back would be
	# a stranger rule than one that may. A trade cart, at damage 0, gets the
	# disabled placeholder it always had.
	var out: Array[HudAction] = [_act(&"move"), _act(&"stop"),
			_act(&"attack", ud != null and ud.attack_damage > 0)]
	if ud == null:
		return out

	if not ud.gather_rate.is_empty():
		var build := _act(&"build")
		build.expands = true             # offers the buildings to place, paged
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


## Every building a villager may place, gated by the owner's age
## (`BuildingDef.age_required`). There is still no per-builder restriction --
## every worker is offered the same list -- and `PlaceBuildingCommand` still
## refuses one they cannot afford.
##
## Returned WHOLE, however long. 19 buildings do not fit MAX_DETAILS, and the
## answer is `page_of()`, not a cap: a capped list drops buildings silently,
## which is how the town centre came to fall off the end of an ungated version
## of this while the wonder stayed on it.
##
## RE-SORTED, not taken in `building_ids()` order. That function sorts an
## Array[StringName], which orders by StringName IDENTITY rather than by string
## content (test_game_data pins exactly that), so its order is whatever the
## engine happened to intern these in -- arbitrary, and not necessarily the same
## between runs. A menu whose buttons move is worse than one in a dull order, so
## this sorts by (age unlocked, then display name): the buildings a player has
## had longest stay put at the front and stay on page 1, and each age's additions
## arrive together at the back.
static func _buildable_details(age: int = 1) -> Array[HudAction]:
	var matching: Array[BuildingDef] = []
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd == null or bd.age_required > age:
			continue
		# `buildable: false` is "the system may place this, the menu may not offer
		# it" (PLAN.md 5.8). Only walls use it: a tier is four defs and two of them
		# -- the medium and long segments -- are chosen by the drag rather than by a
		# player, so without this filter the grid would carry all twelve wall pieces
		# and each of the eight extras would place one fixed-length block.
		if not bd.buildable:
			continue
		matching.append(bd)

	matching.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		if a.age_required != b.age_required:
			return a.age_required < b.age_required
		return a.name < b.name)

	var out: Array[HudAction] = []
	for bd in matching:
		var action := HudAction.new(&"place:%s" % bd.id,
				bd.name if not bd.name.is_empty() else String(bd.id))
		action.payload = bd.id
		# A WALL TIER PRICES ITS SHORT SEGMENT, which is what the tile stands for and
		# what one tap of the drag lays down. A run costs a multiple of it and the
		# readout under the finger gives the real total once the drag is under way --
		# there is no single number that is true of a wall before it is dragged.
		action.cost = bd.cost
		out.append(action)
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


## Who is garrisoned, one slot each, plus an "Empty" slot that turns the lot out
## (PLAN.md 4.8). Tapping an occupant ejects that one.
##
## THE EMPTY SLOT COMES FIRST AND IS `ungarrison:all`. Turning everybody out is the
## common action -- it is what a player does when the raid is over -- and it must not
## be fifteen taps. It lives in the DETAIL grid rather than being what the Garrison
## action itself does, because that action has to expand to show the roster at all,
## and an action cannot both expand and issue an order (`SelectionPanel`'s
## `_on_action_pressed` treats `expands` as a view toggle and returns).
##
## Occupant slots carry the unit's def id as `payload`, so `ActionSlot` crops that
## unit's own portrait -- the same mechanism the production queue uses, and the reason
## `SimBuilding.to_snapshot` sends def ids for the garrison at all.
##
## INDEXED, NOT NAMED BY ENTITY. `UngarrisonCommand`'s header has the argument: a
## garrisoned unit is not in the snapshot, so the client has no id to send, and a
## stale index ejecting the wrong archer is an accepted and recoverable cost.
static func _garrison_details(facts: Dictionary) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var inside: Array = facts.get("garrison", [])
	var count := int(facts.get("garrison_count", inside.size()))
	if count <= 0:
		return out

	out.append(HudAction.new(&"ungarrison:all", "Empty", ICONS.get(&"exit", ""), true))
	for i in range(count):
		var unit_def_id: StringName = inside[i] if i < inside.size() else &""
		var ud: UnitDef = GameDataRegistry.unit(unit_def_id)
		var a := HudAction.new(&"ungarrison:%d" % i,
				ud.name if ud != null and not ud.name.is_empty() else "Garrisoned")
		a.payload = unit_def_id
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


# ── paging the detail grid ──────────────────────────────────────────────────
#
# The grid is 12 slots and the age-4 build list is 19 buildings, so it pages.
# The project owner specified the shape (2026-08-16): the LAST slot of a page
# that has more after it is ">", and the FIRST slot of any page after the first
# is "<". A middle page therefore carries both.
#
# The arrows live INSIDE the 12 slots, which is what makes the arithmetic below
# non-obvious: a page's capacity depends on which arrows it needs, and whether it
# needs ">" depends on whether the remaining items fit -- which depends on the
# capacity. _page_offsets() resolves that by walking the list once rather than
# trying to close the loop with a formula.
#
# Kept here rather than in SelectionPanel for the same reason everything else in
# this file is: it is pure arithmetic over a list, so it is assertable headless
# without building a panel. The panel owns only WHICH page is open.


## Where each page starts. One entry per page; a single-page list returns [0].
static func _page_offsets(total: int) -> PackedInt32Array:
	var offsets := PackedInt32Array([0])
	if total <= MAX_DETAILS:
		return offsets

	# Page 0 has no "<" but does have ">", so it holds MAX_DETAILS - 1.
	var consumed := MAX_DETAILS - 1
	while consumed < total:
		offsets.append(consumed)
		# Every later page spends a slot on "<". It spends another on ">" only if
		# what is left will not fit without one.
		var room := MAX_DETAILS - 1
		if total - consumed > room:
			room -= 1
		consumed += room
	return offsets


static func page_count(total: int) -> int:
	return _page_offsets(total).size()


## One page of `details`, with its navigation slots in place. `page` is clamped,
## so a caller holding a stale page number after the list shrank -- a villager
## on page 2 of the age-4 list whose owner somehow drops to age 1 -- lands on the
## last real page instead of on an empty grid.
static func page_of(details: Array[HudAction], page: int) -> Array[HudAction]:
	var offsets := _page_offsets(details.size())
	var index := clampi(page, 0, offsets.size() - 1)

	var out: Array[HudAction] = []
	if index > 0:
		out.append(_nav(PAGE_PREV, "<"))

	var start := offsets[index]
	var end := offsets[index + 1] if index + 1 < offsets.size() else details.size()
	for i in range(start, end):
		out.append(details[i])

	if index + 1 < offsets.size():
		out.append(_nav(PAGE_NEXT, ">"))
	return out


## An arrow. Enabled -- unlike the disabled placeholders elsewhere in this file,
## this one does something -- but carrying no payload, so a listener that
## dispatches on `place:`/`cancel:` prefixes ignores it without a special case.
static func _nav(id: StringName, label: String) -> HudAction:
	return HudAction.new(id, label, "", true)


static func _act(id: StringName, enabled: bool = true) -> HudAction:
	return HudAction.new(id, String(id).capitalize(), ICONS.get(id, ""), enabled)


static func _capped(actions: Array[HudAction]) -> Array[HudAction]:
	return actions.slice(0, MAX_ACTIONS)


static func _capped_details(details: Array[HudAction]) -> Array[HudAction]:
	return details.slice(0, MAX_DETAILS)
