## Straight-line movement toward a MOVE task's target tile. No pathfinding or
## collision yet -- SimMap and PathService (phase 2.1) insert themselves here
## once terrain exists to navigate around.
class_name MovementSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit) or entry.task != SimUnit.Task.MOVE:
			continue
		var e: SimUnit = entry

		var target: Vector2i = e.move_target_subpos()
		var delta: Vector2i = target - e.pos
		if delta == Vector2i.ZERO:
			continue

		var old_tile: Vector2i = e.tile()
		var dist := Vector2(delta).length()
		if dist <= float(e.speed):
			e.pos = target
		else:
			var step := Vector2(delta).normalized() * float(e.speed)
			e.pos += Vector2i(roundi(step.x), roundi(step.y))
		e.facing = _facing_from_delta(delta)

		var new_tile: Vector2i = e.tile()
		if new_tile != old_tile:
			w.spatial.move(e.id, new_tile)


## 8-way facing from a movement delta. 0 = east, increasing clockwise.
func _facing_from_delta(delta: Vector2i) -> int:
	var angle := atan2(-float(delta.y), float(delta.x))
	var octant := int(round(angle / (PI / 4.0))) % 8
	return octant + 8 if octant < 0 else octant
