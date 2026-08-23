## Grid pathfinding for the sim (PLAN.md 4.2). Phase 4.2.
##
## Wraps `AStarGrid2D` rather than hand-rolling A*: it is engine C++ over a dense
## grid, which is exactly the shape of this problem, and it keeps the search out of
## GDScript where 200 units re-planning would be the whole tick budget.
##
## **Requests are queued and solved against a per-tick budget, not immediately.**
## Ordering 200 units at once is one command, but it is 200 searches, and doing
## them in the tick the order lands is precisely the spike the 0.7 harness already
## shows against the < 5 ms budget. Spreading them costs a few ticks of reaction
## time on the largest orders and nothing at all on ordinary ones.
##
## ## Determinism
##
## Paths feed unit positions, so two clients that pathed differently would desync
## (PLAN.md 7.1). Three things keep this reproducible:
##
##   1. The queue is FIFO over an Array, never a Dictionary iteration.
##   2. The budget is a fixed count, so the same requests are solved on the same
##      ticks on every client.
##   3. `AStarGrid2D` itself is deterministic for identical input -- its costs use
##      only IEEE-754 add/multiply/sqrt, which are correctly rounded and so
##      identical across platforms, and its tie-breaking follows insertion order
##      over a grid built in a fixed sweep.
##
## Point 3 is the one taken on trust rather than enforced here, and it is the
## reason the engine version is pinned (PLAN.md 1.3). test_path_service.gd asserts
## that two services built from the same map return byte-identical paths, which
## catches a same-machine regression; a cross-platform divergence would need two
## machines and is what the 0.7 desync check exists for.
class_name PathService
extends RefCounted

## Searches solved per tick. Chosen against the < 5 ms tick budget (PLAN.md 3.1)
## by measurement, on the 0.7 harness's worst case -- 200 units all re-planning in
## the same frame:
##
##   budget 32   max tick 9.48 ms   over
##   budget 16   max tick 5.09 ms   over, but only just
##   budget 12   max tick 4.30 ms   inside, with headroom
##
## An ordinary order of a dozen units therefore plans within a single tick and
## feels instant; only a whole-army order pays the drip, and it pays it in reaction
## time rather than in a dropped frame.
const MAX_SOLVES_PER_TICK := 12

## How far to look for a substitute when the target itself cannot be stood on
## (PLAN.md 4.1, "stop at nearest reachable tile"). Bounded because an order into
## the middle of a lake should give up, not scan the map.
const MAX_SUBSTITUTE_RINGS := 8

## ONE GRID PER DOMAIN, keyed by `SimMap.Domain` (2026-08-23).
##
## It was a single land-only grid, and the note where `_walkable` used to hard-code
## `Domain.LAND` said why: "MVP units are all land, and a second domain wants its own
## grid rather than a per-query filter -- AStarGrid2D holds solidity IN THE GRID, not in
## the query." That is still the reason it has to be a second grid and not a flag; what
## changed is that the premise stopped being true. Fishing arrived, and a water unit
## routed against the land grid sails happily across a beach -- reported by the project
## owner as "boats spawn and sail on land, its very funny".
##
## Built lazily, because most maps never float anything: a desert start pays for exactly
## one grid. `rebuild()` pre-builds the water one when the map has water in it, so the
## full sweep lands in load time rather than as a hitch on the first ship order.
var _grids: Dictionary = {}

## Rebuild bookkeeping. A full sweep of a 64x64 map is 4096 `set_point_solid()`
## calls and measured at ~12 ms on desktop -- five times the per-tick sim budget on
## its own, and it would recur every time a building went up. So the normal case is
## a list of changed rects, and the full sweep happens only when there is no grid
## yet or the map changed size.
var _needs_full := true
var _dirty_rects: Array[Rect2i] = []

## unit id -> destination tile, plus a FIFO of ids. Two structures rather than one
## so that re-ordering a unit already queued REPLACES its destination instead of
## adding a second request, without disturbing its place in the queue. A player
## dragging a move order around would otherwise queue one search per frame.
var _wanted: Dictionary = {}
var _order: Array[int] = []


