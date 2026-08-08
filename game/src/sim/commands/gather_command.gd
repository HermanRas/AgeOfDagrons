## Order a set of units to work a resource node (PLAN.md 4.4, 6.4).
##
## One command, many units, same shape as MoveCommand -- a shared-target order is
## one message over the wire however many villagers it sends to the same tree.
class_name GatherCommand
extends Command

var unit_ids: Array[int] = []
var node_id: int = 0


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_node_id: int = 0,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	node_id = p_node_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "gather"
	d["unit_ids"] = unit_ids
	d["node_id"] = node_id
	return d


static func from_dict(d: Dictionary) -> GatherCommand:
	var c := GatherCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	c.node_id = int(d.get("node_id", 0))
	return c


func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false
	var node := w.get_entity(node_id)
	if node == null or not node.alive or not (node is SimResourceNode):
		return false
	if (node as SimResourceNode).is_depleted():
		return false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id or not (e is SimUnit):
			return false
	return true


func apply(w: SimWorld) -> void:
	var node := w.get_entity(node_id) as SimResourceNode
	if node == null:
		return
	for id in unit_ids:
		(w.get_entity(id) as SimUnit).set_task_gather(node_id, node.tile())
		if w.paths != null:
			w.paths.request(id, node.tile())
