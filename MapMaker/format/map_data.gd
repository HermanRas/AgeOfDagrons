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

## NAMED REGIONS (PLAN.md 16.5): `{name, rect}` per entry, in authoring order.
##
## ## A FLAT LIST OF NAMED RECTS, AND A REGION IS THE UNION OF EVERY ENTRY SHARING A NAME
##
## So "north_pass" may be one rectangle or five, and an L-shaped or split region needs no
## new shape in the format. Three things fall out of keeping it flat that a
## `{name, rects: [...]}` record would each have cost something for:
##
##   - **it is `entities`' own shape** -- a list of small dictionaries of scalars -- so it
##     snapshots, copies, serialises and round-trips through exactly the code that already
##     exists for that field. ⚠️ In particular `MapEdit._copied()` on the tool side
##     duplicates each dictionary ONE level deep and says in so many words that there is no
##     nested container to reach; a `rects` array inside a record would have made that
##     sentence false, silently, and undo would have shared its rects with the live map.
##   - **erase is per rect.** An author who mis-drags one rectangle of a five-rect region
##     takes back that rectangle, not the region.
##   - **`Rect2i` is a value type**, like the `Vector2i` in `tile`, so nothing here needs a
##     deep copy anywhere.
##
## ## WHAT THIS FIELD IS *FOR*, WHICH IS NOT DRAWING
##
## `subject: "area"` in PLAN.md 11.8's objective vocabulary, and nothing else. It was
## **refused at load** by `ObjectiveDef` for the whole of Phase 15 precisely because the map
## had no way to say where a region was. Nothing in the player's HUD draws an area and
## nothing should: a region is how a *scenario author* asks a question, and what the player
## reads is the objective's own `text`.
##
## ## ⚠️ ONE REGION NAME MEANS SOMETHING TO A RULE, AND IT IS DECLARED HERE
##
## `KOTH_AREA` below. Every other region is a name an author invented and only an objective they
## also wrote refers to; that one is read by `MapGen` to site the King of the Hill zone, so the
## spelling is a contract between a person typing in the MapMaker and a win condition in the sim.
## **Declared in this file precisely because this file is the one the tool carries a verbatim copy
## of** — so the two projects cannot come to disagree about it, and `FormatGuard` fails if they do.
##
## ⚠️ **NEITHER `FORMAT_VERSION` MOVED, AND THAT IS DECISION 7 RATHER THAN LUCK.** The owner
## ruled a bump affordable (2026-09-04) and PLAN.md §16 decision 7's closing rule still says
## to prefer an optional field where it is free: `from_dict` treats an absent `areas` as no
## areas, so all six committed maps go on loading unchanged and the published `howtoplay`
## pack needs no re-download. `axis` set the precedent one row earlier.
##
## 📝 **BUT `to_dict()` WRITES THE KEY EVEN WHEN THE LIST IS EMPTY, UNLIKE `axis`.** That is
## not an inconsistency, it is what makes the tool's re-save correct --
## `MapDocument._preserved_header()` decides which of an opened sidecar's keys to carry
## forward by asking `to_dict()` what it produces, so a key that vanished when the last area
## was deleted would be carried over from the stale header and the deletion would not reach
## the file. The cost is `"areas": []` in a re-saved sidecar; the alternative is a
## written-out key list, which is the thing that function exists not to have.
var areas: Array[Dictionary] = []

## The region name King of the Hill sites its zone on (11.x-koth).
##
## ⚠️ **THE ONE REGION NAME THE SIM KNOWS, AND IT IS A CONTRACT WITH A PERSON.** An author types
## it into the MapMaker's Area box; `MapGen._place_koth_zone()` looks for exactly this and uses the
## bounding rect of every rectangle carrying it. Everything else in `areas` is between an author
## and their own objectives.
##
## **Lower case and unprefixed on purpose.** It is typed by hand into a text field, so it is short
## and there is nothing to get subtly wrong — no namespace, no capital, no underscore. `add_area()`
## strips surrounding whitespace at both ends of the contract and nothing else is normalised, so
## `Koth` is a different region and correctly does not arm the mode.
##
## 📝 **A MAP WITH NO SUCH REGION IS NOT A BROKEN MAP.** KotH falls back to a generated hill and
## every other mode ignores this entirely — see `MapGen._place_koth_zone()` for why the pair is
## deliberately two sources with one resolution rather than a default.
const KOTH_AREA := &"koth"


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

