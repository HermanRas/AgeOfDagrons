## The tile grid: terrain, movement cost, occupancy, passability (PLAN.md 6.2).
## Phase 2.1.
##
## Plain RefCounted with flat packed arrays, no Node and no TileMap -- this is
## simulation state, not rendering (PLAN.md 4). The view layer builds its own
## TileMapLayer from this at 3.1; the two never share an object.
##
## Three parallel arrays, one entry per tile, indexed row-major by `_index()`:
##
##   terrain    what the tile is                      -> Terrain
##   move_cost  what it costs to cross, 255 = never   -> for A* at 4.2
##   occupancy  which entity's footprint sits here    -> entity id, 0 = free
##
## Packed arrays rather than an Array of tile objects because a 128x128 map is
## 16384 tiles and this is read every pathfinding query: PackedByteArray is one
## contiguous allocation, and `state_hash()` can fold the whole grid in one call.
##
## **Occupancy is for STATIC footprints only** -- buildings and resource nodes
## (2.3). Units are never written into it; they live in SpatialHash. That split is
## deliberate: if units occupied tiles, every step would have to rewrite the grid
## and a tile a unit merely walks across would read as unpathable. So an occupied
## tile means "something is permanently in the way", which is exactly the question
## pathfinding and building placement both ask.
class_name SimMap
extends RefCounted

enum Terrain { GRASS, DIRT, SAND, WATER_SHALLOW, WATER_DEEP, ROCK, FOREST }

## Which surfaces a unit can cross. `UnitDef.domain` is the string form
## ("land"); `from_domain_name()` converts.
##
## ⚠️ **DECLARING A DOMAIN IS NOT THE SAME AS IMPLEMENTING IT, and AIR proved that.** All
## three rows sat in `DOMAIN_TERRAIN` from 2.2 on the reasoning that `is_passable()` would
## then be extended rather than rewritten — and the table was still wrong for AIR for months,
## because the two functions below tested `move_cost` and `occupancy` before ever reaching
## the domain. Nothing caught it: the only air unit had `speed: 0`, so no path was ever asked
## for. Both are fixed and both carry a test. **A declared-but-unexercised row in a table is
## indistinguishable from a working one.**
enum Domain { LAND, WATER, AIR }

## Impassable to every domain -- a cliff, not a preference. Distinct from a
## domain rule: ROCK is 255 because nothing crosses it, whereas deep water is
## cheap for a boat and forbidden for a villager, which is a domain question.
const IMPASSABLE := 255

## Base cost per terrain, on a scale where flat ground is 10. Not 1, so that
## slower-but-passable ground can be expressed in integers without fractions --
## sand at 12 is 20% slower, and the sim stays entirely on ints (determinism,
## PLAN.md 7.1).
const TERRAIN_COST := {
	Terrain.GRASS: 10,
	Terrain.DIRT: 10,
	Terrain.SAND: 12,
	Terrain.WATER_SHALLOW: 14,
	Terrain.WATER_DEEP: 10,
	Terrain.ROCK: IMPASSABLE,
	Terrain.FOREST: IMPASSABLE,
}

## Terrain each domain may enter. FOREST and ROCK are absent from LAND and WATER
## on purpose -- a forest tile is a tree's footprint, not walkable ground, and the
## trees standing on it are separate entities placed at 6.3.
const DOMAIN_TERRAIN := {
	Domain.LAND: [Terrain.GRASS, Terrain.DIRT, Terrain.SAND],
	Domain.WATER: [Terrain.WATER_SHALLOW, Terrain.WATER_DEEP],
	Domain.AIR: [
		Terrain.GRASS, Terrain.DIRT, Terrain.SAND,
		Terrain.WATER_SHALLOW, Terrain.WATER_DEEP, Terrain.ROCK, Terrain.FOREST,
	],
}

var size: Vector2i = Vector2i.ZERO
var terrain: PackedByteArray = PackedByteArray()
var move_cost: PackedByteArray = PackedByteArray()
var occupancy: PackedInt32Array = PackedInt32Array()

