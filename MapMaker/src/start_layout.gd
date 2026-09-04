## What a player is given at their start (PLAN.md 16.2): a town centre, villagers, a scout,
## and enough of an economy to play.
##
## ## WHY THE TOOL PLACES THIS AT ALL, RATHER THAN LEAVING IT TO THE AUTHOR
##
## `MapGen.build_from()` gives a player their base **only** by spawning the entities the map
## lists for their index. It never falls back to `_start_origin()` the way the debug map
## does. So a map with a start marker and no base authors a player who opens the match alive,
## owning nothing, and is eliminated on the first tick anything looks — the exact fault
## 16.0's `can_start()` rule 7 exists to refuse. **A tool must not be able to create that by
## accident**, so dropping a start places a start.
##
## ## THE SHAPE IS THE GAME'S; THE NUMBERS ARE THIS TOOL'S
##
## `MapGenerator._place_base()` is the reference and it is **not** copied — it is a private
## static inside a 1,000-line generator that belongs to the sim, and copying it would put a
## second generator in `format/` where only the FORMAT belongs. What is mirrored is the shape,
## because an authored start that plays differently from a generated one is a trap for whoever
## balances a scenario against it:
##
## | the game's generator | here |
## |---|---|
## | town centre, origin = `centre - footprint / 2`, footprint read from `buildings.json` | same, and the footprint is read the same way |
## | 5 villagers + 1 `unit.scout_cavalry` on a ring at Chebyshev radius 7 | same count, same ring, same radius |
## | stone, gold, berries and trees within walking distance, placed by noise with retries | **a fixed cluster at documented distances** — see `_ECONOMY` |
##
## ⚠️ **THE ECONOMY NUMBERS BELOW ARE PROVISIONAL AND ARE THE TOOL'S OWN.** The generator
## chooses them with a `RandomNumberGenerator` and several passes of retry logic that only
## make sense when nobody is looking; an author IS looking, and 16.3's palette is where they
## place resources deliberately. This exists so the first authored map is playable rather
## than a dead economy — delete the cluster and place your own, which is the point of a tool.
class_name StartLayout
extends RefCounted

const TOWN_CENTRE := &"building.town_center"
const VILLAGER := &"unit.villager"
const SCOUT := &"unit.scout_cavalry"

## `MapGen.STARTING_VILLAGERS`, which is 5. Not readable from here -- `map_gen.gd` is sim
## code and is not in `format/` -- so it is written down with the name of the constant it
## must equal. **If a start ever opens with the wrong number of villagers, this is the line.**
const VILLAGERS := 5

## `MapGenerator.UNIT_RING_RADIUS`. The town centre's footprint reaches radius 5, so 7 leaves
## two clear tiles between the wall and the nearest unit -- the game's own note records that
## radius 4 put every villager INSIDE its own town centre.
const UNIT_RING_RADIUS := 7

## The provisional opening: `{def, count, radius}`, all Chebyshev radii from the start centre.
##
## Ordered outward, and every radius is past the unit ring so nothing is placed on top of a
## villager. Kinds are the four the game's generator guarantees, because a start missing one
## of them is a start that cannot reach an age.
const _ECONOMY := [
	{"def": &"res.berry_bush", "count": 5, "radius": 10},
	{"def": &"res.tree", "count": 8, "radius": 12},
	{"def": &"res.gold_mine", "count": 2, "radius": 14},
	{"def": &"res.stone", "count": 2, "radius": 15},
]


## The key every entity this places is tagged with, naming the player whose start put it
## there.
##
## ⚠️ **IT EXISTS FOR THE GAIA HALF, AND WITHOUT IT MOVING A START LITTERS THE MAP.** A base
## and its units are `player`-owned, so `MapDocument.remove_start()` can find them by owner —
## but **every resource node is gaia (`player: 0`)**, indistinguishable from a tree an author
## placed on purpose. A test caught the consequence: placing a start twice left the first
## cluster behind and the entity count went 24 → 40. Deleting "gaia things near the start"
## instead was the alternative and is worse — it would eat the author's own trees at 16.3.
##
## ⚠️ **`MapFile` DROPS THIS ON SAVE, BY DESIGN, AND THAT IS PINNED BY A TEST.**
## `MapData.to_dict()` writes exactly `def_id`, `player`, `x`, `y` and `size_class`, so the
## tag is **session-only editing metadata** and a reloaded map's clusters are ordinary gaia
## nodes — which is what they are. Nothing in the format changes, nothing the game reads is
## affected, and no hash moves.
const ORIGIN_KEY := "origin_start"


