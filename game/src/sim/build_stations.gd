## Where each of several builders should stand to raise one building.
##
## Owner, playtest 2026-09-21: *"look at the villagers bunching up on one spot, trying to
## build the castle we need more spots where the villagers can construct it."*
##
## ## ⛔ THE BUG THIS REPLACES WAS ONE ARGUMENT, REPEATED
##
## `BuildCommand.apply()` gave **every** builder `b.tile()` — the footprint's TOP-LEFT
## tile — and asked `PathService` for a route to it. So twelve villagers sent to a castle
## were twelve units with one identical destination, and they arrived in a heap at one
## corner of a building whose perimeter is 32 tiles.
##
## ⚠️ **AND IT WAS NOT MERELY UNTIDY.** `BuildSystem` only scores progress for a villager
## that is `_adjacent_to_rect` the footprint. Measured before the fix
## (`dev_preview/preview_build_stations.tscn`): of twelve builders sent to a 7x7 castle,
## **three were not touching it** — shoved out of the huddle by `SeparationSystem` and
## standing there doing nothing. The player paid for twelve villagers and got nine.
##
## `Formation` had already written down the principle, one order over: *"two units sharing
## a destination tile is a pair that shoves each other for the rest of the match."* This is
## that sentence applied to the build order, and the shape of this file follows
## `Formation.destinations` deliberately — slots, a deterministic assignment, and unreachable
## slots left for `PathService` to degrade.
##
## ## DETERMINISM IS NOT OPTIONAL HERE
##
## This runs inside a command's `apply()`, so two hosts that assign builders differently
## **desync** (PLAN.md 7.1). Everything below is integer arithmetic over lists built in a
## fixed scan order, and the unit order is by id. Nothing iterates a Dictionary or a Set.
class_name BuildStations
extends RefCounted


## A standing position per builder, in the same order as `unit_ids`.
##
## `unit_tiles[i]` is where builder `unit_ids[i]` is now; the pairing is positional, as
## `Formation.destinations` does it.
##
## ⚠️ **NEVER RETURNS FEWER THAN IT WAS GIVEN.** A caller that got a short list back would
## have to decide what to do with the builders left over, which is exactly the decision
## that belongs here. When there are more builders than stations the ring is reused — see
## `_claim`.
static func around(rect: Rect2i, map: SimMap, unit_tiles: Array[Vector2i],
		unit_ids: Array[int]) -> Array[Vector2i]:
	var n := unit_ids.size()
	var out: Array[Vector2i] = []
	if n == 0:
		return out

	var stations := ring(rect, map)
	if stations.is_empty():
		# Walled in on every side: no legal standing position exists, so fall back to the
		# old behaviour rather than inventing one. The builders will huddle, which is
		# correct — there is nowhere else to be — and `PathService` will put them as close
		# as the ground allows.
		for i in range(n):
			out.append(rect.position)
		return out

	out.resize(n)

	# NEAREST-FIRST, IN ID ORDER. Greedy rather than optimal on purpose: the assignment
	# only has to stop them crossing over each other on the way in, and a global optimum
	# would cost a matching algorithm for a difference nobody can see. Id order is what
	# makes it reproducible on both hosts.
	var order: Array[int] = []
	for i in range(n):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return unit_ids[a] < unit_ids[b])

	var taken := {}
	for i in order:
		out[i] = _claim(stations, taken, unit_tiles[i])
	return out


## Every passable tile touching `rect`, in the fixed scan order `SimMap.find_free_adjacent`
## uses — top edge left to right, then bottom, then left, then right.
##
## ⚠️ **THE SAME RING `BuildSystem` SCORES PROGRESS ON**, which is the point: its
## `_adjacent_to_rect` is `rect.grow(1)` minus `rect`, corners included. A station outside
## that ring would be a villager standing where it cannot work, which is the bug this file
## exists to fix rather than a new way to have it.
##
## Only the FIRST ring. Widening would put builders where they cannot reach the footprint,
## unlike `find_free_adjacent`, which widens because it is answering a different question
## ("anywhere to stand") for a unit that has just been born.
static func ring(rect: Rect2i, map: SimMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var outer := rect.grow(1)
	for x in range(outer.position.x, outer.end.x):
		_add_if_passable(out, map, Vector2i(x, outer.position.y))
	for x in range(outer.position.x, outer.end.x):
		_add_if_passable(out, map, Vector2i(x, outer.end.y - 1))
	for y in range(outer.position.y + 1, outer.end.y - 1):
		_add_if_passable(out, map, Vector2i(outer.position.x, y))
	for y in range(outer.position.y + 1, outer.end.y - 1):
		_add_if_passable(out, map, Vector2i(outer.end.x - 1, y))
	return out


static func _add_if_passable(out: Array[Vector2i], map: SimMap, tile: Vector2i) -> void:
	if map != null and map.is_passable(tile, SimMap.Domain.LAND):
		out.append(tile)


## The nearest station this builder can have, preferring one nobody has claimed.
##
## ⛔ **WHEN THE RING IS FULL IT DOUBLES UP RATHER THAN REFUSING**, and that is deliberate:
## a 1x1 house offers eight stations and a player may well send twelve villagers. Refusing
## the extras would leave them idle beside a building they were told to raise — a worse bug
## than the one being fixed. Doubling up puts two on a tile, `SeparationSystem` nudges them
## apart, and both are still touching the footprint and still adding progress.
##
## The second pass picks the least-crowded station, so a heavy crowd fills the ring evenly
## instead of stacking everybody on whichever tile happens to be nearest.
static func _claim(stations: Array[Vector2i], taken: Dictionary,
		from: Vector2i) -> Vector2i:
	var best := -1
	var best_key := Vector2i(0, 0)      # (occupancy, distance), compared in that order
	for i in range(stations.size()):
		var occupancy := int(taken.get(i, 0))
		var key := Vector2i(occupancy, _dist_sq(stations[i], from))
		# Ties fall to the EARLIEST station in the scan order, because `>` is strict —
		# which is what keeps two hosts choosing the same tile for equidistant builders.
		if best < 0 or key.x < best_key.x \
				or (key.x == best_key.x and key.y < best_key.y):
			best = i
			best_key = key
	taken[best] = int(taken.get(best, 0)) + 1
	return stations[best]


## Squared tile distance. Squared because the sim carries no floats (PLAN.md 4.1's boundary
## rule, enforced by `tests/sim/test_sim_boundary.gd`) and a square root would need one —
## and because ordering by distance never needs the root anyway.
static func _dist_sq(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return d.x * d.x + d.y * d.y
