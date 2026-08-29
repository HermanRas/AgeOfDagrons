## Set what a group of units will start on their own (PLAN.md 4.12).
##
## Many ids in one command, exactly as `MoveCommand` carries many: setting a stance is
## the sort of thing a player does to a whole selection at once, and one command over
## the wire per army is the shape 7.2 asks for.
##
## IT DOES NOT RETASK ANYTHING. A unit already fighting keeps fighting; a villager
## already gathering keeps gathering. The stance is a standing instruction about what to
## do NEXT time the unit is idle, and `StanceSystem` is the only thing that reads it --
## so this command writes exactly one field and cannot break an order in flight.
##
## THE GUARD POST IS CLEARED, and that is the one thing beyond the field itself. A unit
## taken off DEFENSIVE while it is walking back to a post would otherwise carry that post
## forever, since only `StanceSystem` releases it and it stops looking at a unit whose
## stance it no longer manages. Clearing here is a line; the alternative is a leak that
## surfaces days later as a soldier who walks somewhere unaccountable after a fight.
class_name SetStanceCommand
extends Command

var unit_ids: Array[int] = []
var stance: int = SimUnit.Stance.PASSIVE


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [],
		p_stance: int = SimUnit.Stance.PASSIVE, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	stance = p_stance
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "set_stance"
	d["unit_ids"] = unit_ids
	d["stance"] = stance
	return d


static func from_dict(d: Dictionary) -> SetStanceCommand:
	var c := SetStanceCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	c.stance = int(d.get("stance", SimUnit.Stance.PASSIVE))
	return c


## THE RANGE CHECK IS NOT DECORATION. `stance` arrives off the wire as an int and is
## written straight onto the unit, so an out-of-range value would sit there matching none
## of `StanceSystem`'s arms -- a unit that is silently inert and answers to no stance the
## panel can show. `SimUnit.Stance`'s own header records that the order is load-bearing
## for the same reason `colours.json`'s is.
##
## HERDED LIVESTOCK IS DELIBERATELY NOT ACCEPTED, unlike `MoveCommand`. A sheep is
## walked home and nothing else; giving one a stance would be giving gaia an army, and
## `StanceSystem` skips owner 0 outright so the field would do nothing anyway. Refusing
## it here is the server saying so rather than the sim quietly ignoring it.
func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false
	if stance < 0 or stance > SimUnit.Stance.PASSIVE:
		return false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or not (e is SimUnit):
			return false
		if e.owner_id != player_id:
			return false
	return true


func apply(w: SimWorld) -> void:
	for id in unit_ids:
		var u := w.get_entity(id) as SimUnit
		u.stance = stance
		u.guard_post = SimUnit.NO_POST
