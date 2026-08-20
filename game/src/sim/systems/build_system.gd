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
## Anything else stops, as before -- a house or a barracks has no work to offer,
## and inventing some would be a unit wandering off on an order nobody gave.
## `is_harvestable()` is the same test GatherCommand validates against, so this
## can never start a gather the system would then refuse.
func _finished(w: SimWorld, u: SimUnit, b: SimBuilding) -> void:
	if not GatherSystem.is_harvestable(b, u.owner_id):
		u.stop()
		return

	var spot := GatherSystem.harvest_spot(b, u.id)
	u.set_task_gather(b.id, spot)
	if w.paths != null:
		w.paths.request(u.id, spot)


func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return absi(from.x - cx) <= 1 and absi(from.y - cy) <= 1
