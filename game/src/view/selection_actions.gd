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
## cancel-production, attack, upgrade, gate, garrison, STANCE, FORMATIONS, ABILITY and
## destroy all have commands behind them (`src/sim/commands/`). **Repair is the last one
## that does not**, and it is the only `enabled = false` placeholder left in this file --
## see `HudAction`'s header for why a greyed slot beats an omitted one.
##
## Formations were placeholders here from 4.3 until 2026-08-29 and are now live
## (`Formation`); stance and ability arrived with them (4.12, 4.10). `SimUnit.Task` still
## declares FLEE with no verb, and correctly so -- fleeing is something `WildlifeSystem`
## does TO an animal, not something a player orders. STAND_GROUND is no longer a task at
## all: it turned out to be a stance, which is what this file's old note was really
## observing when it listed it as a task with no verb.
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

## Icon filenames in `res://assets/ui/icons/`, keyed by whatever names the action --
## a verb, a technology id, an `UnitDef.ability_id`.
##
## THE FIVE STAND-INS ARE GONE (asset_request.md [P8], 2026-08-30). Harvest drew
## `res_wood.png`, a picture of wood rather than a gather verb; Repair and Stance
## SHARED `act_guard.png`, a shield standing in for a hammer; Upgrade and Research
## shared `hud_techtree.png`, the HUD button standing in for two different verbs. Each
## has its own drawing now, and no two entries below point at one file. That is worth
## saying explicitly, because five of the twelve entries this list used to have were
## deliberate compromises and the next reader would otherwise have to work out which.
##
## A GATE STILL SHARES THE ENTER/EXIT PAIR, and that one is not a compromise: a gate
## opening and a soldier walking out through a door are the same picture of the same
## idea, which is the question PLAN.md 13.2 item 4b asks and this is the answer.
##
## THE TWO PAGE ARROWS STILL HAVE NO ENTRY, deliberately, and `arrow_left`/`arrow_right`
## in `chrome/` are not them. "<" and ">" read as navigation at 72 px in a way a gold
## triangle in the same style as every other tile does not -- it would read as a verb.
## The chrome arrows are for scrollbars and dropdowns.
const ICONS := {
	&"move": "act_move.png",
	&"stop": "act_stop.png",
	&"attack": "act_attack.png",
	&"build": "act_build.png",
	&"harvest": "act_harvest.png",
	&"repair": "act_repair.png",
	&"stance": "act_stance.png",
	&"upgrade": "act_upgrade.png",
	&"research": "act_research.png",
	&"destroy": "act_destroy.png",
	&"garrison": "act_garrison.png",
	&"enter": "act_enter.png",
	&"exit": "act_exit.png",

	# ── the two abilities, keyed by `UnitDef.ability_id` ─────────────────────
	# Not by unit: `_unit_actions` asks `ICONS.get(ud.ability_id, "")`, so a second
	# unit given the monk's heal draws the monk's icon for free.
	&"heal": "abil_heal.png",
	&"fire_breath": "abil_fire_breath.png",

	# ── the four formations, keyed by `Formation.SHAPES` ─────────────────────
	# These are literal dot diagrams of the shape, which is the one case where the
	# glyph beats the word outright -- a picture of four dots in a row IS "line".
	&"line": "form_line.png",
	&"grid": "form_grid.png",
	&"vee": "form_vee.png",
	&"box": "form_box.png",

	# ── the 27 technologies, keyed by `techs.json`'s own ids ─────────────────
	# `_research_details` has asked `ICONS.get(t.id, "")` since 9.3 and got "" every
	# time; this is the data it was waiting for and there is no code in it.
	#
	# THE BLACKSMITH'S TWELVE ARE FOUR LADDERS OF THREE and are drawn as such -- one
	# motif per line (sword, arrow, mail, padding) with the tier in the drawing --
	# because at age 4 all twelve are on screen at once in a 4x3 grid, one line per
	# column, and a player has to tell the LINE apart at a glance and the tier second.
	&"tech.wheelbarrow": "tech_wheelbarrow.png",
	&"tech.hand_cart": "tech_hand_cart.png",
	&"tech.horse_collar": "tech_horse_collar.png",
	&"tech.heavy_plough": "tech_heavy_plough.png",
	&"tech.crop_rotation": "tech_crop_rotation.png",
	&"tech.double_bit_axe": "tech_double_bit_axe.png",
	&"tech.bow_saw": "tech_bow_saw.png",
	&"tech.gold_mining": "tech_gold_mining.png",
	&"tech.stone_mining": "tech_stone_mining.png",
	&"tech.gold_shaft_mining": "tech_gold_shaft_mining.png",
	&"tech.stone_shaft_mining": "tech_stone_shaft_mining.png",
	&"tech.forging": "tech_forging.png",
	&"tech.iron_casting": "tech_iron_casting.png",
	&"tech.blast_furnace": "tech_blast_furnace.png",
	&"tech.fletching": "tech_fletching.png",
	&"tech.bodkin_arrow": "tech_bodkin_arrow.png",
	&"tech.bracer": "tech_bracer.png",
	&"tech.scale_mail": "tech_scale_mail.png",
	&"tech.chain_mail": "tech_chain_mail.png",
	&"tech.plate_mail": "tech_plate_mail.png",
	&"tech.padded_armour": "tech_padded_armour.png",
	&"tech.leather_armour": "tech_leather_armour.png",
	&"tech.ring_armour": "tech_ring_armour.png",
	&"tech.ballistics": "tech_ballistics.png",
	&"tech.chemistry": "tech_chemistry.png",
	&"tech.sanctity": "tech_sanctity.png",
	&"tech.fervour": "tech_fervour.png",
}