## 1 where the tile's occupant also BLOCKS MOVEMENT, 0 where it merely holds the
## ground. Parallel to `occupancy` and meaningless where that is 0.
##
## Two different questions were one array until 2026-08-17, and a field is what
## separated them: "may something else be built here" and "may a unit walk here"
## are not the same. A field claims its 36 tiles so nothing is built on top of the
## crop, and lets villagers walk over it -- without which a 6x6 plot flush against
## a 5x4 mill leaves no ground to stand on to drop food off, and no way onto the
## plot to work it (project owner, 2026-08-17, with the screenshot to prove it).
var blocking: PackedByteArray = PackedByteArray()


## A fresh map of uniform terrain. The real MVP map is built by 2.4a on top of
## this; a procedural generator is 2.4b.
static func create(p_size: Vector2i, fill: Terrain = Terrain.GRASS) -> SimMap:
	var m := SimMap.new()
	m.size = p_size
	var count := maxi(0, p_size.x * p_size.y)
	m.terrain.resize(count)
	m.move_cost.resize(count)
	m.occupancy.resize(count)
	m.blocking.resize(count)
	m.fill_terrain(fill)
	return m


static func from_domain_name(name: StringName) -> Domain:
	match name:
		&"water":
			return Domain.WATER
		&"air":
			return Domain.AIR
		_:
			return Domain.LAND


# ── queries ────────────────────────────────────────────────────────────────

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < size.x and t.y < size.y


func terrain_at(t: Vector2i) -> Terrain:
	if not in_bounds(t):
		return Terrain.ROCK       # out of bounds behaves like a wall, not like grass
	return terrain[_index(t)] as Terrain


func cost_at(t: Vector2i) -> int:
	if not in_bounds(t):
		return IMPASSABLE
	return move_cost[_index(t)]


func occupant(t: Vector2i) -> int:
	if not in_bounds(t):
		return 0
	return occupancy[_index(t)]


## Row-major index of `t`, or -1 out of bounds.
##
## Public because the fog of war (2.5) keeps its own parallel array per player
## (`SimPlayer.vision`) rather than a fourth array here: vision is per PLAYER and
## these three are per MAP, and eight copies of the grid do not belong on the
## object that has exactly one of everything else. The indexing has to be shared
## though, or two row-major strides would eventually disagree about which tile is
## which -- which is a fog bug that looks like a rendering bug.
func index_of(t: Vector2i) -> int:
	return _index(t) if in_bounds(t) else -1


## Can `domain` stand on this tile right now: in bounds, crossable terrain for
## that domain, not blocked outright, and nothing BLOCKING already there.
##
## A non-blocking occupant -- a field -- is walked over, so this stays true while
## `occupant()` reports its id. That is the whole distinction the `blocking` array
## exists for; see `is_buildable()` for the other half.
func is_passable(t: Vector2i, domain: int = Domain.LAND) -> bool:
	if not is_terrain_passable(t, domain):
		return false
	# AIR IGNORES OCCUPANCY, which is the second half of what flying means. A dragon that
	# could cross a forest but not a town centre would still be walled in by a building line,
	# and "over" is the one thing air has that the other two domains do not. `blocking` is a
	# statement about the GROUND, and nothing in this game occupies the sky.
	if domain == Domain.AIR:
		return true
	var i := _index(t)
	return occupancy[i] == 0 or blocking[i] == 0


## Whether something could be BUILT here: passable ground with nothing standing on
## it at all, blocking or not.
##
## Deliberately not `is_passable()`, which `can_place_building()` used to call. A
## field is walkable and must still refuse to have a house dropped on top of it,
## and the two questions parted company the moment anything was walkable and
## claimed at once.
func is_buildable(t: Vector2i, domain: int = Domain.LAND) -> bool:
	return is_terrain_passable(t, domain) and occupancy[_index(t)] == 0


