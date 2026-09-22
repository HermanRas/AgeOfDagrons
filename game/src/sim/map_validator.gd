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

## How close a start must be to shallow water on a sea map, in tiles of walking.
##
## THIS IS THE ARCHIPELAGO'S REPLACEMENT FOR "everybody can reach everybody", not an
## extra: a player who cannot build a dock is sealed on their island for the whole match,
## which is the same unplayable-and-invisible failure the land check exists to catch.
## Generous, like `NEARBY_TILES` -- a start whose beach is 20 tiles away is a poor start
## and a start with no beach at all is a broken one.
const SHORE_TILES := 20


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

	found.append_array(_undrawable_axes(data))

	var blocked := _blocked_tiles(data)
	var sources := _start_sources(data)
	for i in range(data.starts.size()):
		if not sources.has(i):
			found.append("player %d has no starting unit to walk from" % (i + 1))
	if found.size() > 0 and sources.size() < 2:
		return found

	var keys := sources.keys()
	keys.sort()

	# THE CONNECTIVITY CLAIM IS PER TYPE, and for the archipelago it CHANGES rather than
	# relaxes (2.4d, PLAN.md 11.6). "Every start reaches every other by land" is correct
	# for four map types and wrong by intent for the fifth -- a map where you can walk to
	# your enemy is not an archipelago. What replaces it is two claims of the same
	# strength, and skipping the check outright was never the option:
	#
	#   - every start can reach SHALLOW WATER, or a dock can never be built and that
	#     player is sealed in for the whole match;
	#   - the water is ONE BODY, so a ship can get from any island to any other. That is
	#     the archipelago's version of "everybody can reach everybody" and it is the same
	#     flood fill over a different domain.
	#
	# Nothing else moves. A player who cannot reach their own gold is broken on any map,
	# so `MIN_NEARBY` below is unchanged and unconditional.
	if _is_sea_map(data):
		found.append_array(_sea_problems(data, blocked, sources, keys))
	else:
		# One flood fill from the first player, which answers every pairing at once: if
		# everybody is in player 1's component then everybody is in everybody's, since
		# reachability over undirected ground is symmetric and transitive.
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


## Whether this map's players are meant to be separated by water.
##
## READ OFF `meta.type`, which `MapGenerator._generate_once` writes before `generate()`
## calls this. A map with no type -- a hand-built one, a fixture, a saved map from before
## the field existed -- takes the land claim, which is the strict one, so an unknown map
## is never let through on the weaker rule by accident.
static func _is_sea_map(data: MapData) -> bool:
	return int(data.meta.get("type", -1)) == int(MapGenerator.Type.ARCHIPELAGO)


## The archipelago's two claims. See `problems()` for why these replace the land one
## rather than sitting beside it.
static func _sea_problems(data: MapData, blocked: Dictionary, sources: Dictionary,
		keys: Array) -> Array[String]:
	var found: Array[String] = []

	# Each player's own beach, walked to rather than measured as the crow flies -- a
	# shoreline on the far side of your own mountain is not a shoreline you can use.
	for i in keys:
		if not _reaches_shore(data, blocked, sources[i]):
			found.append("player %d cannot walk to any shore within %d tiles, so cannot build a dock"
					% [int(i) + 1, SHORE_TILES])

	# ONE SEA. Flooded from the first player's own nearest water rather than from a
	# corner of the map, because a lagoon inside somebody's island is water too and a
	# fill that started in one would report the ocean as unreachable.
	var seas := _sea_components(data, sources, keys)
	if seas.size() > 1:
		found.append("the sea is in %d separate bodies, so ships cannot cross between all islands"
				% seas.size())
	return found


## Whether shallow water is within `SHORE_TILES` of walking from `from`.
##
## SHALLOW ONLY. Deep water is where a ship sails, not where a dock stands, and an island
## whose rim went straight from grass to deep water would pass a test that accepted
## either while still being unbuildable. A tile ADJACENT to the walk is enough -- water
## is not walkable, so the villager stands beside it exactly as she stands beside a tree.
static func _reaches_shore(data: MapData, blocked: Dictionary, from: Vector2i) -> bool:
	for t in _flood(data, blocked, from, SHORE_TILES):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = t + Vector2i(dx, dy)
				if data.in_bounds(n) and data.terrain_at(n) == SimMap.Terrain.WATER_SHALLOW:
					return true
	return false


## How many distinct bodies of water the players' own shores sit on.
##
## Not "how many bodies of water are on the map" -- a two-tile puddle in the middle of
## somebody's island is a separate body and is nobody's problem. What matters is whether
## the sea each player can LAUNCH INTO is the same sea, so this floods from each player's
## nearest water and counts how many of those fills are distinct.
static func _sea_components(data: MapData, sources: Dictionary, keys: Array) -> Array:
	var seen: Dictionary = {}          # tile -> component index
	var components: Array = []
	for i in keys:
		var launch := _nearest_water(data, sources[i])
		if launch == NO_WATER:
			continue                   # already reported as "cannot build a dock"
		if seen.has(launch):
			continue                   # same sea as an earlier player's
		var body := _flood_water(data, launch)
		for t in body:
			seen[t] = components.size()
		components.append(body.size())
	return components


## The shallow tile nearest `from`, or `NO_WATER`. A plain expanding-square scan rather
## than a flood, because it is asking about DISTANCE and not about reachability --
## whether the player can get there is `_reaches_shore`'s question, asked separately.
##
## A SENTINEL RATHER THAN NULL, so the return type can be declared: an untyped `null`
## return makes every caller's `var x := ...` a Variant, which GDScript refuses to infer.
## `(-1, -1)` is off every map and is the sentinel `SimUnit.deposit_tile` and
## `roam_home` already use, for the same reason -- tile (0, 0) is real.
const NO_WATER := Vector2i(-1, -1)