## The fallback a technology with no icon of its own draws (`tech_generic.png`, a
## scroll). Every one of the 27 is named above, so nothing reaches this today -- it is
## here so that the 28th is a tile with a scroll on it rather than a tile with a
## paragraph of wrapped text, which is what an unmapped tech drew before [P8].
##
## `TechMods.validate()` would not catch a missing icon and should not: an icon is not
## an effect, and a tech that draws the generic scroll works perfectly.
const TECH_FALLBACK_ICON := "tech_generic.png"

## One per `SimUnit.Stance`, keyed by the enum value the wire carries.
##
## A SEPARATE MAP RATHER THAN ENTRIES IN `ICONS`, because a stance is keyed by an INT
## and everything in `ICONS` is keyed by a StringName. Mixing the two would make
## `ICONS.get(x, "")` a lookup whose key type depends on the caller.
const STANCE_ICONS := {
	SimUnit.Stance.AGGRESSIVE: "stance_aggressive.png",
	SimUnit.Stance.DEFENSIVE: "stance_defensive.png",
	SimUnit.Stance.STAND_GROUND: "stance_stand_ground.png",
	SimUnit.Stance.PASSIVE: "stance_passive.png",
}

## The two page-navigation slots. They are real HudActions in the grid rather
## than chrome around it, because the grid IS the 12 slots -- an arrow drawn
## outside it would need layout the panel does not have, and one drawn over a
## slot would cover a building.
const PAGE_PREV := &"page:prev"
const PAGE_NEXT := &"page:next"

## Formation choices a military unit's Move action expands into (UI_Design.md). LIVE
## since 2026-08-29 -- `Formation` is what turns one of these into a destination per unit,
## and this list is deliberately its `SHAPES` rather than a second copy, so the menu and
## the sim cannot come to disagree about which four exist.
const FORMATIONS: Array[StringName] = Formation.SHAPES

