## A map, before it is a world (PLAN.md 2.4b): terrain bytes plus the list of
## entities to place on them. The thing a generator produces, a saved file holds
## (2.4c), the skirmish screen previews (1.6), and `MapGen.build_from()` turns into
## a `SimWorld`.
##
## **This exists so those four things share one representation.** The alternative --
## a generator that writes straight into a world -- cannot be previewed before the
## match starts, cannot be saved, and cannot be validated (2.4b's connectivity gate)
## without standing up a whole simulation to ask.
##
## Plain `RefCounted` with packed arrays, like `SimMap`, and deliberately NOT a
## `SimMap`: this is the *recipe*, and a `SimMap` is the live grid with occupancy and
## pathfinding costs derived from it. Keeping them apart is what lets a map be
## inspected, drawn and shipped without allocating any of that.
##
## THE TERRAIN LAYOUT MATCHES `SimMap.terrain` EXACTLY -- same row-major stride, same
## `SimMap.Terrain` byte values -- so applying a map is a copy rather than a
## translation, and `TerrainLayer` can draw a preview from these bytes with the code
## it already has.
class_name MapData
extends RefCounted

## The format version written into `meta`, so a saved map from an older generator can
## be recognised rather than misread. Bumped when the *meaning* of a field changes,
## not when a generator produces different-looking maps.
const FORMAT_VERSION := 1

var size: Vector2i = Vector2i.ZERO
var terrain: PackedByteArray = PackedByteArray()

## What to place, in placement order: `{def_id, player, tile, size_class}`.
##
## `player` is 0 for gaia (every resource node), otherwise the 1-based player number
## -- an INDEX INTO THE MATCH, not a `SimPlayer.id`, because a map is written before
## anybody knows what ids a match will hand out. `MapGen.build_from()` resolves it.
##
## `tile` is the ORIGIN (top-left) for anything with a footprint, matching
## `SimWorld.spawn_building()`/`spawn_resource_node()`, and simply the tile for a unit.
## Storing a centre instead would be ambiguous for even footprints -- a 10x10 town
## centre has no centre tile.
var entities: Array[Dictionary] = []

## One per player in player order: the CENTRE tile of that player's start.
##
## Kept as its own field rather than derived from the town centre entity, because it
## is what the validator measures connectivity between and what the preview marks --
## both of which want "where does player N begin" without knowing which entity in the
## list is their town centre or how big its footprint is.
var starts: Array[Vector2i] = []

## `{type, seed, players, name, format_version, created}`. Provenance, not content:
## nothing in the sim reads it, and a map with the wrong `seed` recorded still plays
## exactly as its pixels say (2.4c -- the content is authoritative, the seed is only
## how it came to be).
var meta: Dictionary = {}


static func create(p_size: Vector2i, fill: int = SimMap.Terrain.GRASS) -> MapData:
	var d := MapData.new()
	d.size = p_size
	d.terrain.resize(maxi(0, p_size.x * p_size.y))
	d.fill_terrain(fill)
	d.meta = {"format_version": FORMAT_VERSION}
	return d


# ── grid ────────────────────────────────────────────────────────────────────

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < size.x and t.y < size.y


## Row-major index, or -1 out of bounds. Same stride as `SimMap.index_of()`, and
## that is a contract rather than a coincidence -- see the class header.
func index_of(t: Vector2i) -> int:
	return t.y * size.x + t.x if in_bounds(t) else -1


## `SimMap.Terrain.ROCK` out of bounds, so an off-map read behaves like a wall
## rather than like grass -- the same convention `SimMap.terrain_at()` uses, so a
## flood fill written against one works on the other.
func terrain_at(t: Vector2i) -> int:
	var i := index_of(t)
	return terrain[i] if i >= 0 else SimMap.Terrain.ROCK


func set_terrain(t: Vector2i, kind: int) -> void:
	var i := index_of(t)
	if i >= 0:
		terrain[i] = kind


