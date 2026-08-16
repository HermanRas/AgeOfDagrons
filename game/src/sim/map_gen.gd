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
## A line rather than a block: a 2x2 arrangement puts two on the same screen
## column, one hidden behind the other. Stepping only dx staggers all four.
## Berry bushes, not deer -- session decision to use res.berry_bush as the MVP
## food node (PLAN.md 10): it needs no hunt/kill/carcass state machine, and
## vis.berry_bush is fully delivered where the deer carcass is not
## (ASSET_MISSING.md 2.3, asset_request.md). res.deer stays defined and could
## replace this again if wildlife hunting (6.1a/6.1b) comes back.
const DEBUG_FOOD := [Vector2i(8, -3), Vector2i(9, -3), Vector2i(10, -3), Vector2i(11, -3)]

## What a SECOND player gets on the debug map (MatchConfig.debug_skirmish): two
## soldiers and nothing else -- no town centre, no villagers, no stock. Offsets
## are from the FIRST player's town-centre origin, same frame as the resource
## clusters above, because "where the enemy is" is only meaningful relative to
## where you start.
##
## An archer and a knight, chosen as the two ends of the military roster: one
## ranged and one melee, one on foot and one mounted, so whatever combat is
## eventually pointed at them has both cases standing in front of it. Both are
## above age 1 -- archer 2, knight 3 -- and that is fine here: `age_required`
## gates the TRAIN menu, not what may exist on a map (PLAN.md 2.7.1).
##
## PLACED FOR THE SCREEN, like the resource clusters. Iso sends (dx - dy) to
## screen x and (dx + dy) to screen y, and the camera opens centred on the town
## centre's own middle -- which is `origin + (5, 5)`, half its 10x10 footprint.
## Relative to that middle these two sit at (7, -5) and (9, -5), i.e. 384 px and
## 448 px to the right and a little below, on a 1152 px frame whose right half is
## 576 px wide. Comfortably on screen at the default zoom, two tiles clear of the
## town centre's edge, and below the berry-bush row rather than tangled in it.
## Stepping only dx between the two staggers them, exactly as DEBUG_FOOD does.
const DEBUG_ENEMY_SQUAD := [
	[&"unit.archer", Vector2i(12, 0)],
	[&"unit.knight", Vector2i(14, 0)],
]

## Starting stock (PLAN.md 9: numbers are starting values to be tuned by
## playtest), and only on the DEBUG map -- this is a sandbox figure, not a
## balance one, and the day there is a real map generator or a lobby it does not
## follow them there.
##
## Was 200 wood. That was right when the roster was a house and a town centre:
## enough to place one or two without gathering first, and no more, so the gather
## loop still had to work. The roster is now 19 buildings and 21 units across
## four ages, and the thing that needs exercising is no longer "can a villager
## chop wood" -- it is whether every building places, every unit trains, and the
## age skins actually swap. Gathering 650 stone for a castle by hand before you
## can look at the castle is not testing, it is waiting.
##
## Generous in all four kinds, then, and deliberately not infinite: costs should
## still visibly come out of the counters, because a resource HUD that never
## moves cannot be checked either. This affords the whole roster several times
## over -- the wonder alone is 1000/1000/1000.
const DEBUG_STARTING_STOCK := {
	&"food": 5000,
	&"wood": 5000,
	&"gold": 5000,
	&"stone": 5000,
}


## Populate `w` with the fixed debug map. Call after SimWorld.setup(), which has
## already created an empty grid at the configured size.
static func build_debug_map(w: SimWorld) -> void:
	_paint_terrain(w.map)

	# THE FIRST PLAYER GETS THE ONLY BASE. This map has one start position
	# (DEBUG_START) and `_start_origin` takes no player into account, so a second
	# town centre would be forced down on top of the first -- 2.4b is where real
	# per-player starts live. Everyone after the first therefore gets the skirmish
	# squad instead: something on the map that is not yours, which is all a debug
	# opponent has to be until there is an AI to run one.
	#
	# Within the base, order matters and is fixed: the town centre first so its
	# footprint is claimed before anything else can take those tiles, then nodes,
	# then villagers into whatever is left. Placing nodes first would let a tree
	# land where the town centre has to go and silently shrink the start.
	var origin := _start_origin(w, 0)
	for i in range(w.players.size()):
		var p := w.players[i]
		if i == 0:
			var tc := w.spawn_building(&"building.town_center", p.id, origin,
					SimBuilding.Phase.COMPLETE, true)
			_place_resources(w, origin)
			_place_villagers(w, p.id, tc)
			for kind in DEBUG_STARTING_STOCK:
				p.add_resource(kind, int(DEBUG_STARTING_STOCK[kind]))
		else:
			_place_enemy_squad(w, p.id, origin)

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
	for offset in DEBUG_FOOD:
		w.spawn_resource_node(&"res.berry_bush", origin + offset, 0)


## The hostile squad (DEBUG_ENEMY_SQUAD), placed relative to the FIRST player's
## town-centre origin. Unlike the villagers these take fixed tiles rather than
## the next free one: they are placed for where they appear on screen, and a
## squad that shuffled to a neighbouring tile because something was in the way
## would quietly stop being where the comment says it is. Units are not written
## into occupancy anyway, so there is nothing to collide with -- only ground to
## be standable, which is checked so a squad offset that ever reached water or
## the map edge fails visibly here rather than by walking through a cliff later.
static func _place_enemy_squad(w: SimWorld, player_id: int, origin: Vector2i) -> void:
	for entry in DEBUG_ENEMY_SQUAD:
		var def_id: StringName = entry[0]
		var tile: Vector2i = origin + (entry[1] as Vector2i)
		if not w.map.is_passable(tile, SimMap.Domain.LAND):
			push_warning("MapGen: no room for %s at %s" % [def_id, tile])
			continue
		w.spawn_unit(def_id, player_id, tile)


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