## The four stances, in the order `SimUnit.Stance` declares them (PLAN.md 4.12). Taken
## from the enum rather than written out, for the reason above: the value goes on the
## wire as an int and the panel must not be the place that decides what 2 means.
##
## The labels are the player-facing words and are NOT derived from the enum names --
## "Stand Ground" carries a space, and `String(&"STAND_GROUND").capitalize()` gives
## "Stand ground", which is a different verb in the genre than the one meant.
const STANCE_LABELS := {
	SimUnit.Stance.AGGRESSIVE: "Aggressive",
	SimUnit.Stance.DEFENSIVE: "Defensive",
	SimUnit.Stance.STAND_GROUND: "Stand Ground",
	SimUnit.Stance.PASSIVE: "Passive",
}


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
## `researched` is the selection owner's technology set -- `tech id -> true`, off
## `player_state["researched"]` by way of `GameView.researched_of`. APPENDED rather
## than slotted in beside `age`, so every existing caller and test keeps working by
## passing nothing; an empty set is what a player who has researched nothing has, and
## it is the right answer for a caller that has no snapshot yet.
static func for_selection(facts: Dictionary, selected_count: int = 1,
		is_mine: bool = true, all_def_ids: Array = [], age: int = 1,
		researched: Dictionary = {}) -> Array[HudAction]:
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
		#
		# MOVE EXPANDS HERE AND FORMATIONS ARE WHY (4.14). On a single unit it expands
		# only for a military one, because a lone soldier in a "line" is a soldier; a
		# GROUP is the case formations exist for, and it is the case a player reaches
		# for them in. `Formation.destinations` returns the anchor tile for a
		# single-unit order whatever shape was asked, so the two agree.
		var group_move := _act(&"move")
		group_move.expands = true
		# STANCE ON THE WHOLE SELECTION, which is how it is set in practice -- nobody
		# sets a stance one soldier at a time. `SetStanceCommand` carries many ids for
		# exactly this, and members that cannot fight simply ignore it, the same way a
		# trade cart in the group ignores Attack above.
		#
		# The badge and the ring read the PRIMARY's stance, which is the same
		# simplification every other fact in this branch makes -- `facts` is one
		# entity's. A mixed-stance group shows the primary's until the next press makes
		# them agree, and the press is what a player is opening the menu to do.
		var group_stance := _act(&"stance")
		group_stance.expands = true
		group_stance.badge = _stance_badge(int(facts.get("stance", SimUnit.Stance.PASSIVE)))
		return _capped([
			group_move, _act(&"stop"), _act(&"attack"), group_stance, _act(&"destroy"),
		])

	if GameDataRegistry.building(def_id) != null:
		return _capped(_building_actions(def_id, age, facts, researched))
	return _capped(_unit_actions(def_id, facts))


## What tapping an `expands` action fills the detail grid with; `[]` for an
## action that just issues its order.
##
## Called with `action_id = &""` for "nothing expanded", which is when the grid
## shows the selection's own default detail -- a building's production queue,
## or a group's roster.
##
## `active_formation` is the client's current formation choice and is APPENDED rather
## than slotted in beside `facts`, so every existing caller and test keeps working by
## passing nothing. It is the only argument here that is not server truth, and it is the
## only one that could not be: 4.14 keeps the formation on the ORDER, so there is nothing
## about it in the snapshot to read.
static func details_for(action_id: StringName, facts: Dictionary,
		selected_count: int = 1, all_def_ids: Array = [], age: int = 1,
		active_formation: StringName = &"",
		researched: Dictionary = {}) -> Array[HudAction]:
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
	# THE THIRD LIST THAT CAN OUTGROW THE GRID, and the reason it is uncapped: the
	# blacksmith offers twelve technologies at age 4, which is exactly MAX_DETAILS --
	# so the day a thirteenth is added anywhere, a capped list would drop it silently
	# and `page_of` already knows what to do instead.
	if action_id == &"research":
		return _research_details(facts, age, researched)
	if action_id == &"move":
		return _capped_details(_formation_details(active_formation))
	if action_id == &"stance":
		return _capped_details(_stance_details(facts))

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
		facts: Dictionary = {}, researched: Dictionary = {}) -> Array[HudAction]:
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

	# WHAT THIS BUILDING TEACHES (PLAN.md 9.3), and it is ONE slot rather than one per
	# technology -- the blacksmith offers twelve and the action column has eight in
	# total. `expands`, so the row itself only says "there is research here" and the
	# choosing happens in the detail grid, exactly as Build and Garrison do.
	#
	# OFFERED ONLY BY A BUILDING THAT ACTUALLY HAS TECHS, which is seven of the
	# thirty-one, so the other twenty-four rows are unchanged and none of them is
	# pushed past `_capped`'s slice. That mattered: the castle already emits nine with
	# a rally point set, and it has no techs precisely so it still emits nine.
	var research := _research_action(bd, age, facts, researched)
	if research != null:
		out.append(research)

	# STOP CLEARS THE RALLY POINT (project owner, 2026-08-27: *"resuse stop action
	# button to clear waypoint with building selected"*), and it is offered ONLY when
	# there is one to clear — like the gate button, which appears only for a gate.
	#
	# The disabled-placeholder convention does not apply: that is for verbs the game
	# has not implemented yet, shown greyed so the panel reads finished. This verb is
	# implemented and simply has nothing to act on, which is the gate's situation and
	# not Repair's.
	#
	# It is also what keeps the castle inside its slots. With a rally point set the
	# castle asks for nine of `MAX_ACTIONS`' eight, and the ORDER BELOW is what
	# decides which one falls off — see the note on Repair.
	if _has_rally_point(facts):
		out.append(_act(&"stop"))

	out.append(_act(&"destroy"))
	# REPAIR IS LAST, AND IT MOVED HERE ON PURPOSE. `_capped` slices at MAX_ACTIONS,
	# so whatever sits ninth is dropped silently — and a castle with a rally point set
	# is exactly nine. Repair has been a disabled placeholder since 4.3 and does
	# nothing when pressed; Destroy is a real command. Given one of the two has to go,
	# it must be the placeholder, and the only way to say so is to put it last.
	#
	# This is the trap AGENT_GAME_CODER.md warns about, arriving on schedule: the
	# castle emitted exactly 8 before today, so the very next verb added to a building
	# was always going to cost something.
	out.append(_act(&"repair", false))
	return out


