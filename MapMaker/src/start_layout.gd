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

## How far in or out of its declared radius a kind may be placed when the declared ring cannot
## supply it (2026-09-04).
##
## ⚠️ **THIS EXISTS BECAUSE THE FIRST AUTHORED MAP CAME OUT UNPLAYABLE AND SAVED WITHOUT A
## MURMUR.** The owner dropped two starts on a 48x48 map at (6,6) and (35,35) — a perfectly
## reasonable thing to do, and `MIN_SIZE` is 48 — and got **9 of 24 entities for player 1 and
## 21 for player 2**: no scout and no stone for one, no gold at all for the other. Neither
## could have climbed the age ladder.
##
## Two faults, and the second is the nastier:
##
##   1. **Off-map ring tiles were skipped and never replaced.** Both starts sit within 15 tiles
##      of an edge, so the outer rings run to (-9,-9) and (50,50).
##   2. **The ring was SAMPLED, not walked.** `step = ring.size() / wanted` gave 2 gold on a
##      radius-14 ring exactly **two attempts**: one landed on a tile the other player's
##      cluster already held (29 tiles apart, so their outer rings intersect) and the other was
##      off-map. Two misses and the whole resource kind vanished.
##
## Bounded rather than unlimited, because the economy's whole promise is *within walking
## distance*: a stone mine found 20 tiles away is worse than an honest warning that there was
## no room for one. 6 is enough to clear a map edge at these radii and not enough to move a
## resource somewhere surprising.
const RADIUS_SLACK := 6


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
	var wanted := VILLAGERS + 1               # the villagers, plus the scout
	var placed := 0
	for t in _candidates(centre, UNIT_RING_RADIUS, wanted):
		if placed >= wanted:
			break
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
		var footprint := rd.footprint_for_size(0)
		var wanted := int(entry["count"])
		var placed := 0
		for t in _candidates(centre, int(entry["radius"]), wanted):
			if placed >= wanted:
				break
			if not _fits(data, claimed, t, footprint):
				continue
			# GAIA OWNS EVERY RESOURCE NODE (`player: 0`), which is what keeps them out of
			# `seats()`' highest-player arithmetic and out of `remove_start`'s sweep.
			for tile in _rect_tiles(t, footprint):
				claimed[tile] = true
			data.add_entity(def_id, 0, t)
			placed += 1


# ── where things may go ─────────────────────────────────────────────────────

