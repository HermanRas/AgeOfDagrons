## Retires a finished MOVE order. GATHER, RETURN and BUILD (4.4, 6.4) do not
## retire here -- each owns its own arrival check in GatherSystem/BuildSystem,
## since arriving there means "start working", not "go idle". ATTACK will join
## this file when combat lands.
##
## Runs BEFORE MovementSystem, so a unit that arrived last tick is retired before
## it is asked to move again, rather than spending a tick in MOVE with nowhere left
## to go.
class_name TaskSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	for e in w.entities.values():
		if e is SimUnit and e.task == SimUnit.Task.MOVE:
			_retire_if_arrived(e)


## A move is done when the route is walked out, not when the unit's position
## equals the ordered tile.
##
## Those differ whenever the ordered tile was blocked and PathService substituted
## the nearest reachable one (PLAN.md 4.1) -- comparing against the ORDER would
## leave such a unit in MOVE forever, standing still beside the tree it was sent
## to. `set_path()` rewrites task_target_tile to the route's real end, so the
## tile check below is a belt-and-braces agreement between the two.
##
## TILE, not exact sub-position: SeparationSystem (4.2) can nudge an arrived
## unit off the tile's dead centre on the same tick it lands, and a unit that
## never again matches that exact sub-pixel would sit in MOVE forever, looking
## idle but never retiring.
func _retire_if_arrived(e: SimUnit) -> void:
	if e.path_pending or e.has_waypoint():
		return
	if e.tile() == e.task_target_tile:
		e.task = SimUnit.Task.IDLE