## Whether these facts describe a building with a rally point set.
##
## Read defensively rather than as a typed assignment, because `facts` is a plain
## Dictionary off the wire: a building that predates the field, a remembered enemy
## entry (which has it stripped), and a unit or resource node all arrive here with no
## `waypoint` at all, and any of them typed-assigned to a Vector2i is a hard error
## rather than a false.
static func _has_rally_point(facts: Dictionary) -> bool:
	var raw = facts.get("waypoint", null)
	return raw is Vector2i and raw != SimBuilding.NO_WAYPOINT


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
	# NO ICON, deliberately, where the disabled placeholder above keeps one -- and this
	# is STILL right now that `&"upgrade"` has real art rather than the tech-tree glyph
	# it used to borrow. `ActionSlot` prefers an icon file over the payload portrait, so
	# passing one would draw a chevron over a perfectly good picture of the gate you are
	# about to get. Left blank, the slot crops the gate's own sprite exactly as the
	# train and place cells do, and the tile says WHICH gate rather than "upgrade".
	var a := HudAction.new(&"upgrade",
			to.name if not to.name.is_empty() else String(to.id), "", true)
	a.payload = to.id
	return a


## The Research slot for a building that offers technologies, or `null` for one that
## does not (PLAN.md 9.3).
##
## `null` RATHER THAN A DISABLED PLACEHOLDER, which is the opposite of what Repair
## does two lines below it and is the same call the Gate and Garrison buttons make: a
## disabled slot means "this verb exists and you cannot use it right now", and a house
## does not have research in the way a house does have repair. Twenty-four of the
## thirty-one buildings return null here and their rows are byte-identical to before.
##
## ONLY WHEN COMPLETE, like the gate and the garrison. `ResearchCommand.validate`
## refuses a foundation, and a button that does nothing is worse than no button.
##
## The badge counts what is BOUGHT against what is offered AT THIS AGE, so it reads
## 0/4 at the blacksmith in age 2 and 8/12 in age 4 -- which says both "there is more
## here" and "you have been here before" without the row being opened.
static func _research_action(bd: BuildingDef, age: int, facts: Dictionary,
		researched: Dictionary) -> HudAction:
	if int(facts.get("phase", -1)) != SimBuilding.Phase.COMPLETE:
		return null
	var offered := _techs_here(bd.id, age)
	if offered.is_empty():
		return null

	var done := 0
	for t in offered:
		if bool(researched.get(t.id, false)):
			done += 1

	# ITS OWN ICON SINCE [P8]. This asked for `&"upgrade"`'s until 2026-08-30, because
	# the two verbs shared `hud_techtree.png` and asking for the other one made that
	# visible; they are two drawings now and each asks for its own.
	var a := HudAction.new(&"research", "Research", ICONS.get(&"research", ""), true)
	a.expands = true
	a.badge = "%d/%d" % [done, offered.size()]
	return a


## The technologies this building offers that the owner's age has reached, in the
## registry's menu order (age, then display name).
##
## ABOVE-AGE TECHS ARE OMITTED, not shown disabled -- the same rule `_building_actions`
## applies to the train row and `_buildable_details` to the build list, and for the
## same reason recorded there: a greyed Blast Furnace in age 2 is a promise about a
## future age, and the tech tree (9.4) is where promises about future ages belong.
static func _techs_here(building_id: StringName, age: int) -> Array[TechDef]:
	var out: Array[TechDef] = []
	for id in GameDataRegistry.techs_at(building_id):
		var t: TechDef = GameDataRegistry.tech(id)
		if t != null and t.age_required <= age:
			out.append(t)
	return out


