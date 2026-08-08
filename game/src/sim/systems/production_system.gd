## Advances each building's training queue and spawns whatever finishes
## (PLAN.md 5.4). Only the FRONT entry progresses -- SimBuilding.queue's own
## invariant -- so this only ever has to look at index 0.
##
## A finished order is not popped until it actually spawns. A packed town
## centre with nowhere free to stand must not simply discard the villager who
## was paid for; `find_free_adjacent` is retried every tick until room opens up,
## exactly like a real RTS backing up production behind a full rally point.
class_name ProductionSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for e in w.entities.values():
		if not (e is SimBuilding):
			continue
		var b: SimBuilding = e
		if b.queue.is_empty():
			continue

		var front: Dictionary = b.queue[0]
		if not bool(front.get("ready", false)):
			front["progress"] = int(front.get("progress", 0)) + 1
			if int(front["progress"]) >= int(front.get("total", 1)):
				front["ready"] = true
			else:
				continue

		var tile := w.map.find_free_adjacent(b.footprint_rect(), SimMap.Domain.LAND)
		if tile.x < 0:
			continue          # no room yet; retried next tick, nothing is lost
		w.spawn_unit(StringName(front.get("def_id", &"")), b.owner_id, tile)
		b.queue.pop_front()
