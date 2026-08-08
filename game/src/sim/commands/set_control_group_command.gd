## Assigns the current selection to one of a player's 5 control-group slots
## (PLAN.md 10.1/10.2). Sim state, not view state -- unlike an ordinary
## selection this must survive a reconnect, so it lives on `SimPlayer`
## (10.6) rather than only in the client's `Selection`.
##
## Any owned, alive entity can go in a slot -- a group is "revisit this
## selection later," not specifically a squad of units, so nothing here
## requires `SimUnit`.
class_name SetControlGroupCommand
extends Command

var slot: int = 0
var entity_ids: Array[int] = []


func _init(p_player_id: int = 0, p_slot: int = 0, p_entity_ids: Array[int] = [],
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	slot = p_slot
	entity_ids = p_entity_ids
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "set_control_group"
	d["slot"] = slot
	d["entity_ids"] = entity_ids
	return d


static func from_dict(d: Dictionary) -> SetControlGroupCommand:
	var c := SetControlGroupCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.slot = int(d.get("slot", 0))
	var ids: Array[int] = []
	for v in d.get("entity_ids", []):
		ids.append(int(v))
	c.entity_ids = ids
	return c


## Rejects an empty assignment rather than clearing the slot -- a double-tap
## with nothing selected is a no-op, not "empty this group" (PLAN.md 10.4
## already covers emptying: a group reads as empty once every member it holds
## has died, with no separate clear gesture needed).
func validate(w: SimWorld) -> bool:
	if slot < 0 or slot >= SimPlayer.CONTROL_GROUP_COUNT or entity_ids.is_empty():
		return false
	var p := w.player_for(player_id)
	if p == null:
		return false
	for id in entity_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id:
			return false
	return true


func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p != null:
		p.control_groups[slot] = entity_ids.duplicate()
