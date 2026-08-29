## Order a set of units into one of the player's own buildings (PLAN.md 4.8).
##
## One command, many units, one destination -- the same shared-target shape as
## GatherCommand, BuildCommand and AttackCommand, so sending five archers into a
## tower is one message rather than five.
##
## THIS IS AN ORDER TO WALK, NOT AN ARRIVAL. Nothing enters a building here: the
## units are put on `Task.GARRISON` and given a route, and `GarrisonSystem` admits
## each one as it reaches the footprint -- exactly how BuildCommand hands a builder
## to BuildSystem. That split is what makes capacity honest across distance: five
## units ordered into a five-slot tower where one is already inside will see four go
## in and the fifth turn up to a full building, and the fifth is refused there rather
## than being promised a slot here.
##
## THE TARGET IS THE CALLER'S OWN, and only the caller's. Garrisoning into an ally's
## tower is a thing 0 A.D. allows and we do not, because there is no alliance in v1
## (PLAN.md 1: players are told apart by colour) and `Diplomacy` would have to grow a
## notion of "friendly but not mine" for a case nobody can reach.
class_name GarrisonCommand
extends Command

var unit_ids: Array[int] = []
var target_id: int = 0


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_target_id: int = 0,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	target_id = p_target_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "garrison"
	d["unit_ids"] = unit_ids
	d["target_id"] = target_id
	return d


static func from_dict(d: Dictionary) -> GarrisonCommand:
	var c := GarrisonCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	c.target_id = int(d.get("target_id", 0))
	return c


## Refuses: an empty order, a target that is not the caller's own living COMPLETE
## building, one that holds nobody by declaration (`garrison_cap` 0 -- every wall,
## every house, the town centre), and any named unit that is not the caller's own
## living, un-garrisoned SimUnit.
##
## FULLNESS IS NOT CHECKED HERE, deliberately, and it is the one refusal a reader
## expects to find. A tower with one free slot and three units walking to it is the
## ordinary case, and the slot may be taken by any of them; refusing the whole order
## at issue time would mean a player with a nearly-full tower could not send anybody.
## `SimWorld.garrison_unit` is the gate, on arrival, where the answer is current.
##
## Every named unit must qualify rather than being filtered, which is the opposite of
## AttackCommand's rule and follows the same reasoning to a different answer: there
## the filter exists because a mixed selection may contain a trade cart that cannot
## fight, and dropping it is better than refusing the order. Here EVERY unit can
## garrison -- there is no unit-side capability to fail -- so a bad id in the list is
## a client bug or a stale selection, not a mixed group.
func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false

	# A CARRIER, WHICH SINCE 2026-08-29 MAY BE A SHIP (2.4d). `has_garrison_room()` is
	# the one test, and it is the entity's own: a building adds "and it is finished", a
	# unit adds "and it is not itself inside something", and a `garrison_cap` of 0
	# refuses everything else -- every wall, every house, the town centre, and every unit
	# but the transport. Fullness is deliberately NOT part of it; see below.
	var b := w.get_entity(target_id)
	if b == null or not b.alive or b.owner_id != player_id or b.garrison_cap <= 0:
		return false
	if b is SimBuilding and not (b as SimBuilding).is_complete():
		return false

	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id or not (e is SimUnit):
			return false
		# A CARRIER IS NOT CARGO. Nothing carries ships, so ordering a transport into a
		# transport has to be refused somewhere, and refusing it here means the recursion
		# is impossible rather than merely unusual.
		if id == target_id or (e as SimUnit).garrison_cap > 0:
			return false
		# Already inside something. Its `pos` is stale and it is out of the spatial
		# index, so a route planned for it would be planned from nowhere -- and a unit
		# in two buildings at once is a garrison list that never balances.
		if (e as SimUnit).garrisoned_in != 0:
			return false
	return true


func apply(w: SimWorld) -> void:
	var b := w.get_entity(target_id)
	if b == null:
		return
	# The building's own tile is inside its footprint and therefore occupied ground;
	# PathService substitutes the nearest tile that can be stood on, the same way
	# walking up to a foundation or a tree does.
	var to := b.tile()
	for id in unit_ids:
		var u := w.get_entity(id) as SimUnit
		if u == null:
			continue
		u.set_task_garrison(target_id, to)
		if w.paths != null:
			w.paths.request(id, to)
