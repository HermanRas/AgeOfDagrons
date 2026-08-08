## Keeps moving units from stacking on top of each other once MovementSystem has
## walked them (PLAN.md 4.2 -- "steering local avoidance", the half of 4.2 that
## was still outstanding). Full RVO is out of scope for MVP; this only pushes
## overlapping units apart by the minimum needed to stop them sharing a spot,
## which is what "walking through each other" means in practice at this scale.
##
## Runs after MovementSystem, before DeathSystem: units have already taken their
## tick's step, and this is a correction on top of it, not a second movement.
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
		if e is SimUnit and e.alive:
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
			if b == null or not b.alive:
				continue
			_resolve_pair(a, b, corrections)

	for id in corrections:
		_apply(w, w.get_entity(id) as SimUnit, corrections[id])


## Half the overlap to each side, so applying both halves resolves the whole
## thing in one tick rather than only starting to.
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

	var push := dir * (overlap * 0.5)
	corrections[a.id] = corrections.get(a.id, Vector2.ZERO) - push
	corrections[b.id] = corrections.get(b.id, Vector2.ZERO) + push


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
