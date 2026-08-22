## Turn one standing building into what its def says it upgrades to, where it stands
## (PLAN.md 5.8). Today that is exactly one thing: a finished long wall segment
## becoming its tier's gate.
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
## THE PRICE IS THE DIFFERENCE, per resource kind, floored at zero (`cost_delta`). A
## player who has paid 36 wood for a wall pays 14 more for the 50-wood gate, not 50
## again. Floored per kind rather than in total, so a target that is cheaper in one
## resource and dearer in another cannot hand back a refund in the cheap one.
class_name UpgradeBuildingCommand
extends Command

var building_id: int = 0


func _init(p_player_id: int = 0, p_building_id: int = 0, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "upgrade_building"
	d["building_id"] = building_id
	return d


static func from_dict(d: Dictionary) -> UpgradeBuildingCommand:
	var c := UpgradeBuildingCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	return c


## What upgrading `from` into `to` costs on top of what has already been paid.
## Static and public because the HUD prices the button with it and this command
## charges with it -- two implementations of "what does this cost" would disagree the
## first time either changed, and the one that disagrees visibly is the button.
static func cost_delta(from: BuildingDef, to: BuildingDef) -> Dictionary:
	var out: Dictionary = {}
	if to == null:
		return out
	for kind in to.cost:
		var extra := int(to.cost[kind]) - int(from.cost.get(kind, 0) if from != null else 0)
		if extra > 0:
			out[kind] = extra
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
	if from == null or from.upgrades_to == &"":
		return false
	var to: BuildingDef = w.building_def(from.upgrades_to)
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
	if from == null or from.upgrades_to == &"":
		return
	var to: BuildingDef = w.building_def(from.upgrades_to)
	var p := w.player_for(player_id)
	if to == null or p == null:
		return
	if not p.pay(cost_delta(from, to)):
		return
	w.convert_building(b, from.upgrades_to)