## One slot per technology, in three states (PLAN.md 9.3).
##
##   RESEARCHED  ringed and not pressable. `HudAction.selected` is the third state
##               `enabled` could not express, and a bought tech is exactly what it was
##               added for at 4.12 -- there is nothing to press and it is not "not
##               built either".
##   IN THE QUEUE  disabled with a "..." badge. Read off `facts["queue"]`, which is
##               server truth, so a research another client started shows here too.
##   AVAILABLE   pressable, priced along the top of the tile like a train slot.
##
## A TECH WHOSE PREREQUISITE IS MISSING IS SHOWN, DISABLED, and that is deliberately
## different from the age rule above. "Research Forging first" is something the player
## can act on now, in this menu, on this building; "come back in an age" is not.
## `requirement` names what it needs, since a greyed tile with no reason on it reads as
## broken.
##
## ICONS AND CAPTIONS BOTH, since [P8] landed the 27 (2026-08-30). This drew labels
## alone from 9.3 until then, on the owner's instruction (*"we can use blank action
## tiles with only lables filled and log art needed"*), and the prediction that made
## was right: the wiring turned out to be 27 lines of data in `ICONS` and none of code
## here, because this line already asked.
##
## CAPTIONED, unlike a verb tile. A technology is a member of a set of near-identical
## pictures in the strongest sense the game has -- the blacksmith's twelve are four
## ladders of three, drawn as four motifs with the tier in the drawing, so two tiles a
## column apart differ by a detail. The player is spending 200 gold on the difference.
static func _research_details(facts: Dictionary, age: int,
		researched: Dictionary) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var queued: Array = facts.get("queue", [])

	for t in _techs_here(facts.get("def_id", &""), age):
		var a := HudAction.new(&"research:%s" % t.id,
				t.name if not t.name.is_empty() else String(t.id),
				ICONS.get(t.id, TECH_FALLBACK_ICON))
		a.captioned = true
		if bool(researched.get(t.id, false)):
			a.selected = true
			a.enabled = false
		elif queued.has(String(t.id)):
			a.enabled = false
			a.badge = "..."
		else:
			var missing := _missing_prerequisite(t, researched)
			if missing.is_empty():
				a.cost = t.cost
			else:
				a.enabled = false
				# THE TOP STRIP, NOT THE BADGE. It was the badge until 2026-08-30 and
				# that was fine while a research tile was a bare centred label; the
				# moment [P8] gave every tech an icon and a caption, the caption and
				# the badge shared the bottom edge and the blacksmith's locked ladder
				# printed two names over each other. See `HudAction.requirement`.
				a.requirement = missing
		out.append(a)
	return out


## The display name of the first prerequisite this player has not bought, or "" when
## the tech is ready to research. First rather than all: the badge is corner text on a
## 72 px tile, and every tech in the roster has at most one.
static func _missing_prerequisite(t: TechDef, researched: Dictionary) -> String:
	for id in t.requires:
		if bool(researched.get(id, false)):
			continue
		var req: TechDef = GameDataRegistry.tech(id)
		return req.name if req != null and not req.name.is_empty() else String(id)
	return ""


