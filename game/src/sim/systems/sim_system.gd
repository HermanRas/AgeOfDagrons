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


func process_tick(_w: SimWorld) -> void:
	pass
