## Order a set of units to raise a building already standing as a foundation
## (PLAN.md 4.4). Placing the foundation itself is 5.1 -- this command only
## covers sending workers to one that already exists.
class_name BuildCommand
extends Command

var unit_ids: Array[int] = []
var building_id: int = 0


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_building_id: int = 0,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	building_id = p_building_id
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "build"
	d["unit_ids"] = unit_ids
	d["building_id"] = building_id
	return d


static func from_dict(d: Dictionary) -> BuildCommand:
	var c := BuildCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	var ids: Array[int] = []
	for v in d.get("unit_ids", []):
		ids.append(int(v))
	c.unit_ids = ids
	c.building_id = int(d.get("building_id", 0))
	return c


func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false
	var b := w.get_entity(building_id)
	if b == null or not b.alive or not (b is SimBuilding) or b.owner_id != player_id:
		return false
	if (b as SimBuilding).is_complete():
		return false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or e.owner_id != player_id or not (e is SimUnit):
			return false
	return true


## ⛔ **EACH BUILDER GETS ITS OWN STANDING POSITION** (owner, playtest 2026-09-21:
## *"the villagers bunching up on one spot, trying to build the castle"*).
##
## This used to hand every unit `b.tile()` — the footprint's top-left corner — so a dozen
## villagers sent to a castle were a dozen units with one identical destination. They
## arrived in a heap at one corner of a building whose perimeter is 32 tiles, and
## **three of twelve ended up not touching it at all**, shoved out of the huddle by
## `SeparationSystem` and adding nothing. `BuildStations` has the measurement.
##
## ⚠️ **AN UNREACHABLE STATION NEEDS NO HANDLING HERE**, the same way it needs none in
## `Formation`: `PathService` substitutes the nearest tile that can actually be stood on
## and `SimUnit.set_path` rewrites `task_target_tile` to wherever the route really ended.
## So the ring degrades into "as close to your own spot as the ground allows".
func apply(w: SimWorld) -> void:
	var b := w.get_entity(building_id) as SimBuilding
	if b == null:
		return

	# Gathered first rather than assigned in the loop, because the allocator has to see
	# the whole crowd to spread it -- and it pairs positionally, so the two lists must be
	# built together and stay in step. A unit that has died since the command was issued
	# is dropped from BOTH.
	var ids: Array[int] = []
	var tiles: Array[Vector2i] = []
	for id in unit_ids:
		var u := w.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		ids.append(id)
		tiles.append(u.tile())

	var stations := BuildStations.around(b.footprint_rect(), w.map, tiles, ids)
	for i in range(ids.size()):
		var at: Vector2i = stations[i]
		(w.get_entity(ids[i]) as SimUnit).set_task_build(building_id, at)
		if w.paths != null:
			w.paths.request(ids[i], at)