static func _nearest_water(data: MapData, from: Vector2i) -> Vector2i:
	for r in range(1, SHORE_TILES + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue           # the ring at exactly this radius
				var t := from + Vector2i(dx, dy)
				if data.in_bounds(t) and data.terrain_at(t) == SimMap.Terrain.WATER_SHALLOW:
					return t
	return NO_WATER


## Breadth-first flood over WATER, shallow and deep alike -- a ship crosses both
## (`SimMap.DOMAIN_TERRAIN[Domain.WATER]`), so a deep ocean joining two shallow rims is
## one sea and must count as one.
##
## Entities are not obstacles here, deliberately: the only things that stand in water are
## fish, and a shoal is something a ship sails past rather than a wall.
static func _flood_water(data: MapData, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := t + Vector2i(dx, dy)
				if seen.has(n) or not data.in_bounds(n):
					continue
				var kind := data.terrain_at(n)
				if kind != SimMap.Terrain.WATER_SHALLOW and kind != SimMap.Terrain.WATER_DEEP:
					continue
				seen[n] = true
				queue.append(n)
	return seen


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


## Entities laid along an axis their art cannot draw (#97, 2026-09-22).
##
## ## ⛔ THIS IS THE ONLY PLACE THE MISTAKE CAN BE CAUGHT, AND IT IS SILENT EVERYWHERE ELSE
##
## `BuildingDef.facing_for` falls back rather than failing, because it runs inside
## `MapGen.build_from` where a refusal would take the whole match down over one bad entity
## — so a cliff face laid on a diagonal **builds, blocks, and draws a frame that is merely
## wrong**. Nothing crashes, nothing warns, and the only symptom is a piece of scenery that
## looks slightly off in a screenshot nobody is studying. This is the half that turns it
## back into a sentence an author reads before they save.
##
## ⚠️ **`can_face` IS TRUE FOR EVERYTHING THAT DECLARES NO `facings`**, so this costs every
## existing map nothing: twelve wall defs, six committed maps, every generated board. Only
## a def that has said which axes it has art for is held to what it said.
##
## THE MESSAGE NAMES THE TILE, because a plateau is a long line of near-identical entities
## and "a cliff is on the wrong axis" would send an author looking through all of them.
static func _undrawable_axes(data: MapData) -> Array[String]:
	var found: Array[String] = []
	for e in data.entities:
		if not e.has("axis"):
			continue
		var bd: BuildingDef = GameDataRegistry.building(StringName(e["def_id"]))
		if bd == null:
			continue
		var axis := int(e["axis"])
		if bd.can_face(axis):
			continue
		var tile: Vector2i = e.get("tile", Vector2i.ZERO)
		found.append("%s at %d,%d is laid on axis %d, which it has no art for"
				% [String(e["def_id"]), tile.x, tile.y, axis])
	return found


## Tiles claimed by more than one entity. The generator's own `claimed` set should
## make this impossible; asserting it is what keeps a future placement rule from
## quietly dropping a node on top of a town centre.
##
## ## ✅ EXCEPT THAT TWO CLIFFS MAY SHARE A TILE (#97, 2026-09-22), AND THE RING NEEDS IT
##
## The art side's three placement rules were written for a TERRAIN model where both tables
## are live at once: a corner tile draws a face on each of its edges AND the diagonal piece
## over its point. Moving cliffs to entities put one entity per tile in the way of that, and
## the shape of a plateau over-constrains it -- four edges that each want a whole number of
## one length, plus a corner piece, cannot all fit without a tile being wanted twice. The
## owner photographed what happens when you give the corner away instead: *"the east corner
## has a gap, i see single tile cliffs in that spot."*
##
## ⚠️ **IT IS SAFE FOR CLIFFS SPECIFICALLY AND WOULD NOT BE FOR ANYTHING ELSE.** What
## `occupancy` holds is ONE entity id per tile, and the reason that normally matters is that
## despawning the entity clears the cell -- so a stacked pair would leave a hole under a
## building that is still standing. **A cliff never despawns**: it cannot be attacked
## (`Diplomacy`), it is never sold, built over or upgraded, and it leaves no rubble. Both
## occupants block, so whichever id the cell ends up holding gives the same answer to every
## question anything asks it.
##
## ⛔ **NARROW ON PURPOSE -- EVERY occupant of the tile has to be a cliff.** A cliff sharing
## with a house is still an overlap and still reported, because the house can be destroyed
## and would take the cliff's claim with it.
static func _overlapping_entities(data: MapData) -> int:
	var seen: Dictionary = {}
	var overlaps := 0
	for e in data.entities:
		var cliff := _is_cliff(e)
		for t in MapData.footprint_rect_of(e):
			if seen.has(t):
				if cliff and bool(seen[t]):
					continue
				overlaps += 1
			# Stays true only while EVERY entity on this tile has been one, so a house
			# landing on a cliff turns the tile back into an ordinary overlap for whatever
			# arrives after it as well.
			seen[t] = cliff and bool(seen.get(t, true))
	return overlaps


## Whether this entity record is a cliff piece.
##
## 📝 **BY DEF ID PREFIX, WHICH IS A COMPROMISE AND IS WRITTEN DOWN AS ONE.** The honest test
## would be a `BuildingDef` flag, and there is no field that means "scenery that can never be
## removed" -- `selectable` is a view rule and `buildable` is shared with every wall segment.
## Adding one for a single caller is the heavier change; if a second kind of permanent
## scenery ever lands, that flag is what this should become.
static func _is_cliff(e: Dictionary) -> bool:
	return String(e.get("def_id", "")).begins_with("building.cliff")
