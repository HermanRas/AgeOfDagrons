## Order a set of units to attack one enemy entity (PLAN.md 4.13).
##
## One command, many attackers, one target -- the same shared-target shape as
## GatherCommand and BuildCommand, so sending eight units at one building is one
## message over the wire rather than eight.
##
## The target may be a UNIT or a BUILDING. Resource nodes are deliberately not
## attackable: gaia owns them, they are gathered rather than fought, and 4.13's
## hostile wolf (the one gaia entity that would be a real target) is not built
## yet. `validate()` refusing owner 0 is what keeps "attack that tree" from being
## expressible at all rather than merely useless.
class_name AttackCommand
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
	d["type"] = "attack"
	d["unit_ids"] = unit_ids
	d["target_id"] = target_id
	return d


static func from_dict(d: Dictionary) -> AttackCommand:
	var c := AttackCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	c.target_id = int(d.get("target_id", 0))
	return c


## Refuses: an empty order, a target that is gone, dead, gaia-owned or the
## caller's own, any attacker that is not the caller's living unit, and a
## selection in which NOBODY can actually fight.
##
## That last check is why this is not simply "every id is a unit". A trade cart
## carries no attack (units.json gives it damage 0), and a selection of nothing
## but trade carts must be refused rather than accepted into an order none of
## them can carry out -- otherwise the sim reports success and the player watches
## a convoy stand in front of a barracks doing nothing. A MIXED selection is
## accepted, and apply() drops the ones that cannot fight; that mirrors
## `GameView.movable_selection()`'s existing rule for move orders, where a
## selection is filtered rather than rejected whole.
func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false

	# Null, dead, a resource node, somebody's own, and gaia's scenery are all refused
	# here -- but gaia's WILDLIFE is not, which is how a wolf can be hunted at all.
	# See `Diplomacy`, which replaced this file's own copy of the owner clause.
	if not Diplomacy.is_enemy(w.get_entity(target_id), player_id):
		return false

	var armed := false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id or not (e is SimUnit):
			return false
		if _can_fight(w, e as SimUnit):
			armed = true
	return armed


func apply(w: SimWorld) -> void:
	var target := w.get_entity(target_id)
	if target == null:
		return
	for id in unit_ids:
		var u := w.get_entity(id) as SimUnit
		if u == null or not _can_fight(w, u):
			continue
		u.set_task_attack(target_id, target.tile())
		if w.paths != null:
			w.paths.request(id, target.tile())


## Whether this unit has an attack at all. Damage, not a "military" flag: the
## villager carries damage 3 to defend herself (units.json) and is a perfectly
## legal, if poor, attacker -- which is the behaviour every RTS this is modelled
## on has, and the reason peasant rushes exist.
static func _can_fight(w: SimWorld, u: SimUnit) -> bool:
	var d := w.unit_def(u.def_id)
	return d != null and d.attack_damage > 0