## Passability of the ground alone, ignoring what is standing on it. Needed
## separately because a building's own footprint tiles are occupied by definition,
## so "could a unit ever walk here" and "can one walk here now" are different
## questions -- placement validation and pathfinding each want a different one.
func is_terrain_passable(t: Vector2i, domain: int = Domain.LAND) -> bool:
	if not in_bounds(t):
		return false
	# ⚠️ **AIR ANSWERS BEFORE `move_cost`, AND THAT IS THE WHOLE FIX.**
	#
	# `move_cost` comes from `TERRAIN_COST`, which marks ROCK and FOREST IMPASSABLE -- and
	# until 2026-09-04 this returned false on those tiles BEFORE looking at the domain. So
	# `DOMAIN_TERRAIN[AIR]`, which lists rock and forest as crossable, was a lie: a flying
	# unit was refused precisely the tiles flying is for, while the table read as though air
	# already worked. Never noticed because the only air unit had `speed: 0`, so nothing
	# asked.
	#
	# ⚠️ **AND IT RETURNS EARLY RATHER THAN CONSULTING THE TABLE, WHICH IS A HOT-PATH
	# DECISION.** `PathService._sync_rect` calls this for every tile of every domain grid --
	# 65k per sweep on a 256x256 map -- so the first version, which moved the
	# `DOMAIN_TERRAIN` array lookup ahead of this integer compare for ALL domains, put an
	# `Array.has()` in front of the cheapest possible early-out and blew the tick budget in
	# three tests. LAND and WATER now take exactly the path they always did.
	#
	# The shortcut is only sound because `DOMAIN_TERRAIN[AIR]` lists **every** `Terrain`
	# member, so there is nothing for air to look up. That is not left to trust:
	# `test_sim_map.test_the_air_row_still_covers_every_terrain_kind` pins it, and it is what
	# stops this early return from silently diverging from the table above.
	if domain == Domain.AIR:
		return true
	var i := _index(t)
	if move_cost[i] == IMPASSABLE:
		return false
	return (DOMAIN_TERRAIN[domain] as Array).has(terrain[i] as Terrain)


# ── mutation ───────────────────────────────────────────────────────────────

func fill_terrain(kind: Terrain) -> void:
	for i in range(terrain.size()):
		terrain[i] = kind
		move_cost[i] = TERRAIN_COST[kind]


## Setting terrain resets that tile's cost to the terrain default, so the two can
## never silently disagree. Call `set_move_cost()` afterwards for a deliberate
## override.
func set_terrain(t: Vector2i, kind: Terrain) -> void:
	if not in_bounds(t):
		return
	var i := _index(t)
	terrain[i] = kind
	move_cost[i] = TERRAIN_COST[kind]


func set_terrain_rect(rect: Rect2i, kind: Terrain) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			set_terrain(Vector2i(x, y), kind)


func set_move_cost(t: Vector2i, cost: int) -> void:
	if in_bounds(t):
		move_cost[_index(t)] = clampi(cost, 0, IMPASSABLE)


## Claim every tile of `rect` for entity `id`. Callers should check
## `can_place_building()` first; this does not validate, so that 2.4a can place
## the starting town centres without them having to be legal placements.
## `blocks` false claims the ground without closing it to movement -- a field.
## Ignored when `id` is 0, which is a release rather than a claim.
func set_occupied(rect: Rect2i, id: int, blocks: bool = true) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t := Vector2i(x, y)
			if in_bounds(t):
				var i := _index(t)
				occupancy[i] = id
				blocking[i] = 1 if (id != 0 and blocks) else 0


func clear_occupied(rect: Rect2i) -> void:
	set_occupied(rect, 0)


## Free every tile `id` holds, wherever they are. Destruction (5.5) knows the
## entity, not necessarily the rect it was placed with, and clearing by rect
## would silently leave tiles claimed if the footprint had changed.
func clear_occupant(id: int) -> void:
	if id == 0:
		return
	for i in range(occupancy.size()):
		if occupancy[i] == id:
			occupancy[i] = 0
			blocking[i] = 0


# ── placement ──────────────────────────────────────────────────────────────