## What an entity with no orientation writes: nothing at all. See `add_entity()`.
##
## ## WHY A MAP NEEDED AN AXIS, WHEN FOOTPRINTS ARE DELIBERATELY NOT STORED
##
## `claimed_tiles()` below is emphatic that a footprint is *"a property of the def, and a map
## that recorded them would go stale the day a building is resized"*. That is true of all
## thirty-one buildings in the roster **and false of the twelve walls and gates**, whose
## footprint depends on which way the author laid them: `[9, 2]` running one way, `[2, 9]` the
## other. `SimWorld.spawn_building` has always taken a `footprint_override` and a `facing` for
## exactly that reason — its own comment says *"the caller that decided the axis is the caller
## that knows"* — and **a map file is a caller.** Until 2026-09-08 it had no way to say.
##
## ⚠️ **WHAT IT COST TO HAVE NO WAY TO SAY:** `MapGen.build_from()` passed neither, so both
## defaulted — the def's own east-west footprint with facing 0, which `WallPlan.FACING_FOR_AXIS`
## says is the **north-south** wall. Every wall on every authored map would have come out ninety
## degrees wrong in both directions at once, saved cleanly, with the tool showing it correctly.
## That is the fault the owner reported on 2026-08-28 (*"i am dragging NE to SW, the walls look
## like NW to SE"*) which took six days and a re-measurement of twelve atlases to settle.
##
## **The values are `WallPlan.AXIS_X` and `AXIS_Y`** and are not re-declared here: that class is
## the authority on what an axis means for a building and it is already in `src/sim/`.
const AXIS_NONE := -1

## ⚠️ **`axis` IS OPTIONAL AND ITS ABSENCE IS PART OF THE FORMAT** (PLAN.md §16 decision 7,
## added 2026-09-08 for 16.4c). Pass `AXIS_NONE` — the default — and no `axis` key is written,
## which is what every map ever saved before today looks like and what every non-directional
## thing goes on looking like. **`format_version` does not move**, because five committed
## `map.json` files and the published `howtoplay` pack are on version 1 and `MapFile.load_map`
## refuses a mismatch with no migration.
func add_entity(def_id: StringName, player: int, tile: Vector2i, size_class: int = 0,
		axis: int = AXIS_NONE) -> void:
	var e := {"def_id": def_id, "player": player, "tile": tile, "size_class": size_class}
	# STORED ONLY WHEN IT MEANS SOMETHING. An `axis: 0` on every villager in a 170-entity map is
	# 170 keys saying "not applicable", and it would make `axis` look like a field with a default
	# rather than a field that is either there or not -- which is the distinction `build_from()`
	# reads to decide whether to override a footprint at all.
	if axis != AXIS_NONE:
		e["axis"] = axis
	entities.append(e)


func player_count() -> int:
	return starts.size()


# ── areas (PLAN.md 16.5) ────────────────────────────────────────────────────

## Add one rectangle to the region called `name`. False when there is nothing to add.
##
## **THE TWO REFUSALS ARE THE ONES A RECORD CAN BE SURE ABOUT**, `MapDocument.add_entity()`'s
## rule: a nameless region cannot be asked about, and an empty rect contains nothing. Whether
## the rect is ON the map is the CALLER's question -- the tool refuses it there, where there is
## a person to tell -- because a loaded file may carry a region that hangs off the edge of a map
## somebody later shrank, and dropping it on load would silently change what a scenario counts.
##
## ⚠️ **THE NAME IS TAKEN VERBATIM AND IS NOT CASE-FOLDED.** It is matched against an
## objective's `area` field by `ObjectiveSystem`, and folding here without folding there -- or
## folding in the tool and not in the game -- is the `stock.get(&"foood", 0)` trap wearing a
## region: a region nothing can ever be inside, whose only symptom is that the objective never
## ticks. `ScenarioDef.build_config()` is where a name that does not match is caught, and it
## says which names the map does have.
func add_area(name: StringName, rect: Rect2i) -> bool:
	if String(name).strip_edges().is_empty():
		return false
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	areas.append({"name": name, "rect": rect})
	return true


