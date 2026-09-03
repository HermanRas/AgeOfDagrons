## Turn one standing building into one of the things its def says it upgrades to, where
## it stands (PLAN.md 5.8, 5.3). Every upgrade in the game is a wall: a long segment
## becoming its tier's gate, and since 5.3 any piece becoming the same piece one tier up
## -- wood to stone to reinforced, length for length.
##
## THIS IS HOW A GATE IS PLACED AT ALL, and it replaced tap-placement rather than
## joining it. A gate is 9x2 and `PlaceBuildingCommand` carries no facing and never
## transposes a footprint, so a tap-placed gate could only ever lie east-west -- which
## meant a north-south wall could not have a gate in it, and there was no rotate
## control to fix it with. Reported by the project owner on 2026-08-22, playing.
##
## Upgrading a segment sidesteps the whole question instead of answering it: the wall
## already knows which axis it was dragged along, and the gate inherits its footprint,
## its origin and its facing. There is nothing left to rotate. All three gates are now
## `buildable: false`, so this is the only way to get one.
##
## INSTANT, with no foundation and no builder. An upgrade is not a construction -- the
## wall is already there and already paid for -- and making it a build job would mean
## a gate-shaped hole in the player's own wall for the length of the build, which is
## strictly worse than what they had before they asked.
##
## ⚠️ **5.3 ASKED FOR A BUILD TIME AND THE SUBJECT THAT WANTED ONE NO LONGER EXISTS.**
## The card's reasoning was about a non-wall upgrade -- the watch tower becoming a guard
## tower -- and that pair is ruled out for good on the footprint rule (owner,
## 2026-09-03). Every upgrade that remains is a wall, and a wall is exactly the case
## where the argument above applies: a timed tier upgrade would open your own defences
## for the length of it. The day something that is not a wall upgrades, the queue 9.3
## taught to hold a research is where its timer goes; until then a timer would be a
## mechanism with nothing to time.
##
## THE PRICE IS THE DIFFERENCE (`cost_delta`). A player who has paid 36 wood for a wall
## pays 14 more for the 50-wood gate, not 50 again.
##
## ⚠️ **AND THE CREDIT CROSSES RESOURCE KINDS SINCE 5.3** (owner, 2026-09-03: *"lets
## credit the wood onto stone"*). Same-kind credit alone was right while every upgrade
## in the game was wood-for-wood; a wood wall becoming a STONE one shares no resource
## with what it came from, so the whole 36 wood would have counted for nothing and the
## upgrade would have cost exactly what building a stone wall costs. That is a price
## that says "there is no such thing as an upgrade, only a rebuild you did not have to
## aim".
##
## **1:1, AND THAT RATE IS READ OFF THE GAME RATHER THAN CHOSEN.** `market.json` prices
## food, wood and stone identically against gold (130 buy / 70 sell, all three), so the
## only exchange rate this game has ever declared between wood and stone is one for one.
## Any other number here would be inventing a valuation nothing else in the game agrees
## with -- and routing it through the market's own spread would make an upgrade cost
## depend on owning a market, and lose 60% on the way through.
class_name UpgradeBuildingCommand
extends Command

var building_id: int = 0

## WHICH of `upgrades_to` this command means. Empty is legal and means the FIRST one,
## which is what every command written before 5.3 meant -- a long wall's gate.
##
## ON THE WIRE, because one building now offers two futures and the server cannot guess
## which tile the player pressed. Same shape as `TrainUnitCommand` carrying a def id
## rather than "whatever this building trains".
var target_def_id: StringName = &""