## Some tiles no longer match the map. Deferred to the next solve, so placing ten
## buildings in one tick costs one update rather than ten.
##
## `rect` is the area that changed; an empty rect means "everything", which forces
## the expensive full sweep. Callers that know what they touched should say so --
## a building footprint is 64 cells against the map's 4096.
func mark_dirty(rect: Rect2i = Rect2i()) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		_needs_full = true
	else:
		_dirty_rects.append(rect)


## Build the grid now, rather than on the first search.
##
## For use once the map is finished being generated (2.4a): the full sweep has to
## happen sometime, and paying it during setup hides it in load time instead of
## spending it on the player's first move order.
func rebuild(map: SimMap) -> void:
	_needs_full = true
	# Land always; water only where there is any, so a land map never pays for a grid
	# nothing will ever route against.
	_grid_for(SimMap.Domain.LAND)
	if _map_has_water(map):
		_grid_for(SimMap.Domain.WATER)
	_sync(map)


## Whether anything on this map floats a ship. One sweep, at load time, to decide
## whether the water grid is worth building at all.
static func _map_has_water(map: SimMap) -> bool:
	for i in range(map.terrain.size()):
		var t := map.terrain[i]
		if t == SimMap.Terrain.WATER_SHALLOW or t == SimMap.Terrain.WATER_DEEP:
			return true
	return false


func queued() -> int:
	return _order.size()


## Ask for a path for `unit_id`. Solved on this tick or a later one, depending on
## how many others are already waiting.
func request(unit_id: int, to: Vector2i) -> void:
	if not _wanted.has(unit_id):
		_order.append(unit_id)
	_wanted[unit_id] = to


func cancel(unit_id: int) -> void:
	if _wanted.erase(unit_id):
		_order.erase(unit_id)


## Solve up to `budget` queued requests, writing each result onto its unit.
func process(w: SimWorld, budget: int = MAX_SOLVES_PER_TICK) -> void:
	if _order.is_empty():
		return
	_sync(w.map)

	var solved := 0
	while solved < budget and not _order.is_empty():
		var id: int = _order.pop_front()
		var to: Vector2i = _wanted.get(id, Vector2i.ZERO)
		_wanted.erase(id)
		solved += 1

		var u := w.get_entity(id) as SimUnit
		# Died, or was re-tasked to something that does not walk anywhere, while
		# queued.
		if u == null or not u.alive or not u.is_travel_task():
			continue

		# ALREADY THERE IS NOT NOWHERE TO GO, and `find_path` answers both with an
		# empty route -- which `set_path()` turns into `stop()`. So a unit standing
		# on the exact tile its new order would have walked it to was RETIRED
		# instead of getting on with the job: the builder never built, the gatherer
		# never gathered, and nothing said why.
		#
		# Rare until 2026-08-20, when `_evict_from_footprint` began stepping units
		# out of new footprints to `find_free_adjacent` -- the same "nearest free
		# tile just outside" that `_nearest_walkable` then chose as the goal. Every
		# evicted builder was therefore retired on the spot, and the AI's opening
		# lost its mining camp and lumber camp to it.
		var route := find_path(w.map, u.tile(), to, u.domain)
		if route.is_empty() and goal_for(w.map, to, u.domain) == u.tile():
			u.arrive()
		else:
			u.set_path(route)


## A tile path from `from` to `to`, or as near to `to` as can be stood on.
##
## The returned path EXCLUDES the starting tile, so an empty result means "nowhere
## to go" rather than "already there" -- callers do not have to special-case the
## first waypoint being the tile the unit is standing on.
## `domain` defaults to LAND, which is what every caller but a ship wants and what
## every existing one passed implicitly before there was a choice.
func find_path(map: SimMap, from: Vector2i, to: Vector2i,
		domain: int = SimMap.Domain.LAND) -> PackedVector2Array:
	var grid := _grid_for(domain)
	_sync(map)
	if not map.in_bounds(from) or not map.in_bounds(to):
		return PackedVector2Array()

	var goal := goal_for(map, to, domain)
	if goal.x < 0 or goal == from:
		return PackedVector2Array()

	var path := grid.get_id_path(from, goal)
	# AStarGrid2D includes the starting cell; the unit is already standing there.
	if path.size() > 0:
		path.remove_at(0)
	return path


