## Walks units along the route PathService gave them (PLAN.md 4.1). Phase 4.1.
##
## Up to 0.5 this drove straight at the target tile, which was fine when there was
## nothing to walk into. It now follows the path waypoint by waypoint; the straight
## line survives only as the step between two ADJACENT tiles, where it is correct
## by construction.
##
## Walking is orthogonal to WHY a unit is walking: GATHER and RETURN (6.4) and
## BUILD (4.4) all cover ground on the way to doing something, so this drives any
## unit with a route left to walk rather than switching on the task -- the systems
## that act once a unit arrives (GatherSystem, BuildSystem) are the ones that care
## which task it is.
##
## Everything is integer sub-tile arithmetic (PLAN.md 1). `speed` is sub-units per
## tick, so a unit covers the same distance per tick on every machine -- the
## rounding below is the only place a float appears and it is rounded back
## immediately, deliberately, rather than accumulating in the position.
class_name MovementSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var e: SimUnit = entry
		# Ordered, but the search has not come back yet. Standing still for a tick
		# or two beats setting off in a direction the route may not take.
		if e.path_pending or not e.has_waypoint():
			continue
		_advance(w, e)


func _advance(w: SimWorld, e: SimUnit) -> void:
	var budget := e.speed
	var old_tile := e.tile()

	# A tick can cross more than one waypoint when the unit is fast or the
	# waypoints are close, so this consumes the whole tick's movement rather than
	# stopping at the first corner and wasting the remainder.
	while budget > 0 and e.has_waypoint():
		var target := e.waypoint_subpos()
		var delta := target - e.pos
		if delta == Vector2i.ZERO:
			e.path_index += 1
			continue

		var dist := Vector2(delta).length()
		if dist <= float(budget):
			e.pos = target
			budget -= int(ceil(dist))
			e.path_index += 1
		else:
			var step := Vector2(delta).normalized() * float(budget)
			e.pos += Vector2i(roundi(step.x), roundi(step.y))
			budget = 0
		e.facing = _facing_from_delta(delta)

	var new_tile := e.tile()
	if new_tile != old_tile:
		w.spatial.move(e.id, new_tile)


## 8-way facing from a movement delta. 0 = east, increasing clockwise.
func _facing_from_delta(delta: Vector2i) -> int:
	var angle := atan2(-float(delta.y), float(delta.x))
	var octant := int(round(angle / (PI / 4.0))) % 8
	return octant + 8 if octant < 0 else octant
