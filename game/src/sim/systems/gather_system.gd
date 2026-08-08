## The gather loop (PLAN.md 6.4): walk to a node, take from it on a cooldown,
## carry up to cap, walk a load home, deposit, repeat until the node is empty.
##
## Runs after TaskSystem and before MovementSystem -- same slot TaskSystem itself
## occupies, and for the same reason. A unit that arrived last tick (no waypoint
## left, no path pending) is either put to work or turned around for home THIS
## tick, and if that starts a new route MovementSystem walks it the same tick
## rather than paying an extra tick of visible delay.
##
## `gather_cooldown` counts DOWN in whole ticks, not a fractional accumulator: a
## float accruing `gather_rate` here would round differently on different
## machines and desync (PLAN.md 7.1). `gather_rate` is authored per 100 ticks
## (units.json), so the ticks a single unit costs is a ceiling division done in
## pure integers -- rate 25 gives 4.
class_name GatherSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var u: SimUnit = entry
		if u.task == SimUnit.Task.GATHER:
			_process_gather(w, u)
		elif u.task == SimUnit.Task.RETURN:
			_process_return(w, u)


func _process_gather(w: SimWorld, u: SimUnit) -> void:
	# Still walking there -- nothing to do until it arrives.
	if u.path_pending or u.has_waypoint():
		return

	var node := w.get_entity(u.task_target_id) as SimResourceNode
	if node == null or not node.alive or node.is_depleted():
		u.stop()
		return
	if not _adjacent_to_tile(u.tile(), node.tile()):
		# The substituted walk-up tile should always be adjacent (4.1); if it is
		# not, the order cannot be honoured rather than gathering through a wall.
		u.stop()
		return

	# A unit still holding a different kind from an earlier, since-changed order
	# must drop that load off before it can start a new one -- carrying two kinds
	# at once has no slot to represent it.
	if u.carry_amount > 0 and u.carry_kind != node.kind:
		_start_return(w, u)
		return

	var def := w.unit_def(u.def_id)
	var rate := int(def.gather_rate.get(node.kind, 0)) if def != null else 0
	var per_unit := _ticks_per_unit(rate)
	if per_unit <= 0:
		u.stop()          # this unit cannot gather this kind at all
		return

	if u.gather_cooldown > 0:
		u.gather_cooldown -= 1
		return

	u.carry_kind = node.kind
	u.carry_amount += node.gather(1)
	u.gather_cooldown = per_unit - 1

	var cap := int(def.carry_cap.get(node.kind, 0)) if def != null else 0
	if u.carry_amount >= cap or node.is_depleted():
		_start_return(w, u)


func _process_return(w: SimWorld, u: SimUnit) -> void:
	if u.path_pending or u.has_waypoint():
		return

	var bld := w.get_entity(u.task_target_id) as SimBuilding
	if bld == null or not bld.alive or not bld.is_complete():
		u.stop()
		return
	if not _adjacent_to_rect(u.tile(), bld.footprint_rect()):
		u.stop()
		return

	var player := w.player_for(u.owner_id)
	if player != null and u.carry_amount > 0:
		player.add_resource(u.carry_kind, u.carry_amount)
	u.carry_amount = 0

	var node := w.get_entity(u.gather_node_id) as SimResourceNode
	if node == null or not node.alive or node.is_depleted():
		u.stop()
		return

	u.set_task_gather(node.id, node.tile())
	if w.paths != null:
		w.paths.request(u.id, node.tile())


func _start_return(w: SimWorld, u: SimUnit) -> void:
	var bld := w.nearest_drop_off(u.owner_id, u.carry_kind, u.tile())
	if bld == null:
		u.stop()          # nowhere to take the load; better idle than stuck walking
		return
	u.set_task_return(bld.id, bld.tile())
	if w.paths != null:
		w.paths.request(u.id, bld.tile())


## Whole ticks to gather one unit at `rate` per 100 ticks. Ceiling division kept
## entirely in integers -- rate 25 gives (100 + 24) / 25 = 4.
func _ticks_per_unit(rate: int) -> int:
	if rate <= 0:
		return 0
	return (100 + rate - 1) / rate


func _adjacent_to_tile(from: Vector2i, target: Vector2i) -> bool:
	return absi(from.x - target.x) <= 1 and absi(from.y - target.y) <= 1


func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return absi(from.x - cx) <= 1 and absi(from.y - cy) <= 1
