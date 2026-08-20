## The gate a generated or loaded map has to pass before a match may start
## (PLAN.md 2.4b fix 5). Returns human-readable problems, so the skirmish screen can
## show *why* Start is disabled rather than just refusing.
##
## **This exists because an unplayable map is invisible.** A player walled in behind
## water, or with the map's only gold on somebody else's island, looks exactly like a
## normal map until you have spent two minutes discovering it. The prototype carved
## paths for the Forest type only, so the other three could produce that map and
## nothing would notice.
##
## It is also what makes the generator testable at all: "does it look right" needs
## eyes, and "can every player reach every other player and some of each resource" is
## an assertion.
##
## ## What it measures, and from where
##
## Reachability is measured **from a player's starting units**, not from the centre of
## their base -- the centre is inside the town centre's own footprint, which is
## blocked ground, so a flood fill starting there would start nowhere. The units on
## the ring are the things that actually have to get somewhere.
##
## Units are not obstacles. `SimMap`'s static-footprint rule keeps them out of the
## occupancy grid entirely, so the only blockers are terrain and the footprints of
## buildings and resource nodes.
class_name MapValidator
extends RefCounted

## A player must find each of these within this many tiles of their start, measured
## as a walk rather than as the crow flies. Generous on purpose: this is a
## playability gate, not a balance pass -- a start with its gold 40 tiles away is
## poor, and a start with no reachable gold at all is broken.
const NEARBY_TILES := 34

## Minimum reachable nearby nodes per player, by resource kind.
const MIN_NEARBY := {&"wood": 4, &"gold": 1, &"stone": 1, &"food": 1}


## Empty when the map is playable.
static func problems(data: MapData) -> Array[String]:
	var found: Array[String] = []
	if data == null or data.size.x <= 0 or data.size.y <= 0:
		found.append("the map has no size")
		return found
	if data.starts.size() < 2:
		found.append("a match needs at least 2 starts, this map has %d" % data.starts.size())
		return found

	var overlaps := _overlapping_entities(data)
	if overlaps > 0:
		found.append("%d entity tiles overlap another entity" % overlaps)

	var blocked := _blocked_tiles(data)
	var sources := _start_sources(data)
	for i in range(data.starts.size()):
		if not sources.has(i):
			found.append("player %d has no starting unit to walk from" % (i + 1))
	if found.size() > 0 and sources.size() < 2:
		return found

	# One flood fill from the first player, which answers every pairing at once: if
	# everybody is in player 1's component then everybody is in everybody's, since
	# reachability over undirected ground is symmetric and transitive.
	var keys := sources.keys()
	keys.sort()
	var reachable := _flood(data, blocked, sources[keys[0]])
	for i in keys:
		if not reachable.has(sources[i]):
			found.append("player %d cannot reach player %d" % [int(keys[0]) + 1, int(i) + 1])

	# Resources are checked per player, because "the map has gold somewhere" is not
	# the same promise as "this player can get to gold".
	for i in keys:
		var near := _nearby_resource_counts(data, blocked, sources[i])
		for kind in MIN_NEARBY:
			if int(near.get(kind, 0)) < int(MIN_NEARBY[kind]):
				found.append("player %d has %d reachable %s within %d tiles, needs %d"
						% [int(i) + 1, int(near.get(kind, 0)), kind, NEARBY_TILES,
						int(MIN_NEARBY[kind])])

	return found


## Player index -> the tile of that player's first starting unit.
static func _start_sources(data: MapData) -> Dictionary:
	var out: Dictionary = {}
	for e in data.entities:
		var player := int(e.get("player", 0))
		if player <= 0 or out.has(player - 1):
			continue
		if GameDataRegistry.unit(e.get("def_id", &"")) == null:
			continue
		out[player - 1] = e["tile"] as Vector2i
	return out


## Tiles nothing can walk through: impassable ground, plus every footprint of a
## building or resource node. Units are deliberately absent -- see the class header.
static func _blocked_tiles(data: MapData) -> Dictionary:
	var blocked: Dictionary = {}
	for y in range(data.size.y):
		for x in range(data.size.x):
			var t := Vector2i(x, y)
			if not data.is_ground_passable(t):
				blocked[t] = true

	for e in data.entities:
		var def_id: StringName = e.get("def_id", &"")
		if GameDataRegistry.unit(def_id) != null:
			continue
		var bd: BuildingDef = GameDataRegistry.building(def_id)
		if bd != null and not bd.blocks_movement:
			continue          # a field is walked over (2.1's `blocking` array)
		for t in MapData.footprint_rect_of(e):
			blocked[t] = true
	return blocked


## Breadth-first flood over walkable tiles, 8-directional to match the pathfinder.
## Returns the reachable set; `limit` stops it early for the per-player radius check.
static func _flood(data: MapData, blocked: Dictionary, from: Vector2i,
		limit: int = -1) -> Dictionary:
	var seen: Dictionary = {}
	if blocked.has(from) or not data.in_bounds(from):
		return seen
	seen[from] = 0
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		var d: int = seen[t]
		if limit >= 0 and d >= limit:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := t + Vector2i(dx, dy)
				if seen.has(n) or blocked.has(n) or not data.in_bounds(n):
					continue
				seen[n] = d + 1
				queue.append(n)
	return seen


## How many nodes of each resource kind this player can walk to inside
## `NEARBY_TILES`. A node counts when a tile ADJACENT to its footprint is reachable,
## because that is where a villager stands to work it -- the node's own tiles are
## blocked by definition.
static func _nearby_resource_counts(data: MapData, blocked: Dictionary,
		from: Vector2i) -> Dictionary:
	var reachable := _flood(data, blocked, from, NEARBY_TILES)
	var counts: Dictionary = {}
	for e in data.entities:
		var rd: ResourceDef = GameDataRegistry.resource_def(e.get("def_id", &""))
		if rd == null:
			continue
		var tiles := MapData.footprint_rect_of(e)
		var workable := false
		for t in tiles:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if reachable.has(t + Vector2i(dx, dy)):
						workable = true
						break
				if workable:
					break
			if workable:
				break
		if workable:
			counts[rd.kind] = int(counts.get(rd.kind, 0)) + 1
	return counts


## Tiles claimed by more than one entity. The generator's own `claimed` set should
## make this impossible; asserting it is what keeps a future placement rule from
## quietly dropping a node on top of a town centre.
static func _overlapping_entities(data: MapData) -> int:
	var seen: Dictionary = {}
	var overlaps := 0
	for e in data.entities:
		for t in MapData.footprint_rect_of(e):
			if seen.has(t):
				overlaps += 1
			seen[t] = true
	return overlaps