## Every tile in `rect` must be in bounds, buildable ground, and unoccupied.
## Buildings are land-only, which is why the domain is not a parameter -- a dock
## would need a different rule and can add one when it exists.
##
## `is_buildable`, not `is_passable`: a field is walkable and still occupied, and
## calling the movement question here would let a second building be dropped on
## top of a standing crop.
func can_place_building(rect: Rect2i) -> bool:
	return can_place(rect, Domain.LAND)


## The same question for any domain, which is what a FISH needed (6.5). Buildings keep
## their own no-argument entry point above, because the comment on it is still true --
## a building is land-only and the domain is not a choice its caller should be offered.
## A resource node is different: `res.fish` declares `domain: water` and `SimMap` is the
## only thing that can decide whether a given tile satisfies it.
func can_place(rect: Rect2i, domain: int) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not is_buildable(Vector2i(x, y), domain):
				return false
	return true


## The nearest free tile just outside `rect`, for a unit leaving a building
## (5.4's production spawn). Vector2i(-1, -1) if the building is walled in.
##
## Scans the ring in a FIXED order -- top edge left to right, then bottom, then
## left, then right -- and widens by one ring at a time. Order matters more than
## it looks: two clients spawning a unit must pick the same tile or the
## simulations diverge (PLAN.md 7.1), so this must never depend on iteration
## order of anything unordered.
##
## **`max_ring` BOUNDS HOW FAR IT WILL LOOK, and 0 keeps the old behaviour of the whole
## map.** That default is right for a building, which stands on the ground its occupants
## are going onto: the ring widens past a crowd of units and finds a tile a few steps
## away. It is catastrophic for a TRANSPORT SHIP (2.4d), which is why this argument
## exists -- a boat in mid-ocean has no land at any ring near it, so an unbounded search
## walks outward until it finds a beach somewhere else on the map and TELEPORTS THE
## LANDING PARTY THERE. Caught by `test_transport`, which expected the unload to be
## refused and watched the army arrive on a coast it had never sailed to.
##
## So an amphibious landing passes 1: you come off onto ground you are moored against,
## or you stay aboard.
func find_free_adjacent(rect: Rect2i, domain: int = Domain.LAND,
		max_ring: int = 0) -> Vector2i:
	var limit := maxi(size.x, size.y) if max_ring <= 0 else max_ring
	for ring in range(1, limit + 1):
		var outer := rect.grow(ring)
		for x in range(outer.position.x, outer.end.x):
			var top := Vector2i(x, outer.position.y)
			if is_passable(top, domain):
				return top
		for x in range(outer.position.x, outer.end.x):
			var bottom := Vector2i(x, outer.end.y - 1)
			if is_passable(bottom, domain):
				return bottom
		for y in range(outer.position.y + 1, outer.end.y - 1):
			var left := Vector2i(outer.position.x, y)
			if is_passable(left, domain):
				return left
		for y in range(outer.position.y + 1, outer.end.y - 1):
			var right := Vector2i(outer.end.x - 1, y)
			if is_passable(right, domain):
				return right
	return Vector2i(-1, -1)


## The tile rect a footprint occupies when placed at `origin`, which is the
## footprint's TOP-LEFT tile. Centring instead would be ambiguous for even
## footprints -- an 8x8 town centre has no centre tile -- and placement snaps to
## the grid without rotation (PLAN.md 5.1), so top-left is unambiguous.
static func footprint_rect(origin: Vector2i, footprint: Vector2i) -> Rect2i:
	return Rect2i(origin, Vector2i(maxi(1, footprint.x), maxi(1, footprint.y)))


# ── determinism ────────────────────────────────────────────────────────────

## Folded into SimWorld.state_hash(). Without the map in the hash, two runs on
## different terrain would hash identically and the desync check at 0.7 would
## pass while the clients disagreed about where the walls are.
func state_hash() -> int:
	return hash([size.x, size.y, terrain, move_cost, occupancy])


func _index(t: Vector2i) -> int:
	return t.y * size.x + t.x