## Every distinct region name, in the order it first appears.
##
## FIRST-APPEARANCE ORDER AND NOT SORTED, because it is what the tool's palette lists and an
## author reads it as the order they authored in. Nothing depends on it being stable across a
## save -- `to_dict()` writes the entries, not this -- so it is a presentation answer.
func area_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in areas:
		var name: StringName = a.get("name", &"")
		if not out.has(name):
			out.append(name)
	return out


## The rectangles making up one region. Empty for a name no entry carries, which is a
## DIFFERENT answer from a region that happens to contain nothing -- see `has_area()`.
func area_rects(name: StringName) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for a in areas:
		if StringName(a.get("name", &"")) == name:
			out.append(a.get("rect", Rect2i()))
	return out


## Is there a region by this name at all?
##
## ⚠️ **ASKED SEPARATELY FROM `area_rects()` BEING EMPTY, AND THE DIFFERENCE IS TRAP 3.**
## "No such region" must not be answered as "a region with nothing in it": `ObjectiveSystem`
## returns its unmeasurable -1 for the first and a real 0 for the second, and 0 is a value that
## PASSES `== 0` and `<= n`. A scenario naming a misspelled region would otherwise announce
## victory on tick 1.
func has_area(name: StringName) -> bool:
	for a in areas:
		if StringName(a.get("name", &"")) == name:
			return true
	return false


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
##
## ⚠️ **AN `axis` OF `WallPlan.AXIS_Y` TRANSPOSES THE FOOTPRINT**, which is what makes the
## validator, the generator's placement check and the MapMaker's collision test all agree about a
## wall laid the other way. Without it the three of them would claim `[9, 2]` for a wall the
## world builds as `[2, 9]`: a map that validates and cannot be built, which is the exact failure
## 16.4's row forbids a second collision test for.
static func footprint_rect_of(e: Dictionary) -> Array[Vector2i]:
	var def_id: StringName = e.get("def_id", &"")
	var origin: Vector2i = e.get("tile", Vector2i.ZERO)
	var footprint := Vector2i.ONE

	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd != null:
		footprint = bd.footprint
		# TRANSPOSED HERE AND IN `build_from()`, from the same key -- there is no third place to
		# forget. `WallPlan.footprint_for()` is the same transposition expressed for a length,
		# and it stays the authority for an in-game drag.
		if int(e.get("axis", AXIS_NONE)) == WallPlan.AXIS_Y:
			footprint = Vector2i(footprint.y, footprint.x)
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
		var row := {"def_id": String(e["def_id"]), "player": int(e["player"]),
				"x": t.x, "y": t.y, "size_class": int(e.get("size_class", 0))}
		# ABSENT STAYS ABSENT, which is decision 7's rule and the reason no version number moved:
		# a map with no directional entities is byte-identical to one written before `axis`
		# existed. `MapDocument._preserved_header()` on the tool side computes its filter FROM
		# this function, so re-saving an opened map needed no edit for this key.
		if e.has("axis"):
			row["axis"] = int(e["axis"])
		out.append(row)
	var starts_out: Array[Dictionary] = []
	for s in starts:
		starts_out.append({"x": s.x, "y": s.y})
	# FLAT INTS, exactly as an entity's tile becomes `x`/`y`: `Rect2i` is not JSON either, and
	# one shape for "a place on the map" across the whole file is one shape to get right.
	var areas_out: Array[Dictionary] = []
	for a in areas:
		var r: Rect2i = a.get("rect", Rect2i())
		areas_out.append({"name": String(a.get("name", &"")),
				"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y})
	return {"w": size.x, "h": size.y, "terrain": terrain,
			# WRITTEN EVEN WHEN EMPTY -- see the `areas` field's own note. This is the key
			# `MapDocument._preserved_header()` filters an opened sidecar against, and a key that
			# disappeared with the last area would leave the deletion out of the saved file.
			"entities": out, "starts": starts_out, "areas": areas_out, "meta": meta}


## Terrain arrives in one of three shapes, so it is READ rather than assigned straight.
##
## Over the WIRE it is a real `PackedByteArray`: Godot's RPC layer encodes Variants in
## binary and hands the bytes across untouched. That is why a two-device match on a
## generated map works (12.1g) despite the bug below.
##
## Through JSON it is a **String**. `JSON.stringify` renders a `PackedByteArray` as the
## text `"[1, 2, 250]"` -- verified on 4.7.1 -- so `terrain` comes back as a String, and
## assigning a String to a typed `PackedByteArray` property is a runtime error that
## abandons the rest of `from_dict` and returns null. Every other field here is already
## defended against JSON, with `int()` around each one because JSON numbers return as
## floats; terrain was the one field that looked like it needed no conversion. It went
## undetected because the test written to catch it died on the very same error and was
## counted as a pass -- see `run_tests.gd`'s `ScriptErrorSpy`.
##
## The Array form nothing produces today. It is accepted because it is what a
## hand-written or hand-edited saved sidecar (2.4c) would most naturally contain.
##
## `to_dict()` deliberately goes on sending raw bytes rather than switching to base64:
## the wire carries 20-40 KB of terrain, base64 would add a third to that for nothing,
## and 12.1f is about wire size. The tolerance belongs on the reading side.
static func _terrain_from(v: Variant) -> PackedByteArray:
	if v is PackedByteArray:
		return v as PackedByteArray

	var numbers: Array = []
	if v is Array:
		numbers = v as Array
	elif v is String:
		var text := (v as String).strip_edges().trim_prefix("[").trim_suffix("]")
		if text.strip_edges().is_empty():
			return PackedByteArray()
		numbers = Array((text as String).split(","))
	else:
		# Not a shape we know. An empty map reads as "no terrain" downstream, which
		# beats guessing at bytes.
		return PackedByteArray()

	var out := PackedByteArray()
	out.resize(numbers.size())
	for i in numbers.size():
		var n: Variant = numbers[i]
		out[i] = int((n as String).strip_edges()) if n is String else int(n)
	return out


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.size = Vector2i(int(d.get("w", 0)), int(d.get("h", 0)))
	m.terrain = _terrain_from(d.get("terrain", PackedByteArray()))
	m.meta = d.get("meta", {})
	for e in d.get("entities", []):
		# ⚠️ **`has()` AND NOT A DEFAULT, because absent and `AXIS_X` are different things.**
		# Absent means "this entity has no orientation, behave exactly as before"; `AXIS_X` means
		# "a wall, laid east-west, and the caller must be told so" -- and `build_from()` reads
		# that difference to decide whether to force a facing at all. A `get("axis", 0)` here
		# would quietly turn every villager on every old map into a directional entity.
		m.add_entity(StringName(e.get("def_id", "")), int(e.get("player", 0)),
				Vector2i(int(e.get("x", 0)), int(e.get("y", 0))),
				int(e.get("size_class", 0)),
				int(e.get("axis", AXIS_NONE)) if e.has("axis") else AXIS_NONE)
	for s in d.get("starts", []):
		m.starts.append(Vector2i(int(s.get("x", 0)), int(s.get("y", 0))))
	# ABSENT MEANS NO AREAS, which is what every map written before 16.5 looks like and is the
	# whole reason neither FORMAT_VERSION had to move (decision 7). `add_area()` rather than a
	# direct append, so a file carrying a nameless or empty region is dropped by the same rule
	# that refuses one in the tool -- there is one definition of a region worth having.
	for a in d.get("areas", []):
		m.add_area(StringName(str(a.get("name", ""))),
				Rect2i(int(a.get("x", 0)), int(a.get("y", 0)),
						int(a.get("w", 0)), int(a.get("h", 0))))
	return m
