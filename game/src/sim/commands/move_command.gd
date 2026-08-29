## Order a set of units to walk to a tile.
##
## One command carries MANY unit ids on purpose: a shared-destination order is a
## single command over the wire however many units it moves (PLAN.md 7.2). It is
## still one PATH per unit, since they start from different tiles -- those go into
## PathService's queue and are solved against its per-tick budget (4.2).
##
## A FORMATION IS A PROPERTY OF THE ORDER, NOT OF THE UNIT (PLAN.md 4.14, 2026-08-29),
## and that is what kept 4.14 to one field and one pure helper. Nothing is stored on
## `SimUnit`, nothing rides the snapshot, and a formation cannot be left half-applied
## after a unit dies -- the shape exists only for as long as it takes to turn one tapped
## tile into one destination each. Which shape is "currently selected" is a client-side
## preference, exactly like the selection itself, and lives in `GameScene`.
class_name MoveCommand
extends Command

var unit_ids: Array[int] = []
var target_tile: Vector2i = Vector2i.ZERO

## `Formation.NONE`, or one of `Formation.SHAPES`. Absent means every unit walks to the
## one tile, which is what a move order has always done and what every existing caller --
## the AI, the tests, the minimap, `send_to_waypoint` -- gets by not saying anything.
var formation: StringName = Formation.NONE


func _init(p_player_id: int = 0, p_unit_ids: Array[int] = [], p_target_tile: Vector2i = Vector2i.ZERO,
		p_issued_tick: int = 0, p_formation: StringName = Formation.NONE) -> void:
	player_id = p_player_id
	unit_ids = p_unit_ids
	target_tile = p_target_tile
	issued_tick = p_issued_tick
	formation = p_formation


## `formation` is omitted when there is none, rather than sent empty. It is the common
## case by a wide margin -- every AI order and every minimap tap -- and `from_dict`
## defaults to NONE, so this costs nothing to read and saves a key on most packets.
func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "move"
	d["unit_ids"] = unit_ids
	d["target_tile"] = {"x": target_tile.x, "y": target_tile.y}
	if formation != Formation.NONE:
		d["formation"] = String(formation)
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
	c.formation = StringName(d.get("formation", ""))
	return c


func validate(w: SimWorld) -> bool:
	if unit_ids.is_empty():
		return false
	# AN UNKNOWN SHAPE IS REFUSED, NOT IGNORED. Falling back to NONE would leave a client
	# and a server disagreeing about where an army is walking, which is a desync dressed
	# as a cosmetic difference -- and it would hide the version skew that caused it.
	if formation != Formation.NONE and not Formation.is_shape(formation):
		return false
	for id in unit_ids:
		var e := w.get_entity(id)
		if e == null or not e.alive or not (e is SimUnit):
			return false
		# OWNED, OR HERDED. Livestock stays gaia's and is ordered through `herded_by`
		# instead (6.5) -- see `HerdSystem` for why the two are kept apart. This is the
		# only command that accepts the second form: a sheep may be walked home and
		# nothing else, which is the whole of what herding is.
		if e.owner_id != player_id and (e as SimUnit).herded_by != player_id:
			return false
	return true


## One destination each, which for the formationless case is the same tile for everybody
## and is exactly what this used to do.
##
## `unit_ids` ORDER IS NOT TRUSTED and that is the whole determinism argument. It arrives
## from a client's selection, which is built from `units_in_box` and a tap history, so
## two hosts can legitimately hold the same set in a different order -- and `Formation`
## ranks by position with an ID tie-break precisely so the assignment does not depend on
## it. What must match is the SET, and validate has already checked every member of it.
func apply(w: SimWorld) -> void:
	var tiles: Array[Vector2i] = []
	for id in unit_ids:
		tiles.append((w.get_entity(id) as SimUnit).tile())
	var targets := Formation.destinations(formation, target_tile, tiles, unit_ids)

	for i in range(unit_ids.size()):
		var id := unit_ids[i]
		var at := targets[i]
		(w.get_entity(id) as SimUnit).set_task_move(at)
		if w.paths != null:
			w.paths.request(id, at)
