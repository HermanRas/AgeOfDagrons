## Order a set of units to walk to a tile.
##
## One command carries MANY unit ids on purpose: a shared-destination order is a
## single command over the wire however many units it moves (PLAN.md 7.2). It is
## still one PATH per unit, since they start from different tiles -- those go into
## PathService's queue and are solved against its per-tick budget (4.2).
class_name MoveCommand
extends Command

var unit_ids: Array[int] = []
var target_tile: Vector2i = Vector2i.ZERO


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_target_tile: Vector2i = Vector2i.ZERO,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	target_tile = p_target_tile
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "move"
	d["unit_ids"] = unit_ids
	d["target_tile"] = {"x": target_tile.x, "y": target_tile.y}
	return d


static func from_dict(d: Dictionary) -> MoveCommand:
	var c := MoveCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	var t: Dictionary = d.get("target_tile", {})
	c.target_tile = Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
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
		(w.get_entity(id) as SimUnit).set_task_move(target_tile)
		if w.paths != null:
			w.paths.request(id, target_tile)
