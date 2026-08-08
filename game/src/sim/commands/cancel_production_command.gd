## Cancels one queued (or in-progress) training order and refunds its cost
## (PLAN.md 5.4). `index` into the building's own queue, not a global id -- the
## queue has no separate identity for its entries beyond position.
class_name CancelProductionCommand
extends Command

var building_id: int = 0
var index: int = 0


func _init(p_player_id: int = 0, p_building_id: int = 0, p_index: int = 0,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	index = p_index
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "cancel_production"
	d["building_id"] = building_id
	d["index"] = index
	return d


static func from_dict(d: Dictionary) -> CancelProductionCommand:
	var c := CancelProductionCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	c.index = int(d.get("index", 0))
	return c


func validate(w: SimWorld) -> bool:
	var e := w.get_entity(building_id)
	if e == null or not e.alive or not (e is SimBuilding) or e.owner_id != player_id:
		return false
	return index >= 0 and index < (e as SimBuilding).queue.size()


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null:
		return
	var entry := b.cancel_training(index)
	if entry.is_empty():
		return
	var p := w.player_for(player_id)
	if p != null:
		p.refund(entry.get("cost", {}))