## A unit's own verbs. Harvest and Build are gated on the def actually being a
## gatherer -- MVP's only unit is the villager, so this is the closest thing to
## a "is a worker" flag until one exists; a soldier def with no `gather_rate`
## correctly gets neither.
static func _unit_actions(def_id: StringName, facts: Dictionary = {}) -> Array[HudAction]:
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

	# WHAT IT DOES WHEN NOBODY IS WATCHING (PLAN.md 4.12). Offered to anything that can
	# actually fight, which is the same `attack_damage > 0` test the Attack verb above
	# uses -- so the villager gets one (she carries damage 3 and hiding indoors is not
	# always an option) and the monk, the trade cart and the transport do not. A stance
	# on a unit that cannot land a blow would be a control that changes nothing:
	# `StanceSystem` refuses to acquire for them, deliberately and for `CombatSystem`'s
	# reason -- the order would be retired on the tick it was given.
	if ud.attack_damage > 0:
		var st := _act(&"stance")
		st.expands = true                # offers the four, with the live one ringed
		# The badge is the current stance in one word, so the row says which it is
		# without being opened. "Stand Ground" is abbreviated because the badge is
		# corner text on a 72 px tile and the full label does not fit.
		st.badge = _stance_badge(int(facts.get("stance", SimUnit.Stance.PASSIVE)))
		out.append(st)

	# ITS ONE SPECIAL ABILITY (PLAN.md 4.10) -- the monk's heal, the dragon's breath, and
	# nothing else in the roster. Labelled with the ability's OWN name rather than
	# "Ability", for the reason a train button says "Archer": the player is being asked
	# to spend a cooldown and needs to know on what.
	#
	# DISABLED WHILE COOLING, which is IDEA.md 4.10's own wording ("greyed out and
	# unclickable"). `ability_cooldown` is only on the wire while it is running, so
	# absence reads as ready -- and `AbilityCommand.validate` refuses it again anyway,
	# because a greyed slot is a courtesy and the server is the trust boundary.
	if ud.has_ability():
		var cooling := int(facts.get("ability_cooldown", 0))
		var ab := HudAction.new(&"ability",
				ud.ability_name if not ud.ability_name.is_empty() else "Ability",
				ICONS.get(ud.ability_id, ""), cooling <= 0)
		# Seconds rather than ticks: ticks are a sim unit and 150 of them means nothing
		# to a player. SimClock runs at 10 a second, and it rounds UP so a cooldown with
		# any time left never reads "0".
		if cooling > 0:
			ab.badge = "%ds" % ((cooling + 9) / 10)
		out.append(ab)

	# WHO IS ABOARD, AND A WAY OFF (2.4d) -- the transport ship and nothing else, since
	# `garrison_cap` is 0 on every other unit. **The same block as `_building_actions`'s,
	# deliberately not shared**: it is six lines, and factoring it out would need a
	# parameter for the phase test that only one caller has. What matters is that it
	# emits the identical `&"garrison"` action, so `details_for` lists the occupants and
	# `SelectionPanel` ejects them through the code path a castle already uses.
	if ud.garrison_cap > 0:
		var aboard := int(facts.get("garrison_count", 0))
		var g := HudAction.new(&"garrison", "Unload", ICONS.get(&"garrison", ""), aboard > 0)
		g.badge = "%d/%d" % [aboard, ud.garrison_cap]
		g.expands = true
		out.append(g)

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


## Formation choices for a military unit's Move (UI_Design.md, PLAN.md 4.14). LIVE since
## 2026-08-29; this was four disabled placeholders from 4.3 until then.
##
## THIS FILE SAID THEY WOULD NEVER HAVE ICONS and it was wrong about what the icon would
## be. The argument was that a formation is a SHAPE and "Vee" says what a wedge is more
## directly than a glyph of one would -- which assumed a glyph, an object standing for
## the idea. [P8] drew the shape ITSELF: four gold dots in a row, nine in a square, a
## wedge, a hollow box. A picture of four dots in a row is not a symbol for "line", it
## is a line, and it survives 52 px in a way no object would.
##
## CAPTIONED ANYWAY, so the word is still there. The four diagrams are unambiguous
## against each other and the caption costs the bottom strip of a tile that has no
## portrait under it.
##
## `active` is the client's own current choice, not a fact off the wire. A formation is a
## property of the ORDER (`MoveCommand.formation`) and nothing stores it on a unit, so
## there is nowhere in the snapshot for this to come from -- `GameScene` holds it exactly
## as it holds the selection. Empty means "no formation", which is a real state and the
## default: it is what a move order has always done.
##
## THE ACTIVE ONE STAYS PRESSABLE and is ringed rather than greyed. Pressing it again is
## how a player turns the formation OFF, which is the only way back to a plain move order
## once one has been chosen.
static func _formation_details(active: StringName = &"") -> Array[HudAction]:
	var out: Array[HudAction] = []
	for f in FORMATIONS:
		var a := HudAction.new(&"formation:%s" % f, String(f).capitalize(),
				ICONS.get(f, ""), true)
		a.captioned = true
		a.selected = (f == active)
		out.append(a)
	return out


