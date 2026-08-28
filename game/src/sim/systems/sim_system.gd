## Base for one stage of SimWorld.step(). Systems run in a fixed order
## (PLAN.md 5.1, 6.2) so tick behaviour stays deterministic regardless of
## instantiation order.
class_name SimSystem
extends RefCounted

## How far a worker looks for MORE OF THE SAME JOB when the one it was given runs
## out, in tiles (project owner, 2026-08-22: "in general increase scan for same work
## to 10 tiles"). Shared by `BuildSystem` and `GatherSystem` so the two cannot drift.
##
## THIS REVERSES AN EARLIER CALL, deliberately, and the earlier reasoning is worth
## keeping because it was not wrong -- it was answering a different question.
## `GatherSystem.RESCAN_RADIUS` was 1, a 3x3 ring, and its note argued the tightness
## was the point: a worker should carry on with the wood it was already standing in
## rather than set off across the map on an order the player did not give.
##
## What that missed is the case where the player DID give the order and it covered
## more ground than three tiles. A wall drag lays a dozen foundations at once and
## spreads the builders round-robin across them; at radius 1 a villager who finished
## one segment could not see the next one, so it stood there while eleven foundations
## went untouched. That is the report this constant comes from, and the same
## reasoning applies to a villager working a forest wider than its own 3x3.
##
## NOT the combat re-acquire (`CombatSystem.REACQUIRE_RADIUS`, still 2). That one
## looks for the next thing to HIT, and its note rules out exactly this: an aggro
## range that pulls a unit across the map is a different feature from finishing what
## is in front of you, and ten tiles of it would have every soldier in a battle
## wandering off after its own target.
const SAME_WORK_RADIUS := 10


## A worker that is no longer standing at its work: WALK BACK, rather than retire.
## True when it has been sent back and the caller should return; false when it is
## genuinely out of reach and retiring is right.
##
## THE BUG THIS FIXES (project owner, 2026-08-28): *"villager push each other out of
## the way, when they are pushed too far from build site for mining rock or tree for
## chopping it stops their work and leaves them idle."* Three systems each read
## "not adjacent to my work" as "the order cannot be honoured" and called `stop()` --
## `BuildSystem._process`, `GatherSystem._process_gather` and `_process_return`. That
## was a fair reading when the only way to lose adjacency was a stale walk-up tile.
##
## **`SeparationSystem` IS THE OTHER WAY, and its own comment says it cannot happen.**
## `MAX_PUSH` is 120 against a 256 sub-tile, and the note there argues that "a push can
## never carry a unit out of the tile MovementSystem just placed it in" because 120 is
## inside half a tile. That is only true from the tile's CENTRE: a unit standing at
## sub-position 250 pushed +120 lands at 370, which is the next tile along. The code
## below that comment already knows -- it calls `spatial.move()` when the tile changes.
## So a villager jostled by the crowd around one rock steps off the working ring and,
## before this, downed tools.
##
## Bounded by `SAME_WORK_RADIUS`, so this only ever rescues a unit that is still at its
## job. Anything further away was moved by something other than a shove and retiring is
## the honest answer. It is also self-limiting in the way rally points are: `set_task_*`
## raises `path_pending`, every caller returns early on that, and an unreachable goal
## comes back as an empty route which `set_path` turns into `stop()`.
static func rejoin_work(w: SimWorld, u: SimUnit, rect: Rect2i, goal: Vector2i) -> bool:
	# No pathing (a bare-world unit test) means no way to walk back, so the caller
	# keeps its old behaviour rather than spinning on a task it can never satisfy.
	if w.paths == null:
		return false
	# `CombatSystem.tile_gap`, not `Occlusion.gap_to` -- the two compute the same
	# Chebyshev distance and only one of them is in the sim. `src/sim/` may not name a
	# `view/` class and `tests/sim/test_sim_boundary.gd` greps for exactly that.
	if CombatSystem.tile_gap(u.tile(), rect) > SAME_WORK_RADIUS:
		return false
	w.paths.request(u.id, goal)
	u.path_pending = true
	return true


func process_tick(_w: SimWorld) -> void:
	pass
