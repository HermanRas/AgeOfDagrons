## Keeps moving units from stacking on top of each other once MovementSystem has
## walked them (PLAN.md 4.2 -- "steering local avoidance", the half of 4.2 that
## was still outstanding). Full RVO is out of scope for MVP; this only pushes
## overlapping units apart by the minimum needed to stop them sharing a spot,
## which is what "walking through each other" means in practice at this scale.
##
## Runs after MovementSystem, before DeathSystem: units have already taken their
## tick's step, and this is a correction on top of it, not a second movement.
##
## ## Who yields
##
## **A unit that is standing still is not shoved by one that is walking.** Until
## 2026-08-29 every push was split evenly, so a soldier crossing the base
## barged a line of gatherers off their nodes on the way through and left them
## there -- reported by the project owner as "units path find through each other,
## pushing each other out of the way". The half of that complaint this can answer
## is the pushing: the walker owes the whole correction, because it is the one
## that chose to be there, and the stander keeps the ground it was working.
##
## The walker's correction is turned SIDEWAYS (`_sidestep`) rather than pointed
## straight back down the line between them. A head-on push is a bounce -- the
## walker is shoved back along the path it is about to re-walk, and jitters
## against whatever is in the way for as long as the order stands. A push across
## its own heading is a step around, which is what a person does and what it
## looks like it should do.
##
## Two walkers still split evenly, and so do two standers -- the latter is
## load-bearing, because a barracks emptying its queue puts several units on one
## tile and nothing else would ever separate them (`SimWorld.find_free_adjacent`
## says so in its own header).
##
## The OTHER half of the owner's report -- that a route is planned through
## whatever is standing in the way, rather than around it -- is not fixed here
## and cannot be: `AStarGrid2D` holds solidity in the grid, so units would have
## to be written into the pathing grid and it re-swept every tick. Logged in
## BUGS.md rather than half-attempted.
##
## ## Determinism
##
## Pairs are visited in a fixed order -- alive units sorted by id, then their
## spatial neighbours sorted by id, each pair resolved once from the lower id --
## so every client resolves the same overlaps in the same order and pushes land
## on the same sub-tile position (PLAN.md 7.1). The correction itself is
## IEEE-754 float arithmetic, trusted the same way PathService trusts
## AStarGrid2D (PLAN.md 4.2): identical inputs, identical rounding, on every
## platform the engine targets.
class_name SeparationSystem
extends SimSystem

## Two units nearer than this (sub-tile units) count as overlapping. Comfortably
## under a tile (SimWorld.SUBTILE = 256) so several units can still stand around
## one resource node without fighting each other for the exact same spot.
const MIN_SEPARATION := 170

## A correction is capped well inside half a tile so a push can never carry a
## unit out of the tile MovementSystem just placed it in -- TaskSystem's arrival
## check reads `tile()`, and a push that changed it would either strand a unit
## mid-MOVE or walk it through a wall the pathfinder never routed it across. The
## cap matters most when several neighbours overlap the same unit at once and
## their pushes would otherwise sum past it.
const MAX_PUSH := 120


func process_tick(w: SimWorld) -> void:
	var ids := w.entities.keys()
	ids.sort()

	var units: Array[SimUnit] = []
	for id in ids:
		var e: SimEntity = w.entities[id]
		# A GARRISONED UNIT IS NOT ON THE MAP (4.8) and must not push anything. Its
		# `pos` is wherever it stood when it walked inside, possibly minutes ago and
		# possibly under somebody's house by now, and `SimUnit.garrisoned_in`'s header
		# is explicit that nothing reads it while this is set. It is not in the spatial
		# hash either, so it was never found as a NEIGHBOUR -- but it was still swept
		# up as an `a` here, and shoved whoever happened to be standing on its ghost.
		if e is SimUnit and e.alive and (e as SimUnit).garrisoned_in == 0:
			units.append(e)

	if units.size() < 2:
		return

	var corrections: Dictionary = {}          # int id -> Vector2 accumulator
	for a in units:
		var neighbour_ids := w.spatial.query_rect(Rect2i(a.tile() - Vector2i.ONE, Vector2i(3, 3)))
		neighbour_ids.sort()
		for nid in neighbour_ids:
			if nid <= a.id:
				continue                      # each pair resolved once, from the lower id
			var b := w.get_entity(nid) as SimUnit
			# `garrisoned_in` again, for the same reason and belt-and-braces: garrison
			# takes a unit OUT of the spatial hash, so this should be unreachable, and
			# stating it here means the invariant does not rely on another system
			# remembering to.
			if b == null or not b.alive or b.garrisoned_in != 0:
				continue
			_resolve_pair(a, b, corrections)

	for id in corrections:
		_apply(w, w.get_entity(id) as SimUnit, corrections[id])


