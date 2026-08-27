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
		# Rubble (5.5) stays in `entities` indefinitely with whatever queue it had
		# going -- without this a destroyed town centre would keep training
		# villagers out of its own wreckage forever.
		if not b.alive or b.queue.is_empty():
			continue

		var front: Dictionary = b.queue[0]
		if not bool(front.get("ready", false)):
			front["progress"] = int(front.get("progress", 0)) + 1
			if int(front["progress"]) >= int(front.get("total", 1)):
				front["ready"] = true
			else:
				continue

		# THE UNIT'S OWN DOMAIN, not LAND. This hard-coded LAND, so a dock launched its
		# fishing ships onto the beach -- reported 2026-08-23 as "boats spawn and sail
		# on land, its very funny". A water unit put on sand is not merely misplaced:
		# nothing else in the sim will ever move it off, because every route it could
		# be given starts from a tile its own domain says it cannot occupy.
		var trained := StringName(front.get("def_id", &""))
		var td: UnitDef = w.unit_def(trained)
		var domain := SimMap.from_domain_name(td.domain) if td != null \
				else SimMap.Domain.LAND
		var tile := w.map.find_free_adjacent(b.footprint_rect(), domain)
		if tile.x < 0:
			continue          # no room yet; retried next tick, nothing is lost
		var spawned := w.spawn_unit(trained, b.owner_id, tile)
		# AND THEN IT WALKS TO THE RALLY POINT, if its building has one (project owner,
		# 2026-08-27). This function's header has described `find_free_adjacent`'s spot
		# as "a full rally point" since 5.4 without there being one; now there is.
		#
		# It is the same call `ungarrison_unit` makes, on purpose: a unit trained here and
		# a garrison turned out of here are both "something leaving this building", they
		# had the same defect (appearing up-screen of it, behind the art), and one rule
		# fixes both. A building with no waypoint is untouched, which is every building
		# until a player sets one.
		w.send_to_waypoint(b, spawned)
		b.queue.pop_front()