## Every tile worth trying for `wanted` things around `centre`, best first.
##
## ⚠️ **THE WHOLE RING IS OFFERED, NOT A SAMPLE OF IT — THAT WAS THE BUG.** The old code
## stepped `ring.size() / wanted` tiles at a time, so two gold mines got exactly two chances
## and a single collision or off-map tile lost the kind outright. See `RADIUS_SLACK` for the
## map that proved it. Now the caller walks this list until it has what it needs, so a
## placement fails only when there is genuinely nowhere.
##
## **THE SPREAD IS PRESERVED, WHICH IS WHY THIS IS NOT JUST THE RING IN ORDER.** `_spread`
## puts `wanted` evenly-spaced tiles first, so a start that has room looks exactly as it did —
## a fan of villagers, resources around the compass — and the remaining tiles follow as
## fallbacks. Walking the ring in raw order instead would clump the whole opening into one arc.
##
## Radii are tried `r, r+1, r-1, r+2, r-2, …` out to `RADIUS_SLACK`, skipping anything that
## would land inside the base: a ring at or under `UNIT_RING_RADIUS` overlaps the town centre's
## own footprint and the units standing around it.
static func _candidates(centre: Vector2i, radius: int, wanted: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for step in _radius_order():
		var r := radius + step
		# A UNIT RING MAY BE ITS OWN RADIUS BUT NOTHING MAY GO TIGHTER. `>=` rather than `>`
		# would forbid the unit ring itself, which is the one caller that legitimately sits
		# there.
		if r < UNIT_RING_RADIUS or r <= 0:
			continue
		out.append_array(_spread(_ring_tiles(centre, r), wanted))
	return out


## `[0, 1, -1, 2, -2, …]` out to `RADIUS_SLACK`. Outward first at each distance, because a
## resource slightly further out is a smaller change to a start than one tucked in behind the
## villagers.
static func _radius_order() -> Array[int]:
	var out: Array[int] = [0]
	for d in range(1, RADIUS_SLACK + 1):
		out.append(d)
		out.append(-d)
	return out


## `ring` reordered so the first `wanted` entries are evenly spaced around it, then the rest.
##
## The even-spacing half replaces the generator's "every other position" rule, which existed so
## no two units start adjacent: at 6 units on a 56-tile ring the spacing is every ninth tile.
## **The fallback half CAN place two things adjacent**, and that is the right trade — a start
## with six units standing close together is playable, and a start missing its scout is not.
static func _spread(ring: Array[Vector2i], wanted: int) -> Array[Vector2i]:
	if wanted <= 1 or ring.size() <= wanted:
		return ring
	var out: Array[Vector2i] = []
	var picked := {}
	for k in range(wanted):
		# Integer arithmetic on purpose -- the sim is deterministic and so is this, and two
		# machines authoring the same map must produce the same file (PLAN.md 11.3).
		var i := (k * ring.size()) / wanted
		picked[i] = true
		out.append(ring[i])
	for i in range(ring.size()):
		if not picked.has(i):
			out.append(ring[i])
	return out


# ── did each start actually get its opening? (16.4b) ────────────────────────

## One sentence per start that is short of what `place()` promises, or empty when every start
## is whole. Warnings, never refusals — see below.
##
## ⚠️ **THE TOOL SAVED AN UNPLAYABLE MAP WITHOUT A MURMUR, AND THAT IS WHAT THIS IS FOR.** The
## placement bug `RADIUS_SLACK` describes is fixed, but the underlying exposure is not: a map
## can still be too cramped, too crowded or too watery for a start to fit, and the author is
## the last person who should find out from a match. `MapValidator` on the game side answers a
## different question — is this file *loadable* — and cannot answer this one, because "a start
## owes 24 things" is `StartLayout`'s promise and lives nowhere else.
##
## ⚠️ **A WARNING AND NOT A REFUSAL, DELIBERATELY.** `_ECONOMY`'s own header says to delete the
## cluster and place your own, and 16.3's palette is the row that makes that pleasant. An
## author who has done exactly that must not be blocked from saving by a checker counting
## berry bushes. So this reports and the save proceeds.
##
## **COUNTED BY OWNERSHIP AND PROXIMITY, NOT BY `ORIGIN_KEY`.** The tag would be easier and is
## the wrong tool: `MapFile` drops it on save, so it exists only in the session that placed the
## start and a map opened by 16.4a would audit as empty. Owned things are counted by player id;
## gaia nodes are attributed to the nearest start, which is the same rule a player reads off
## the screen.
static func audit(data: MapData) -> Array[String]:
	var out: Array[String] = []
	for i in data.starts.size():
		var centre: Vector2i = data.starts[i]
		if centre.x < 0:
			continue
		var short := _shortfalls(data, i + 1, centre)
		if not short.is_empty():
			out.append("P%d's start is short: %s" % [i + 1, ", ".join(short)])
	return out


## `["3 of 5 villagers", "no scout"]` for one start, or empty when it is whole.
static func _shortfalls(data: MapData, player: int, centre: Vector2i) -> Array[String]:
	var got := _tally(data, player, centre)
	var out: Array[String] = []
	_note_short(out, got, TOWN_CENTRE, 1, "town centre", "town centres")
	_note_short(out, got, VILLAGER, VILLAGERS, "villager", "villagers")
	_note_short(out, got, SCOUT, 1, "scout", "scouts")
	for entry in _ECONOMY:
		var def_id: StringName = entry["def"]
		if GameDataRegistry.resource_def(def_id) == null:
			continue          # not in the roster any more; `_place_economy` skipped it too
		var label := GameDataRegistry.display_name(def_id)
		_note_short(out, got, def_id, int(entry["count"]), label, label)
	return out


static func _note_short(out: Array[String], got: Dictionary, def_id: StringName,
		want: int, one: String, many: String) -> void:
	var n := int(got.get(def_id, 0))
	if n >= want:
		return
	# "NO STONE" READS BETTER THAN "0 OF 2 STONE", and the difference matters: a missing kind
	# is a start that cannot reach an age, while a short one is merely poorer.
	out.append("no %s" % one if n == 0 else "%d of %d %s" % [n, want, many])


## What is actually within reach of this start, by def id.
static func _tally(data: MapData, player: int, centre: Vector2i) -> Dictionary:
	var got := {}
	for e in data.entities:
		var owner_id := int(e.get("player", 0))
		# ⚠️ `tile`, NOT `x`/`y`. An in-memory entity carries a `Vector2i` under `tile`;
		# `x` and `y` exist only in the SAVED dictionary, which `MapData.to_dict()` builds by
		# splitting that vector. Reading `x` here returned 0 for everything, so every gaia node
		# was attributed to whichever start was nearest (0,0) and the audit reported the other
		# player as having no resources at all -- a warning that looked exactly like the real
		# bug it was written to catch.
		var t: Vector2i = e.get("tile", Vector2i.ZERO)
		var mine := false
		if owner_id == player:
			# Owned outright. Position is not consulted: a villager the author has since
			# dragged across the map is still that player's villager.
			mine = true
		elif owner_id == 0:
			mine = _nearest_start(data, t) == player
		if mine:
			var id := StringName(e.get("def_id", &""))
			got[id] = int(got.get(id, 0)) + 1
	return got


## Which player's start a gaia node is nearest to, by the Chebyshev metric the sim measures
## range in. 0 when the map has no starts at all.
##
## Ties go to the LOWER player number, which is arbitrary and has to be *stable*: a node
## counted for both players would make two short starts look whole.
static func _nearest_start(data: MapData, t: Vector2i) -> int:
	var best := 0
	var best_d := -1
	for i in data.starts.size():
		var s: Vector2i = data.starts[i]
		if s.x < 0:
			continue
		var d := maxi(absi(t.x - s.x), absi(t.y - s.y))
		if best_d < 0 or d < best_d:
			best_d = d
			best = i + 1
	return best


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