## Place player `player`'s whole start on `data`, centred on `centre`.
##
## Assumes the caller has already cleared this player's previous start --
## `MapDocument.place_start()` does. Placing twice without that would double the base.
static func place(data: MapData, player: int, centre: Vector2i) -> void:
	var claimed := data.claimed_tiles()
	var before := data.entities.size()
	_place_base(data, claimed, player, centre)
	_place_units(data, claimed, player, centre)
	_place_economy(data, claimed, centre)
	# Tagged in one sweep afterwards rather than at each `add_entity` call, because
	# `add_entity` is `MapData`'s -- a verbatim, hash-checked copy -- and is not ours to widen.
	for i in range(before, data.entities.size()):
		data.entities[i][ORIGIN_KEY] = player


static func _place_base(data: MapData, claimed: Dictionary, player: int,
		centre: Vector2i) -> void:
	# THE FOOTPRINT IS READ FROM THE ROSTER, never assumed. The game's own note records the
	# prototype reserving 5x5 for a building that is 10x10 in the data.
	var bd: BuildingDef = GameDataRegistry.building(TOWN_CENTRE)
	var footprint := bd.footprint if bd != null else Vector2i(10, 10)
	var origin := centre - footprint / 2
	data.add_entity(TOWN_CENTRE, player, origin)
	for t in MapData.footprint_rect_of(data.entities[data.entities.size() - 1]):
		claimed[t] = true


static func _place_units(data: MapData, claimed: Dictionary, player: int,
		centre: Vector2i) -> void:
	var ring := _ring_tiles(centre, UNIT_RING_RADIUS)
	var wanted := VILLAGERS + 1               # the villagers, plus the scout
	# EVERY OTHER POSITION, so no two units start adjacent -- the generator's rule.
	var step := maxi(2, ring.size() / maxi(1, wanted))
	var placed := 0
	var i := 0
	while placed < wanted and i < ring.size():
		var t: Vector2i = ring[i]
		i += step
		if not _free(data, claimed, t):
			continue
		claimed[t] = true
		# The scout LAST, matching the generator, so a map with room for only some of the
		# opening loses the scout rather than a villager.
		data.add_entity(SCOUT if placed == wanted - 1 else VILLAGER, player, t)
		placed += 1


static func _place_economy(data: MapData, claimed: Dictionary, centre: Vector2i) -> void:
	for entry in _ECONOMY:
		var def_id: StringName = entry["def"]
		var rd: ResourceDef = GameDataRegistry.resource_def(def_id)
		if rd == null:
			# A ROSTER THAT HAS MOVED ON IS NOT A CRASH. `res.stone` could be renamed
			# tomorrow; a start missing its stone is a map the author can fix, and a tool
			# that died on it is not.
			continue
		var ring := _ring_tiles(centre, int(entry["radius"]))
		var wanted := int(entry["count"])
		var step := maxi(1, ring.size() / maxi(1, wanted))
		var placed := 0
		var i := 0
		while placed < wanted and i < ring.size():
			var t: Vector2i = ring[i]
			i += step
			# GAIA OWNS EVERY RESOURCE NODE (`player: 0`), which is what keeps them out of
			# `seats()`' highest-player arithmetic and out of `remove_start`'s sweep.
			if _fits(data, claimed, t, rd.footprint_for_size(0)):
				for tile in _rect_tiles(t, rd.footprint_for_size(0)):
					claimed[tile] = true
				data.add_entity(def_id, 0, t)
				placed += 1
	return


# ── geometry ────────────────────────────────────────────────────────────────

## The tiles on a Chebyshev ring of `radius` around `centre`, clockwise from the top-left.
##
## A square ring rather than a circle, because Chebyshev is the metric the sim measures
## ranges in -- a circular ring would put the corners further away in game terms than the
## sides, which is the kind of asymmetry a player feels and cannot name.
static func _ring_tiles(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(centre)
		return out
	for x in range(centre.x - radius, centre.x + radius + 1):
		out.append(Vector2i(x, centre.y - radius))
	for y in range(centre.y - radius + 1, centre.y + radius + 1):
		out.append(Vector2i(centre.x + radius, y))
	for x in range(centre.x + radius - 1, centre.x - radius - 1, -1):
		out.append(Vector2i(x, centre.y + radius))
	for y in range(centre.y + radius - 1, centre.y - radius, -1):
		out.append(Vector2i(centre.x - radius, y))
	return out


static func _rect_tiles(origin: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(origin.y, origin.y + maxi(1, footprint.y)):
		for x in range(origin.x, origin.x + maxi(1, footprint.x)):
			out.append(Vector2i(x, y))
	return out


## In bounds, walkable ground, and nothing already on it.
##
## `is_ground_passable` is asked of `MapData`, which asks `SimMap`'s own tables -- so a unit
## is never authored standing in water, and the tool cannot disagree with the grid the map
## becomes.
static func _free(data: MapData, claimed: Dictionary, t: Vector2i) -> bool:
	return data.in_bounds(t) and data.is_ground_passable(t) and not claimed.has(t)


static func _fits(data: MapData, claimed: Dictionary, origin: Vector2i,
		footprint: Vector2i) -> bool:
	for t in _rect_tiles(origin, footprint):
		if not _free(data, claimed, t):
			return false
	return true
