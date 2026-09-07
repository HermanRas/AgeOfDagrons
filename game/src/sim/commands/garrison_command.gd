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
## ⚠️ **THERE IS NOW EXACTLY ONE UNIT-SIDE CAPABILITY, AND IT IS FILTERED RATHER THAN
## REFUSED** (PLAN.md 4.8c, 2026-09-07). This header used to say *"EVERY unit can garrison
## -- there is no unit-side capability to fail"*, and `UnitDef.can_garrison` is that
## capability: false on the four siege engines and both dragons.
##
## **Ten swordsmen and one onager ordered into a tower admit the ten and drop the onager.**
## A blanket refusal would mean one siege engine caught in a box-select silently cancels a
## garrison the player plainly meant -- and it is the same answer 4.8 already gives to a
## tower that fills up mid-walk: *"the fifth is refused there rather than being promised a
## slot here"*. So this is AttackCommand's filtering rule arriving here at last, for
## AttackCommand's own reason: a mixed selection is the ordinary case, not a client bug.
##
## THE REST OF THE LIST IS STILL CHECKED RATHER THAN FILTERED, and the split is deliberate.
## A named unit that is dead, somebody else's, already inside something or a carrier is a
## client bug or a stale selection -- there is nothing for a player to have meant by it.
## Being siege is a fact about the roster, which is different.
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

	var admitted := 0
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
		# THE ONE FILTERED CASE. See the header: siege engines and dragons are dropped from
		# the order rather than cancelling it for everybody selected alongside them.
		if not _may_garrison(w, e as SimUnit):
			continue
		admitted += 1
	# AT LEAST ONE, so an order made up ENTIRELY of siege still fails rather than being
	# accepted and doing nothing. A command that validates and has no effect is the
	# invisible refusal `GameView.tap_action`'s own comments keep warning about.
	return admitted > 0


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
		# FILTERED AGAIN HERE, not just counted in `validate`. The two run at different
		# times -- validate on submission, apply on the tick -- and a rule enforced only in
		# the check is a rule that stops existing the day something applies a command it
		# did not validate. It also has to be per-unit: `validate` answered one question
		# about the whole order, and this is where each unit is actually sent.
		if not _may_garrison(w, u):
			continue
		u.set_task_garrison(target_id, to)
		if w.paths != null:
			w.paths.request(id, to)


## Whether `u`'s def allows it inside anything at all (PLAN.md 4.8c).
##
## A MISSING DEF ANSWERS TRUE, which is the default `UnitDef.can_garrison` carries and the
## honest answer for a unit whose roster row cannot be read: the pre-4.8c behaviour, rather
## than a silent new refusal on top of whatever is already wrong.
static func _may_garrison(w: SimWorld, u: SimUnit) -> bool:
	var def := w.unit_def(u.def_id)
	return def == null or def.can_garrison