## Half the overlap to each side, so applying both halves resolves the whole
## thing in one tick rather than only starting to -- unless exactly one of the two
## is walking, in which case that one owes the whole of it and the other is left
## where it stands. See the "Who yields" note in the header.
func _resolve_pair(a: SimUnit, b: SimUnit, corrections: Dictionary) -> void:
	var delta := Vector2(b.pos - a.pos)
	var dist := delta.length()
	if dist > 0.001 and dist >= MIN_SEPARATION:
		return

	var dir: Vector2
	var overlap: float
	if dist <= 0.001:
		# Exactly coincident: nothing to normalise. The tie is broken on id
		# parity rather than direction, which lands on the same axis on every
		# client anyway but would otherwise read as an arbitrary choice.
		dir = Vector2.RIGHT if b.id % 2 == 0 else Vector2.UP
		overlap = float(MIN_SEPARATION)
	else:
		dir = delta / dist
		overlap = float(MIN_SEPARATION) - dist

	var a_walks := _is_walking(a)
	if a_walks != _is_walking(b):
		var mover := a if a_walks else b
		# Whichever way open ground lies from the mover: `dir` runs a -> b, so it
		# points AT b, and away from the mover is the one of the two that is not
		# toward the other unit.
		var away := -dir if a_walks else dir
		# CAPPED AT THE MOVER'S OWN SPEED, which is the whole difference between a
		# nudge and a shove. A villager covers ~26 sub-units in a tick and the raw
		# overlap runs to MIN_SEPARATION, so an uncapped correction outweighs the
		# step MovementSystem just took by five to one: the unit was thrown clear,
		# spent the next several ticks walking back to the line it was thrown off,
		# and got thrown again -- forward progress zero, for as long as the order
		# stood. Measured, not guessed: three tests deadlocked on exactly this.
		var reach := minf(overlap, float(mover.speed))
		var step := _sidestep(mover, away) * reach
		corrections[mover.id] = corrections.get(mover.id, Vector2.ZERO) + step
		return

	var push := dir * (overlap * 0.5)
	corrections[a.id] = corrections.get(a.id, Vector2.ZERO) - push
	corrections[b.id] = corrections.get(b.id, Vector2.ZERO) + push


## Is this unit COVERING GROUND right now -- not "was it ordered somewhere".
##
## `path_pending` is deliberately not walking. A unit waiting on a budgeted search
## (PathService.MAX_SOLVES_PER_TICK) is standing perfectly still for those few
## ticks, and a passer-by that shoved it because an order had landed but its route
## had not would be the same bug in a form that only shows up under load.
##
## Nor is a route at speed 0. A siege engine mid-pack (4.13) keeps whatever route it
## had while `SiegeSystem` holds its speed at zero, and it is standing exactly as
## still as anything else that is not moving -- it also has no `speed` to scale a
## sidestep by, so calling it a walker would leave it overlapping forever.
static func _is_walking(u: SimUnit) -> bool:
	return u.speed > 0 and u.has_waypoint()


## A unit-length push ACROSS the mover's heading, on whichever side the other unit
## is not. Falls back to straight-away when there is no heading to be across --
## which `_is_walking` makes impossible in practice, and which is here so the
## geometry below never divides by zero if that ever stops being true.
static func _sidestep(mover: SimUnit, away: Vector2) -> Vector2:
	var heading := Vector2(mover.waypoint_subpos() - mover.pos)
	if heading.length() <= 0.001:
		return away
	var side := heading.normalized().orthogonal()
	var lean := side.dot(away)
	if absf(lean) <= 0.001:
		# Dead ahead: the two sides are equally good, so the tie goes on id parity
		# for the same reason the coincident case above does -- an arbitrary choice
		# that has to be the SAME arbitrary choice on every client (PLAN.md 7.1).
		return side if mover.id % 2 == 0 else -side
	return side if lean > 0.0 else -side


func _apply(w: SimWorld, u: SimUnit, correction: Vector2) -> void:
	if u == null:
		return
	if correction.length() > MAX_PUSH:
		correction = correction.normalized() * MAX_PUSH
	var delta := Vector2i(roundi(correction.x), roundi(correction.y))
	if delta == Vector2i.ZERO:
		return

	var new_pos := u.pos + delta
	var new_tile := new_pos / SimWorld.SUBTILE
	if not w.map.is_passable(new_tile, u.domain):
		return                                 # would shove the unit into an obstacle

	var old_tile := u.tile()
	u.pos = new_pos
	if new_tile != old_tile:
		w.spatial.move(u.id, new_tile)
