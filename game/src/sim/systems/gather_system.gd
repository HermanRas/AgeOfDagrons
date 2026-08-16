## The gather loop (PLAN.md 6.4): walk to a node, take from it on a cooldown,
## carry up to cap, walk a load home, deposit, repeat until the node is empty --
## at which point the node itself goes, which is also this system's job
## (PLAN.md's system table gives it "depletion", and SimResourceNode.gather()
## defers removal here rather than deciding it under a working villager).
##
## A DEPLETED NODE IS DESPAWNED OUTRIGHT, not left standing as a husk. Its tile is
## claimed occupancy (2.3), so a chopped-out forest that stayed in `entities`
## would leave a dozen unwalkable, unbuildable holes in the ground looking exactly
## like trees -- which is what it did until 2026-08-16. `remaining_fraction()`
## survives for the depletion VISUAL a stump would need; there is no stump art yet
## (PLAN.md A.4), and fading a full-size tree to nothing is not an improvement on
## removing it.
## `gather_slots` (PLAN.md 6.3) caps how many units can be drawing from one
## node at once -- an arrived unit past the cap holds its ground rather than
## gathering, so ten villagers sent at one tree do not all extract at once.
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
	var emptied: Array[int] = []
	for entry in w.entities.values():
		if entry is SimResourceNode:
			if (entry as SimResourceNode).is_depleted():
				emptied.append(entry.id)
			continue
		if not (entry is SimUnit):
			continue
		var u: SimUnit = entry
		if u.task == SimUnit.Task.GATHER:
			_process_gather(w, u)
		elif u.task == SimUnit.Task.RETURN:
			_process_return(w, u)

	# AFTER the unit loop, and out of a list rather than inside it: despawn()
	# mutates `entities`, which cannot be done while iterating it, and a villager
	# that filled its last load this tick has already been turned for home above.
	# Its final delivery still lands -- _process_return() deposits before it looks
	# for the node to go back to, and finds it gone only then.
	for id in emptied:
		w.despawn(id)


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

	if not _holds_gather_slot(w, node, u):
		return          # every slot is taken by a lower-id competitor; wait rather than give up

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


## Whether `u` is one of the (at most) `node.gather_slots` units currently
## drawing from it (PLAN.md 6.3's cap on simultaneous gatherers). Recomputed
## fresh every tick from live task state rather than reserved once and stored
## in a new field -- ties broken by id, the same determinism convention as
## `nearest_drop_off()` -- so a competitor stopping, dying, or being re-tasked
## frees its spot for whoever ranks next, with nothing extra to keep in sync.
##
## RETURN counts alongside GATHER: a unit walking a load home still holds its
## place at the node it is coming back to, so a slot cannot be sniped out from
## under it mid-cycle by whichever other villager happens to arrive first.
func _holds_gather_slot(w: SimWorld, node: SimResourceNode, u: SimUnit) -> bool:
	var holders: Array[int] = []
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var other: SimUnit = entry
		if not other.alive or other.gather_node_id != node.id:
			continue
		if other.task == SimUnit.Task.GATHER or other.task == SimUnit.Task.RETURN:
			holders.append(other.id)
	holders.sort()
	return holders.find(u.id) < node.gather_slots


func _adjacent_to_tile(from: Vector2i, target: Vector2i) -> bool:
	return absi(from.x - target.x) <= 1 and absi(from.y - target.y) <= 1


func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return absi(from.x - cx) <= 1 and absi(from.y - cy) <= 1