## The four stances, with the one this unit is currently on ringed (PLAN.md 4.12).
##
## Read off `facts["stance"]`, which is SERVER truth -- `SimUnit` sends it on every unit
## every tick. So the ring says what the unit is actually doing rather than what was last
## pressed, and a stance set by another client, or refused by `validate`, shows correctly
## on the next snapshot without the panel tracking anything.
##
## THE CURRENT ONE IS NOT DISABLED, and that is deliberate: `enabled = false` already
## means "not built" and "nothing to act on", both of which draw greyed, and a stance the
## unit is already on is neither. `HudAction.selected` is the third state, and its header
## records why it had to be one.
##
## Ordered by the enum, so the four never move under a player's thumb -- the same reason
## `_buildable_details` re-sorts rather than taking `building_ids()` order.
static func _stance_details(facts: Dictionary) -> Array[HudAction]:
	var current := int(facts.get("stance", SimUnit.Stance.PASSIVE))
	var out: Array[HudAction] = []
	for value in [SimUnit.Stance.AGGRESSIVE, SimUnit.Stance.DEFENSIVE,
			SimUnit.Stance.STAND_GROUND, SimUnit.Stance.PASSIVE]:
		var a := HudAction.new(&"stance:%d" % value, STANCE_LABELS[value],
				STANCE_ICONS.get(value, ""), true)
		# CAPTIONED, AND HERE IT IS LOAD BEARING rather than a courtesy. The four are a
		# flaming sword, a sword-and-shield, a planted spear and a plain shield -- two
		# shields and two blades, at 52 px. The glyph says "this row is about how the
		# unit fights"; only the word says which of the four it is.
		a.captioned = true
		a.selected = (value == current)
		out.append(a)
	return out


## One word for the action row's badge. "Hold" rather than "Stand Ground" because the
## badge is corner text on a 72 px tile; the full wording is on the detail slot, which is
## where the player is choosing rather than checking.
static func _stance_badge(stance: int) -> String:
	match stance:
		SimUnit.Stance.AGGRESSIVE:
			return "Aggr"
		SimUnit.Stance.DEFENSIVE:
			return "Def"
		SimUnit.Stance.STAND_GROUND:
			return "Hold"
	return "Pass"


## A building's production queue, one slot per entry (5.4). Tapping one cancels it,
## which `CancelProductionCommand` already supports -- for a research as much as for a
## unit, since it refunds the entry's own recorded `cost` and never asks what kind it
## was.
##
## A RESEARCH IN THE QUEUE IS A UNIT ID THAT RESOLVES TO NOTHING, and it used to draw
## as the word "Queued" (5.4's own note records that failure with the def ids that
## fixed it). `payload` stays EMPTY for a technology and always will: `ActionSlot` crops
## the payload's portrait from a baked sprite, and a tech has none.
##
## IT TAKES ITS OWN ICON INSTEAD, since 2026-08-30 (project owner: *"upgrades queue items
## does not show their tiles"*). A queued unit has drawn its cropped portrait since 5.4,
## so a queued technology beside it -- a bare centred word with a percentage under it --
## read as a tile that had failed to load rather than as the other kind of entry. The 27
## icons landed with [P8] and `ICONS` is keyed by `techs.json`'s own ids, so this is the
## SAME picture the Research grid and the tech tree draw for it; a player who has just
## bought Wheelbarrow off one grid finds the same tile in the queue.
##
## CAPTIONED, for `_research_details`' reason and one more of its own. The blacksmith's
## twelve are four ladders of three drawn as one motif per line, so the icon alone says
## which LINE is queued and not which tier -- and the entry is pressable, cancelling and
## refunding what it names.
static func _queue_details(facts: Dictionary) -> Array[HudAction]:
	var out: Array[HudAction] = []
	var queue: Array = facts.get("queue", [])
	var queue_len := int(facts.get("queue_len", queue.size()))

	for i in range(queue_len):
		var def_id: StringName = queue[i] if i < queue.size() else &""
		var ud: UnitDef = GameDataRegistry.unit(def_id)
		var td: TechDef = GameDataRegistry.tech(def_id)
		var label := "Queued"
		if ud != null and not ud.name.is_empty():
			label = ud.name
		elif td != null and not td.name.is_empty():
			label = td.name
		var a := HudAction.new(&"cancel:%d" % i, label)
		if ud != null:
			a.payload = def_id
		elif td != null:
			a.icon = ICONS.get(td.id, TECH_FALLBACK_ICON)
			a.captioned = true
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
##
## `member:<n>` NAMES A POSITION IN THIS LIST, and pressing one narrows the selection to
## that entity alone (`GameScene._select_roster_member`, live since 2026-08-30). An index
## rather than an entity id because this function is not given one -- `all_def_ids` is
## what it takes, and it is the caller that holds the ids in the same order. That is the
## same shape `_garrison_details` uses, for a different reason: a garrisoned unit HAS no
## id on the wire, whereas this one has an id the caller can look up.
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