func fill_terrain(kind: int) -> void:
	terrain.fill(kind)


func set_terrain_rect(rect: Rect2i, kind: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			set_terrain(Vector2i(x, y), kind)


## Whether LAND can cross this tile's ground, ignoring anything standing on it.
## Asked of `SimMap`'s own tables so a map cannot disagree with the grid it becomes.
func is_ground_passable(t: Vector2i) -> bool:
	if not in_bounds(t):
		return false
	return (SimMap.DOMAIN_TERRAIN[SimMap.Domain.LAND] as Array).has(terrain_at(t))


# ── entities ────────────────────────────────────────────────────────────────

func add_entity(def_id: StringName, player: int, tile: Vector2i, size_class: int = 0) -> void:
	entities.append({"def_id": def_id, "player": player, "tile": tile,
			"size_class": size_class})


func player_count() -> int:
	return starts.size()


## Every tile an entity's footprint claims, as a set (tile -> true).
##
## Needed by the validator and by the generator's own placement, both of which have
## to know what is in the way BEFORE a `SimWorld` exists to ask. Footprints come from
## `GameDataRegistry` rather than being stored per entity: they are a property of the
## def, and a map that recorded them would go stale the day a building is resized.
func claimed_tiles() -> Dictionary:
	var claimed: Dictionary = {}
	for e in entities:
		for t in footprint_rect_of(e):
			claimed[t] = true
	return claimed


## The tiles one entity entry covers.
static func footprint_rect_of(e: Dictionary) -> Array[Vector2i]:
	var def_id: StringName = e.get("def_id", &"")
	var origin: Vector2i = e.get("tile", Vector2i.ZERO)
	var footprint := Vector2i.ONE

	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd != null:
		footprint = bd.footprint
	else:
		var rd: ResourceDef = GameDataRegistry.resource_def(def_id)
		if rd != null:
			footprint = rd.footprint_for_size(int(e.get("size_class", 0)))
		# A unit claims nothing in the grid (SimMap's static-footprint rule), but it
		# still occupies the one tile it stands on as far as PLACEMENT is concerned --
		# two villagers must not be put on the same tile.

	var tiles: Array[Vector2i] = []
	for y in range(origin.y, origin.y + maxi(1, footprint.y)):
		for x in range(origin.x, origin.x + maxi(1, footprint.x)):
			tiles.append(Vector2i(x, y))
	return tiles


# ── wire format ─────────────────────────────────────────────────────────────

## For sending a map to a joining client and for the saved sidecar (2.4c).
##
## `terrain` rides as raw bytes; the entity list is small enough (tens to a few
## hundred entries) that naming its fields costs little and makes a captured map
## readable. Tiles become paired ints because `Vector2i` is not JSON.
func to_dict() -> Dictionary:
	var out: Array[Dictionary] = []
	for e in entities:
		var t: Vector2i = e["tile"]
		out.append({"def_id": String(e["def_id"]), "player": int(e["player"]),
				"x": t.x, "y": t.y, "size_class": int(e.get("size_class", 0))})
	var starts_out: Array[Dictionary] = []
	for s in starts:
		starts_out.append({"x": s.x, "y": s.y})
	return {"w": size.x, "h": size.y, "terrain": terrain,
			"entities": out, "starts": starts_out, "meta": meta}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.size = Vector2i(int(d.get("w", 0)), int(d.get("h", 0)))
	m.terrain = d.get("terrain", PackedByteArray())
	m.meta = d.get("meta", {})
	for e in d.get("entities", []):
		m.add_entity(StringName(e.get("def_id", "")), int(e.get("player", 0)),
				Vector2i(int(e.get("x", 0)), int(e.get("y", 0))),
				int(e.get("size_class", 0)))
	for s in d.get("starts", []):
		m.starts.append(Vector2i(int(s.get("x", 0)), int(s.get("y", 0))))
	return m
