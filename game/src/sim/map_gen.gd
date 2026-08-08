## Builds the starting world: terrain, resource nodes, and each player's opening
## town centre and villagers. Phases 2.4a (fixed debug map), 2.3 (placement into
## the grid) and 2.6 (starting conditions).
##
## Separate from SimWorld because "what a match starts with" is content and "how a
## match runs" is machinery. A procedural generator (2.4b) is another function
## here; SimWorld does not learn about either.
##
## **Everything is deterministic.** No `randi()`, no `Time`, no iteration over an
## unordered Dictionary. The layout is either fixed or driven by a seeded RNG whose
## seed comes from MatchConfig, because two clients building the same match must
## produce byte-identical worlds or they desync on tick 1 (PLAN.md 7.1).
class_name MapGen
extends RefCounted

## PLAN.md 2.6 / IDEA 2.6.
const STARTING_VILLAGERS := 5

## Where a player's town centre goes on the debug map, as a fraction of map size.
## One start position only -- 2.4b handles 2-8.
const DEBUG_START := Vector2(0.5, 0.5)

## Resource layout for the debug map, in tiles relative to the town centre's
## top-left. Hand-placed rather than scattered: the MVP has to be walkable in a
## few seconds on a phone, and a villager should reach wood, gold and food without
## a hunt (PLAN.md 10).
##
## The wood and deer offsets are also chosen for the *screen*, not just the grid.
## Iso sends (dx - dy) to screen x and (dx + dy) to screen y, so an offset along
## the -x+y diagonal moves an object left with no vertical drift, and +x-y moves
## it right the same way. Wood therefore sits ~6 tiles down-left of the town
## centre and the deer ~6 up-right, which puts tree, town centre and stag on one
## horizontal band in dev_preview/preview_world.tscn -- the only way to compare
## their sizes by looking, which is what they are placed like this for. Six and
## not eight because the preview frame is 1152 px wide, and eight put the deer
## just past the right edge.
const DEBUG_WOOD_CLUSTER := [
	Vector2i(-4, 9), Vector2i(-3, 9), Vector2i(-2, 9), Vector2i(-1, 9),
	Vector2i(-4, 10), Vector2i(-3, 10), Vector2i(-2, 10), Vector2i(-1, 10),
	Vector2i(-4, 11), Vector2i(-3, 11), Vector2i(-2, 11), Vector2i(-1, 11),
]
const DEBUG_GOLD := [Vector2i(11, 2), Vector2i(12, 2), Vector2i(11, 3)]
## A line rather than a block: a 2x2 of deer puts two of them on the same screen
## column, one hidden behind the other. Stepping only dx staggers all four.
const DEBUG_DEER := [Vector2i(8, -3), Vector2i(9, -3), Vector2i(10, -3), Vector2i(11, -3)]


## Populate `w` with the fixed debug map. Call after SimWorld.setup(), which has
## already created an empty grid at the configured size.
static func build_debug_map(w: SimWorld) -> void:
	_paint_terrain(w.map)

	# Order matters and is fixed: town centres first so their footprints are
	# claimed before anything else can take those tiles, then nodes, then
	# villagers into whatever is left. Placing nodes first would let a tree land
	# where a town centre has to go and silently shrink a player's start.
	for p in w.players:
		var origin := _start_origin(w, p.id)
		var tc := w.spawn_building(&"building.town_center", p.id, origin,
				SimBuilding.Phase.COMPLETE, true)
		_place_resources(w, origin)
		_place_villagers(w, p.id, tc)

	# The map is final; build the pathfinding grid now. A full sweep of a 64x64
	# grid measures ~12 ms, which is invisible during setup and five times the
	# per-tick budget if it lands on the player's first move order instead (4.2).
	if w.paths != null:
		w.paths.rebuild(w.map)


static func _paint_terrain(map: SimMap) -> void:
	map.fill_terrain(SimMap.Terrain.GRASS)
	# A dirt border, purely so the map edge is visible before there is a camera
	# clamp to prove itself against (3.3). Cheap and it makes "am I at the edge?"
	# answerable by looking.
	var w := map.size.x
	var h := map.size.y
	for x in range(w):
		map.set_terrain(Vector2i(x, 0), SimMap.Terrain.DIRT)
		map.set_terrain(Vector2i(x, h - 1), SimMap.Terrain.DIRT)
	for y in range(h):
		map.set_terrain(Vector2i(0, y), SimMap.Terrain.DIRT)
		map.set_terrain(Vector2i(w - 1, y), SimMap.Terrain.DIRT)


## Top-left tile of a player's town centre. Derived from map size rather than
## hardcoded so the debug map still works if MatchConfig.map_size changes.
static func _start_origin(w: SimWorld, _player_id: int) -> Vector2i:
	var footprint := _footprint_of(w, &"building.town_center")
	var centre := Vector2i(
		int(float(w.map.size.x) * DEBUG_START.x),
		int(float(w.map.size.y) * DEBUG_START.y))
	return centre - footprint / 2


static func _footprint_of(w: SimWorld, def_id: StringName) -> Vector2i:
	var d: BuildingDef = w.building_def(def_id)
	return d.footprint if d != null else Vector2i.ONE


static func _place_resources(w: SimWorld, origin: Vector2i) -> void:
	# spawn_resource_node returns null on an occupied or off-map tile, and that is
	# fine here -- a cluster near the map edge simply places fewer trees rather
	# than failing the whole match.
	for offset in DEBUG_WOOD_CLUSTER:
		w.spawn_resource_node(&"res.tree", origin + offset, 1)
	for offset in DEBUG_GOLD:
		w.spawn_resource_node(&"res.gold_mine", origin + offset, 1)
	for offset in DEBUG_DEER:
		w.spawn_resource_node(&"res.deer", origin + offset, 0)


## Villagers ring the town centre, placed one at a time so each claims a distinct
## tile. `find_free_adjacent` scans a fixed order, so this is deterministic --
## but it only reports free *terrain*, and units are not written into occupancy
## (SimMap's static-footprint rule), so the tiles taken so far are tracked here.
static func _place_villagers(w: SimWorld, player_id: int, tc: SimBuilding) -> void:
	var rect := tc.footprint_rect() if tc != null else Rect2i(_fallback_origin(w), Vector2i.ONE)
	var taken: Array[Vector2i] = []

	for i in range(STARTING_VILLAGERS):
		var tile := _next_free_tile(w, rect, taken)
		if tile.x < 0:
			break                      # nowhere left; better 4 villagers than a crash
		taken.append(tile)
		w.spawn_unit(&"unit.villager", player_id, tile)


static func _next_free_tile(w: SimWorld, rect: Rect2i, taken: Array[Vector2i]) -> Vector2i:
	# Widen the ring until a tile is found that is both passable and not already
	# assigned to an earlier villager this call.
	for ring in range(1, maxi(w.map.size.x, w.map.size.y)):
		var outer := rect.grow(ring)
		for y in range(outer.position.y, outer.end.y):
			for x in range(outer.position.x, outer.end.x):
				var t := Vector2i(x, y)
				if rect.grow(ring - 1).has_point(t):
					continue           # inner rings were already searched
				if taken.has(t):
					continue
				if w.map.is_passable(t, SimMap.Domain.LAND):
					return t
	return Vector2i(-1, -1)


static func _fallback_origin(w: SimWorld) -> Vector2i:
	return Vector2i(w.map.size.x / 2, w.map.size.y / 2)
