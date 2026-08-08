## Cancels whatever task a unit is doing and holds position.
class_name StopCommand
extends Command

var unit_ids: Array[int] = []


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "stop"
	d["unit_ids"] = unit_ids
	return d


static func from_dict(d: Dictionary) -> StopCommand:
	var c := StopCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	return c


func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id or not (e is SimUnit):
			return false
	return true


func apply(w: SimWorld) -> void:
	for id in unit_ids:
		(w.get_entity(id) as SimUnit).stop()
		# Drop any search still queued for this unit, or it would be solved a few
		# ticks later and hand a stopped unit a route to walk (4.2).
		if w.paths != null:
			w.paths.cancel(id)