func _init(p_player_id: int = 0, p_building_id: int = 0, p_target_def_id: StringName = &"",
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	target_def_id = p_target_def_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "upgrade_building"
	d["building_id"] = building_id
	d["target_def_id"] = String(target_def_id)
	return d


static func from_dict(d: Dictionary) -> UpgradeBuildingCommand:
	var c := UpgradeBuildingCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	# JSON has no StringName, so everything off the wire is a String.
	c.target_def_id = StringName(str(d.get("target_def_id", "")))
	return c


## Which target this command actually names, or `&""` if it names one `from` does not
## offer. THE LIST IS THE AUTHORITY: a command may not name a def that is not in it, or
## a client could upgrade a palisade straight into a castle by sending the id.
##
## An EMPTY name resolves to the first entry rather than being refused, because that is
## exactly what the command meant for the whole of 5.8 -- and the order is load bearing
## for that reason (`BuildingDef.upgrades_to`).
static func resolve_target(from: BuildingDef, wanted: StringName) -> StringName:
	if from == null or from.upgrades_to.is_empty():
		return &""
	if wanted.is_empty():
		return from.upgrades_to[0]
	return wanted if from.upgrades_to.has(wanted) else &""


## What upgrading `from` into `to` costs on top of what has already been paid.
## Static and public because the HUD prices the button with it and this command
## charges with it -- two implementations of "what does this cost" would disagree the
## first time either changed, and the one that disagrees visibly is the button.
##
## TWO PASSES, and the order matters. Same-kind first, so a stone wall becoming a
## reinforced one is 75 - 45 = 30 stone and nothing exotic happens to the commonest
## case. Then whatever was invested that the target does not want at all becomes a
## CREDIT, spent 1:1 against what is still owed -- 36 wood against a 45-stone wall
## leaves 9 stone to pay.
##
## ⚠️ **THE CREDIT IS SPENT IN A DECLARED ORDER AND NOT IN DICTIONARY ORDER.** It only
## bites when the credit cannot cover everything still owed across two or more kinds,
## which no shipped pair reaches -- and an order that came from however the JSON parser
## happened to fill a Dictionary is exactly the kind of thing that is stable until it
## is not. `Array[StringName].sort()` orders by IDENTITY rather than by content (§6),
## so the sort is over Strings.
static func cost_delta(from: BuildingDef, to: BuildingDef) -> Dictionary:
	var out: Dictionary = {}
	if to == null:
		return out

	var credit := 0
	if from != null:
		for kind in from.cost:
			# EVERYTHING PAID THAT THIS TARGET DOES NOT ASK FOR, which is both the kinds it
			# wants none of AND the surplus of a kind it wants less of. The palisade gate is
			# the case that needs the second half: 50 wood becoming a stone gate that wants
			# 30 wood and 45 stone leaves 20 wood over, and dropping it on the floor would
			# charge the full 45 stone while the player watches a 50-wood gate be consumed.
			credit += maxi(0, int(from.cost[kind]) - int(to.cost.get(kind, 0)))

	var owed_order: Array[String] = []
	for kind in to.cost:
		var extra := int(to.cost[kind]) - int(from.cost.get(kind, 0) if from != null else 0)
		if extra > 0:
			out[kind] = extra
			owed_order.append(String(kind))
	owed_order.sort()

	for name in owed_order:
		if credit <= 0:
			break
		var kind := StringName(name)
		var paid := mini(credit, int(out[kind]))
		credit -= paid
		if paid >= int(out[kind]):
			out.erase(kind)
		else:
			out[kind] = int(out[kind]) - paid
	return out


func validate(w: SimWorld) -> bool:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null or not b.alive or b.owner_id != player_id:
		return false
	# COMPLETE ONLY. A foundation has not been paid for in full yet and has no art of
	# its own tier to swap, and upgrading one would let a player skip most of a wall's
	# build time by ordering the cheap thing and immediately improving it.
	if not b.is_complete():
		return false

	var from: BuildingDef = w.building_def(b.def_id)
	var target := resolve_target(from, target_def_id)
	if target.is_empty():
		return false
	var to: BuildingDef = w.building_def(target)
	if to == null:
		return false
	# THE FOOTPRINT MUST MATCH. `SimWorld.convert_building` keeps the ground the
	# building already holds, so a target that wanted more of it would silently occupy
	# tiles nobody checked were free. Enforced here rather than trusted, because it is
	# a relationship between two separate JSON entries and nothing else pins it.
	if to.footprint != from.footprint:
		return false

	var p := w.player_for(player_id)
	if p == null or p.defeated:
		return false
	# Age-gated on the TARGET, and enforced here as well as in the panel for the
	# reason every other command states: the menu is a client, the server is the only
	# trust boundary. A player in age 2 holding an age-2 wall cannot buy an age-3 gate.
	if to.age_required > p.age:
		return false
	return p.can_afford(cost_delta(from, to))


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null:
		return
	var from: BuildingDef = w.building_def(b.def_id)
	var target := resolve_target(from, target_def_id)
	if target.is_empty():
		return
	var to: BuildingDef = w.building_def(target)
	var p := w.player_for(player_id)
	if to == null or p == null:
		return
	if not p.pay(cost_delta(from, to)):
		return
	w.convert_building(b, target)