## The tile a route to `to` would actually END at: `to` itself when it can be stood
## on, else the nearest tile that can (PLAN.md 4.1). (-1, -1) when there is none.
##
## Shared by `find_path` and by `process`, which needs to tell "there is no route"
## apart from "you are standing on it" -- two answers that were the same empty array
## and are not the same thing at all.
func goal_for(map: SimMap, to: Vector2i, domain: int = SimMap.Domain.LAND) -> Vector2i:
	if not map.in_bounds(to):
		return Vector2i(-1, -1)
	return to if _walkable(map, to, domain) else _nearest_walkable(map, to, domain)


## The closest tile to `t` that a unit could stand on, or (-1, -1).
##
## Rings are scanned in a fixed order -- and the whole ring is scanned rather than
## returning on the first hit -- so that "nearest" is decided by distance and then
## by a stable sweep, never by which direction the loop happened to run. Two
## clients picking different substitute tiles for the same blocked order is a
## desync in the shape of a unit standing on the wrong side of a tree.
func _nearest_walkable(map: SimMap, t: Vector2i,
		domain: int = SimMap.Domain.LAND) -> Vector2i:
	var best := Vector2i(-1, -1)
	for ring in range(1, MAX_SUBSTITUTE_RINGS + 1):
		var best_d := -1
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue                 # interior, covered by a smaller ring
				var c := t + Vector2i(dx, dy)
				if not _walkable(map, c, domain):
					continue
				var d := dx * dx + dy * dy
				if best_d < 0 or d < best_d:
					best_d = d
					best = c
		if best_d >= 0:
			return best
	return best


func _walkable(map: SimMap, t: Vector2i, domain: int = SimMap.Domain.LAND) -> bool:
	return map.is_passable(t, domain)


## The grid for `domain`, built on first use. A map with no water never builds a water
## grid; asking for one is what creates it, and it arrives already synced because the
## caller runs `_sync` immediately afterwards.
func _grid_for(domain: int) -> AStarGrid2D:
	if _grids.has(domain):
		return _grids[domain]
	var grid := AStarGrid2D.new()
	_grids[domain] = grid
	# A grid that has never been swept is not usable, and `_sync` only re-sweeps what
	# is dirty -- so a grid created after the last full sweep would be all-passable and
	# route a ship straight across the land it was built to keep it off.
	_needs_full = true
	return grid


## Bring the grid back in line with the map, doing the least work that will do it.
##
## Land-only, single grid. MVP units are all land (PLAN.md 2.2), and a second
## domain wants its own grid rather than a per-query filter -- `AStarGrid2D` holds
## solidity in the grid, not in the query.
## EVERY grid, not just one. A building going up blocks the land grid and leaves the
## water grid alone, but a `mark_dirty` cannot know which -- so both are re-read and
## each answers for its own domain. The cost is per grid that EXISTS, and a land-only
## map only ever has one.
func _sync(map: SimMap) -> void:
	var resized := false
	for domain in _grids:
		var g: AStarGrid2D = _grids[domain]
		if g.region.size != map.size:
			resized = true
	if _needs_full or resized:
		_full_sync(map)
		return

	for rect in _dirty_rects:
		for domain in _grids:
			_sync_rect(map, rect, int(domain))
	_dirty_rects.clear()


func _full_sync(map: SimMap) -> void:
	# There is always a land grid, so a service asked for a path before anything called
	# `rebuild` still has one to answer with.
	_grid_for(SimMap.Domain.LAND)
	for domain in _grids:
		var grid: AStarGrid2D = _grids[domain]
		grid.region = Rect2i(Vector2i.ZERO, map.size)
		grid.cell_size = Vector2.ONE
		# Corners are not cut past a blocked tile: a villager must not slip diagonally
		# between two buildings that touch, which looks like walking through a wall.
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
		_sync_rect(map, Rect2i(Vector2i.ZERO, map.size), int(domain))

	_needs_full = false
	_dirty_rects.clear()


## Re-read solidity for one area of one domain's grid, clipped to the map so a caller
## may pass a rect grown past the edge without checking.
func _sync_rect(map: SimMap, rect: Rect2i, domain: int) -> void:
	var grid: AStarGrid2D = _grids[domain]
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var t := Vector2i(x, y)
			grid.set_point_solid(t, not _walkable(map, t, domain))
