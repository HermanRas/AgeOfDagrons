## Advances construction on whatever a BUILD-tasked villager is standing next to
## (PLAN.md 4.4). Placing the foundation is 5.1, showing its progress bar is 5.2 --
## this system only supplies the progress those will read.
##
## One villager finishes a building in exactly its authored `build_time_ticks`:
## `BUILD_RATE` is 1 progress per tick per worker, so build_total IS the solo
## build time by construction, with no separate per-worker rate to keep in sync
## with it. Multiple builders on the same foundation simply add their rate
## together, for free, because each is a separate SimUnit calling this each tick.
class_name BuildSystem
extends SimSystem

const BUILD_RATE := 1

func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		# `alive` for the same reason CombatSystem asks it: a unit destroyed by a
		# command this tick is already dead when this runs, and DeathSystem does not
		# clear its task until the end of the tick. Nobody builds from the grave.
		if entry is SimUnit and entry.alive and entry.task == SimUnit.Task.BUILD:
			_process(w, entry)


func _process(w: SimWorld, u: SimUnit) -> void:
	if u.path_pending or u.has_waypoint():
		return

	var b := w.get_entity(u.task_target_id) as SimBuilding
	if b == null or not b.alive or b.is_complete():
		u.stop()
		return
	if not _adjacent_to_rect(u.tile(), b.footprint_rect()):
		u.stop()
		return

	# Face the work, for the reason GatherSystem spells out at the same point in its
	# own tick: a builder hammering with his back to the wall reads as a bug, and
	# nothing else was ever going to turn him -- MovementSystem stopped caring the
	# moment he arrived. A building's `pos` is its CENTRE, so this points at the
	# middle of the footprint rather than at a corner, which is what a person would
	# face when standing against a long wall.
	u.facing = SimUnit.facing_toward(b.pos - u.pos)

	if b.add_build_progress(BUILD_RATE):
		# COMPLETE is set inside add_build_progress().
		_finished(w, u, b)


## What a builder does the tick its building completes.
##
## A FIELD PUTS ITS BUILDER STRAIGHT TO WORK (project owner, 2026-08-17). Standing
## idle beside a finished crop is the wrong default: farming it is the only reason
## the plot was paid for, the villager is already standing on it, and the player
## would otherwise have to find and re-order every farmer by hand the moment each
## plot came up.
##
## OTHERWISE IT LOOKS FOR ANOTHER FOUNDATION (project owner, 2026-08-22). Until then
## this simply called `stop()`, and the reasoning recorded here was that a house or a
## barracks has no work to offer so inventing some would be a unit wandering off on an
## order nobody gave. That held while a placement was one building. **A wall drag lays
## a dozen at once**, spreads the builders round-robin across them, and every villager
## downed tools after its first segment -- reported from play as "builder does not
## continue to build all the pieces, stops after 1".
##
## It is not wandering off on an order nobody gave: every foundation it can find was
## placed by this player on purpose and is standing there unbuilt. The bound is
## `SimSystem.SAME_WORK_RADIUS`, which is what keeps it "the site I am on" rather than
## "every building site I own".
## A FINISHED WALL SEGMENT MAY BE SWALLOWED BY ITS OWN NEIGHBOURS (project owner,
## 2026-08-22): three shorts that meet become one long piece. Done first, and before
## the builder is given anything else to do, because `b` may not survive it -- the
## merge keeps the piece at the low end of the run and despawns the others, so
## `GatherSystem.is_harvestable(b, ...)` below could be asked about an entity that no
## longer exists. A wall is never harvestable and never the next foundation, so the
## re-read costs the ordinary case nothing.
func _finished(w: SimWorld, u: SimUnit, b: SimBuilding) -> void:
	if WallMerge.apply(w, b):
		if not _next_foundation(w, u, b):
			u.stop()
		return

	if GatherSystem.is_harvestable(b, u.owner_id):
		var spot := GatherSystem.harvest_spot(b, u.id)
		u.set_task_gather(b.id, spot)
		if w.paths != null:
			w.paths.request(u.id, spot)
		return

	if not _next_foundation(w, u, b):
		u.stop()


## Send `u` to another unfinished building of its owner's near the one just raised.
## True if one was found and the unit is now walking to it.
##
## PREFERS A FOUNDATION NOBODY IS ALREADY BUILDING, which is what preserves the
## round-robin spread `PlaceWallCommand` set up. Without it, the first villager to
## finish walks to the segment the second is already raising, they finish it together,
## and from then on the whole crew moves as one pack down the wall -- correct, and
## about as slow as one villager doing the lot. Ranked rather than filtered, so a crew
## larger than the number of foundations still all find work instead of stopping.
##
## Measured from where the FINISHED BUILDING stood, not from the unit: a villager who
## has just raised a nine-tile wall may be standing at either end of it, and using its
## own tile would make which segment it picks next depend on where it happened to
## finish. The building is the site.
##
## Deterministic, and it has to be: a strict minimum over
## (already-claimed, distance, id) walked in sorted id order -- the same shape
## `CombatSystem._reacquire` uses, and for the same reason. Two hosts sending one
## villager to different foundations is a desync.
func _next_foundation(w: SimWorld, u: SimUnit, done: SimBuilding) -> bool:
	if w.paths == null:
		return false
	var from := done.tile()
	var ids := w.entities.keys()
	ids.sort()

	var best: SimBuilding = null
	var best_claimed := 0
	var best_d := 0
	for id in ids:
		if id == done.id:
			continue
		var e: SimEntity = w.entities[id]
		if not (e is SimBuilding):
			continue
		var candidate: SimBuilding = e
		if candidate.owner_id != u.owner_id or not candidate.alive or candidate.is_complete():
			continue
		if candidate.phase == SimBuilding.Phase.DESTROYED:
			continue
		var gap := CombatSystem.tile_gap(from, candidate.footprint_rect())
		if gap > SimSystem.SAME_WORK_RADIUS:
			continue
		var claimed := 1 if _has_builder(w, candidate.id, u.id) else 0
		if best != null:
			if claimed > best_claimed:
				continue
			if claimed == best_claimed:
				if gap > best_d:
					continue
				if gap == best_d and int(id) > best.id:
					continue
		best = candidate
		best_claimed = claimed
		best_d = gap

	if best == null:
		return false
	u.set_task_build(best.id, best.tile())
	w.paths.request(u.id, best.tile())
	return true


## Whether anybody but `except_id` is already on their way to build `building_id`.
static func _has_builder(w: SimWorld, building_id: int, except_id: int) -> bool:
	for e in w.entities.values():
		if not (e is SimUnit) or e.id == except_id or not e.alive:
			continue
		var other: SimUnit = e
		if other.task == SimUnit.Task.BUILD and other.task_target_id == building_id:
			return true
	return false


func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return absi(from.x - cx) <= 1 and absi(from.y - cy) <= 1
