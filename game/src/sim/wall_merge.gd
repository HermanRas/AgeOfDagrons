## Short wall segments that finish next to each other become one longer segment
## (project owner, 2026-08-22). PLAN.md 5.8.
##
## WHY, and it is not tidiness. A player who walls a gap three tiles at a time ends up
## with a row of short pieces where a single drag would have laid long ones -- same
## wall, same ground, same cost, but three times the entities, three times the seams
## an attacker can pick at, three vision circles, and three entries in every snapshot
## for as long as the match lasts. `WallPlan` already fills a single drag
## longest-first for exactly those reasons; this is the same rule applied to walls
## that were built up over several drags, which is how walls actually get built.
##
## ONLY COMPLETE PIECES MERGE (project owner's call, and it settles a real hazard):
## absorbing a foundation would delete the thing a villager is walking to, and the
## builder would arrive at a wall that is already finished and go looking for other
## work. So a piece under construction is a wall of its own until the tick it is
## finished -- which is also the tick it gets its chance to be merged.
##
## SILENT, and no cost either way. Nothing is announced, nothing is refunded, nothing
## is charged: the wall the player paid for is still standing on the ground they put
## it on, and a toast for "your wall is now one piece" would be noise about an
## improvement they did not ask for and cannot decline.
##
## Its own class rather than more of `WallPlan`, because it answers the opposite
## question. `WallPlan` turns a drag into pieces and knows nothing about the world;
## this reads standing buildings and decides which of them are one wall. Both are
## integer arithmetic over tiles, so both belong on the sim side of PLAN.md 4.
class_name WallMerge
extends RefCounted


## What merging `b` into its neighbours would produce, or `{}` for the ordinary case
## where nothing should happen.
##
## `{def_id, origin, footprint, hp, survivor_id, absorbed}` -- `absorbed` being the
## ids that go away, never including the survivor.
##
## THE SURVIVOR IS THE PIECE AT THE LOW END of the run, not `b` itself. The merged
## wall starts where that piece already starts, so the survivor keeps its origin and
## only grows; picking `b` would mean moving a building's corner backwards over ground
## another entity still holds this instant. It also makes the outcome independent of
## which piece happened to be finished last, which is what stops two hosts that
## completed the same wall in a different order from producing different entities.
static func plan(w: SimWorld, b: SimBuilding) -> Dictionary:
	var tier := _tier_of(w, b)
	if tier == null:
		return {}
	var axis := _axis_of(b)
	if axis < 0:
		return {}

	# Every mergeable piece touching `b`, in order along the axis. `b` is in it by
	# construction, so an isolated segment gives a run of one and falls out below.
	var run := _run_through(w, b, tier, axis)
	if run.size() < 2:
		return {}

	var lengths := WallPlan.lengths_of(tier.wall_lengths, w.building_def)
	var choice := _best_span(run, lengths, _index_of(run, b.id))
	if choice.is_empty():
		return {}

	var first: SimBuilding = run[int(choice["from"])]
	var absorbed: Array[int] = []
	var hp := 0
	for i in range(int(choice["from"]), int(choice["to"]) + 1):
		var piece: SimBuilding = run[i]
		hp += piece.hp
		if piece.id != first.id:
			absorbed.append(piece.id)

	var length := int(choice["length"])
	return {
		"def_id": lengths[length] as StringName,
		"origin": first.origin_tile(),
		"footprint": WallPlan.footprint_for(length, axis),
		# THE SUM, not the fraction (project owner's default, taken). Wall health is
		# authored strictly per tile -- 400 for three tiles, 800 for six, 1200 for nine
		# (buildings.json) -- so three undamaged shorts add up to exactly one undamaged
		# long, and a merged wall is neither repaired nor weakened by the merge. Clamped
		# to the new maximum inside `convert_building`, which only bites if that
		# proportion is ever broken.
		"hp": hp,
		"survivor_id": first.id,
		"absorbed": absorbed,
	}


## Merge if there is anything to merge, and report whether one happened.
##
## The absorbed pieces are `despawn`ed, which is the SILENT removal: it frees their
## ground, files them under `removed_this_tick` so every client drops the view node,
## and -- unlike the destruction path (5.5) -- leaves no rubble, plays nothing and
## tells no win condition that a building was lost.
static func apply(w: SimWorld, b: SimBuilding) -> bool:
	var merge := plan(w, b)
	if merge.is_empty():
		return false

	var survivor := w.get_entity(int(merge["survivor_id"])) as SimBuilding
	if survivor == null:
		return false
	# Absorbed first, so the survivor's own claim is the last one written over the
	# tiles: the other order leaves whichever piece was cleared last holding ground
	# the merged wall has already been given.
	for id in merge["absorbed"]:
		w.despawn(int(id))
	w.convert_building(survivor, merge["def_id"], merge["footprint"], int(merge["hp"]))
	return true


## The tier `b` belongs to, or null if it is not a mergeable wall piece at all.
##
## A GATE IS NEVER MERGED, and it falls out of the data rather than being tested for:
## no tier's `wall_lengths` names a gate, because a gate is an upgrade of the long
## piece and not a length a drag can lay, so `wall_tier()` does not resolve one.
## Merging a gate away would take a player's door out of their own wall.
static func _tier_of(w: SimWorld, b: SimBuilding) -> BuildingDef:
	if b == null or not b.alive or not b.is_complete():
		return null
	return w.wall_tier(b.def_id)


