## Enqueues a unit at a building's production queue (PLAN.md 5.4).
class_name TrainCommand
extends Command

var building_id: int = 0
var unit_def_id: StringName = &""


func _init(p_player_id: int = 0, p_building_id: int = 0, p_unit_def_id: StringName = &"",
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	building_id = p_building_id
	unit_def_id = p_unit_def_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "train"
	d["building_id"] = building_id
	d["unit_def_id"] = String(unit_def_id)
	return d


static func from_dict(d: Dictionary) -> TrainCommand:
	var c := TrainCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.building_id = int(d.get("building_id", 0))
	c.unit_def_id = StringName(d.get("unit_def_id", ""))
	return c


func validate(w: SimWorld) -> bool:
	var e := w.get_entity(building_id)
	if e == null or not e.alive or not (e is SimBuilding) or e.owner_id != player_id:
		return false
	var b := e as SimBuilding
	if not b.is_complete():
		return false

	var bd: BuildingDef = w.building_def(b.def_id)
	if bd == null or not bd.trains.has(unit_def_id):
		return false

	var ud: UnitDef = w.unit_def(unit_def_id)
	if ud == null:
		return false

	var p := w.player_for(player_id)
	return p != null and p.can_afford(ud.cost)


func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	var ud: UnitDef = w.unit_def(unit_def_id)
	var p := w.player_for(player_id)
	if b == null or ud == null or p == null:
		return
	if not p.pay(ud.cost):
		return
	b.enqueue_training(unit_def_id, ud.build_time_ticks, ud.cost)