## `WallPlan.AXIS_X` / `AXIS_Y` from the footprint, or -1 if this is not shaped like
## a wall segment. Read off the FOOTPRINT rather than `facing`, because the footprint
## is what decides which way the pieces have to line up, and the shortest segment is
## three tiles long so `[3, 2]` and `[2, 3]` can never be confused.
static func _axis_of(b: SimBuilding) -> int:
	if b.footprint.y == WallPlan.DEPTH and b.footprint.x > WallPlan.DEPTH:
		return WallPlan.AXIS_X
	if b.footprint.x == WallPlan.DEPTH and b.footprint.y > WallPlan.DEPTH:
		return WallPlan.AXIS_Y
	return -1


## The unbroken line of mergeable pieces that `b` is part of, ordered along `axis`.
##
## Walked outwards from `b` through the OCCUPANCY GRID -- the tile immediately past
## each end names whatever holds it -- rather than by scanning every building in the
## world. The grid already answers "what is on this tile" in constant time, and asking
## it is what makes the walk stop at the first gap instead of collecting a piece
## thirty tiles away that happens to be collinear.
static func _run_through(w: SimWorld, b: SimBuilding, tier: BuildingDef,
		axis: int) -> Array[SimBuilding]:
	var run: Array[SimBuilding] = [b]
	var step := Vector2i(1, 0) if axis == WallPlan.AXIS_X else Vector2i(0, 1)

	# Backwards from the low corner, then forwards from the high one. The
	# already-in-the-run guard is not defensive about geometry that can happen -- it is
	# there because the alternative to a wrong answer would be a loop that never ends,
	# inside a tick, with no way out of it.
	var seen: Dictionary = {b.id: true}
	var at := run[0].origin_tile() - step
	while true:
		var prev := _mergeable_at(w, at, tier, axis, b)
		if prev == null or seen.has(prev.id):
			break
		seen[prev.id] = true
		run.insert(0, prev)
		at = prev.origin_tile() - step

	var last := run[run.size() - 1]
	at = last.origin_tile() + step * _length_of(last, axis)
	while true:
		var next := _mergeable_at(w, at, tier, axis, b)
		if next == null or seen.has(next.id):
			break
		seen[next.id] = true
		run.append(next)
		at = next.origin_tile() + step * _length_of(next, axis)
	return run


## The building on `tile`, if it is a piece of the same wall as `like` -- same owner,
## same tier, same axis, finished, and lying on the same LINE rather than merely
## touching. The line test is what refuses a T junction: a north-south wall abutting
## an east-west one shares tiles with it and is not part of it.
static func _mergeable_at(w: SimWorld, tile: Vector2i, tier: BuildingDef, axis: int,
		like: SimBuilding) -> SimBuilding:
	if w.map == null or not w.map.in_bounds(tile):
		return null
	var e := w.get_entity(w.map.occupant(tile))
	if e == null or not (e is SimBuilding):
		return null
	var other: SimBuilding = e
	if other.owner_id != like.owner_id:
		return null
	# By ID, not by object: a def is a shared cached instance today and comparing the
	# references happens to work, which is exactly the kind of thing that stops being
	# true the day the registry hands out copies.
	var other_tier := _tier_of(w, other)
	if other_tier == null or other_tier.id != tier.id or _axis_of(other) != axis:
		return null
	var origin := other.origin_tile()
	var mine := like.origin_tile()
	var same_line := origin.y == mine.y if axis == WallPlan.AXIS_X else origin.x == mine.x
	return other if same_line else null


static func _length_of(b: SimBuilding, axis: int) -> int:
	return b.footprint.x if axis == WallPlan.AXIS_X else b.footprint.y


static func _index_of(run: Array[SimBuilding], id: int) -> int:
	for i in range(run.size()):
		if run[i].id == id:
			return i
	return -1


## The best contiguous stretch of `run` that INCLUDES the piece at `must_include` and
## whose lengths add up to exactly one of the tier's own lengths.
##
## `{from, to, length}`, or `{}` when no stretch does. Two or more pieces always, so
## a segment that already matches a declared length on its own is not "merged" with
## itself.
##
## Longest first, then leftmost, and the tie-break matters: a run of six shorts
## contains four different stretches of three, and a rule that picked whichever the
## scan reached first would depend on which end the walk in `_run_through` started
## from. Longest-first for the same reason `WallPlan` fills longest-first -- fewer
## pieces is the whole point -- and it is why merging six shorts gives long + short
## rather than two mediums: the long is taken first and the leftover is the remainder,
## exactly as a single drag of eighteen tiles would have laid it.
##
## `must_include` is what keeps this local. The completed piece has to be in the
## stretch, so finishing one segment can never silently rearrange a wall further along
## that the player has not touched.
static func _best_span(run: Array[SimBuilding], lengths: Dictionary,
		must_include: int) -> Dictionary:
	if must_include < 0 or lengths.is_empty():
		return {}
	var axis := _axis_of(run[0])
	var best: Dictionary = {}

	for from in range(run.size()):
		var total := 0
		for to in range(from, run.size()):
			total += _length_of(run[to], axis)
			if to == from or from > must_include or to < must_include:
				continue
			if not lengths.has(total):
				continue
			if best.is_empty() or total > int(best["length"]):
				best = {"from": from, "to": to, "length": total}
	return best
