## Recomputes every player's fog of war (PLAN.md 2.5): which tiles they can see
## right now, and which they have ever seen. Writes `SimPlayer.vision` and nothing
## else.
##
## `SnapshotSystem` is the half that matters. Vision on its own is a drawing hint;
## vision used to FILTER THE SNAPSHOT is a security property (PLAN.md 5.1 step 6:
## "the server must not send a client entities it cannot see"), and it is the reason
## this lives in the sim rather than in the view. A client that decided its own fog
## would be a client that could decide not to have any.
##
## RECOMPUTED FROM SCRATCH every tick, exactly like `PopulationSystem` and for the
## same reason: the alternative is adjusting the grid as units move, which means
## un-revealing tiles a unit has left, which means knowing whether anything ELSE
## still sees them. That is a reference count per tile per player, and one missed
## decrement is a permanent hole in the fog that nothing on screen explains.
##
## EXPLORED IS STICKY, so the recount is not symmetrical: VISIBLE decays to EXPLORED
## every tick and is re-marked by whatever can see it, while EXPLORED never returns
## to UNSEEN. Ground you have walked past stays drawn forever, which is what every
## RTS does and what makes the third state worth having.
##
## Runs after `DeathSystem`, beside `PopulationSystem`, for its reason too: a unit
## killed this tick grants no vision, and the scout you just lost should not still
## be lighting up the map in the snapshot that tells you it died.
##
## COST IS PER PLAYER PER TICK, which is what makes it the most expensive system here
## and why the decay is incremental.
##
## The obvious implementation decays the whole grid each tick: set every VISIBLE tile
## back to EXPLORED, then re-mark. That is O(tiles x players), and **measured on an
## 8-player 192x192 generated map it was the single biggest cost in the tick** -- 8
## players x 36,864 tiles is ~295,000 byte writes before any vision is computed at all,
## and the whole tick came to 39.7 ms against PLAN.md 3.1's 5 ms budget.
##
## So the tiles marked VISIBLE last tick are REMEMBERED and only those are decayed,
## which makes the decay the same order as the marking: per entity, the tiles in a box
## around its footprint (81 for a villager at los 4, 676 for a 10x10 town centre at los
## 8). The cache is derived state and deliberately not in `state_hash()` -- `p.vision`
## is the answer, this is only how it is reached, and it is rebuilt from scratch if it
## is ever missing.
class_name VisionSystem
extends SimSystem

## Ticks between recomputes. **Fog does not need 10 Hz.**
##
## Even after the tight loop below, vision is the most expensive system in the tick
## (17.9 ms of an 8-player map's total), and it is also the one nobody can see running:
## at 2 the fog updates 5 times a second, which is imperceptible against units that
## interpolate at display rate. What it costs is up to 100 ms of lag before a newly
## spotted enemy enters the snapshot -- a delay, never a leak, since the filter still
## refuses everything the grid does not yet mark visible.
##
## Keyed off `w.tick` rather than an internal counter, so it stays deterministic and
## two hosts recompute on exactly the same ticks (PLAN.md 7.1).
const VISION_INTERVAL := 2

## player id -> the grid indices set VISIBLE on the previous recompute.
var _visible_last: Dictionary = {}


func process_tick(w: SimWorld) -> void:
	if w.map == null:
		return
	var due := w.tick % VISION_INTERVAL == 0
	for p in w.players:
		# A player with no fog yet is ALWAYS computed, whatever the interval says.
		# `SimWorld.step()` increments the tick before running systems, so the very
		# first step is tick 1 and an interval of 2 would skip it -- leaving a world
		# that has been stepped once with no vision at all, which broke thirteen fog
		# tests the moment the interval landed and would have shown up in play as a
		# match that opens blind for its first 100 ms.
		if due or p.vision.is_empty():
			_recompute(w, p)


func _recompute(w: SimWorld, p: SimPlayer) -> void:
	var count := w.map.size.x * w.map.size.y
	if count <= 0:
		return
	var fresh := p.vision.size() != count
	if fresh:
		# First tick, or a map that changed size under us. Allocating here rather
		# than in SimWorld.setup() is what gives "empty means no fog" its meaning --
		# see SimPlayer.vision's own header.
		p.vision.resize(count)
		p.vision.fill(SimPlayer.Fog.UNSEEN)
		_visible_last.erase(p.id)

	# Decay only what was lit last tick. Falls back to a full sweep when the cache is
	# missing -- a fresh grid, or a system that has not run for this player before --
	# so a lost cache costs one expensive tick rather than leaving stale VISIBLE tiles
	# that nothing would ever clear.
	if _visible_last.has(p.id):
		var previous: PackedInt32Array = _visible_last[p.id]
		for i in previous:
			if p.vision[i] == SimPlayer.Fog.VISIBLE:
				p.vision[i] = SimPlayer.Fog.EXPLORED
	else:
		for i in range(count):
			if p.vision[i] == SimPlayer.Fog.VISIBLE:
				p.vision[i] = SimPlayer.Fog.EXPLORED

	var lit := PackedInt32Array()
	for e in w.entities.values():
		if not e.alive or e.owner_id != p.id:
			continue
		if not (e is SimUnit or e is SimBuilding):
			continue
		_reveal(w, p, _rect_of(e), e.vision_range, lit)
	_visible_last[p.id] = lit


## Mark every tile within `range_tiles` of `rect` as VISIBLE.
##
## MEASURED TO THE FOOTPRINT, not to the centre tile, which for a unit is the same
## thing and for a town centre is not: a 10x10 building looking 8 tiles from its
## middle would see barely three tiles past its own walls, and the player would have
## a blind spot exactly where their base is.
##
## Euclidean, so vision is a circle (a rounded rectangle around a footprint) rather
## than the square a Chebyshev gap would give. Compared squared, in integers -- no
## `sqrt`, nothing to round, and nothing that can differ between two machines
## (PLAN.md 7.1).
## `lit` collects every index set, for next tick's incremental decay. An index can be
## appended twice when two of a player's own entities see the same tile; that is
## harmless -- decaying a tile twice is idempotent -- and cheaper than de-duplicating.
##
## **DELIBERATELY WRITTEN AS A TIGHT LOOP**, which is not this codebase's usual style
## and is justified by measurement: at ~1,150 tiles per player per tick this is the
## hottest loop in the sim, and the readable version cost **32 of 55 ms** on an
## 8-player map. What made it expensive was not the arithmetic but the CALLS -- a
## `SimMap.index_of()` per tile (itself calling `in_bounds()` and `_index()`), a
## `Vector2i` allocated per tile, and four `maxi()` calls for the distance. All of that
## is inlined here, and the box is clamped to the map ONCE instead of testing every
## tile for bounds.
##
## `p.vision[i]` is written directly rather than through a local: `PackedByteArray` is
## copy-on-write, so `var v := p.vision` then `v[i] = x` would quietly mutate a copy
## and leave the player's own fog untouched.
static func _reveal(w: SimWorld, p: SimPlayer, rect: Rect2i, range_tiles: int,
		lit: PackedInt32Array) -> void:
	if range_tiles < 0:
		return
	var size := w.map.size
	var r2 := range_tiles * range_tiles

	# The footprint's own extents, so a tile inside it measures a gap of 0 on that axis
	# and every tile a building stands on is always seen.
	var left := rect.position.x
	var right := rect.end.x - 1
	var top := rect.position.y
	var bottom := rect.end.y - 1

	var x0 := maxi(0, left - range_tiles)
	var x1 := mini(size.x - 1, right + range_tiles)
	var y0 := maxi(0, top - range_tiles)
	var y1 := mini(size.y - 1, bottom + range_tiles)

	for y in range(y0, y1 + 1):
		var dy := 0
		if y < top:
			dy = top - y
		elif y > bottom:
			dy = y - bottom
		var dy2 := dy * dy
		if dy2 > r2:
			continue
		var row := y * size.x
		for x in range(x0, x1 + 1):
			var dx := 0
			if x < left:
				dx = left - x
			elif x > right:
				dx = x - right
			if dx * dx + dy2 > r2:
				continue
			var i := row + x
			p.vision[i] = SimPlayer.Fog.VISIBLE
			lit.append(i)


static func _rect_of(e: SimEntity) -> Rect2i:
	if e is SimBuilding:
		return (e as SimBuilding).footprint_rect()
	return Rect2i(e.tile(), Vector2i.ONE)


# ── readers ─────────────────────────────────────────────────────────────────
#
# Everything below is for SnapshotSystem and for tests. They take a SimPlayer
# rather than an id so a caller that already has one does not pay for a lookup per
# entity -- the snapshot filter asks these once per entity per tick.

## What `p` currently makes of `t`. UNSEEN out of bounds, and VISIBLE when `p` has
## no fog at all (see SimPlayer.vision): a world that has never been stepped shows
## everything rather than nothing.
static func fog_at(w: SimWorld, p: SimPlayer, t: Vector2i) -> int:
	if p == null or w.map == null:
		return SimPlayer.Fog.VISIBLE
	if p.vision.is_empty():
		return SimPlayer.Fog.VISIBLE
	var i := w.map.index_of(t)
	return p.vision[i] if i >= 0 else SimPlayer.Fog.UNSEEN


## True if ANY tile of `rect` is currently visible. Any, not all: a town centre
## seen from one corner is a town centre you can see, and requiring the whole
## footprint would make big buildings vanish while their owner was standing next
## to them.
static func can_see_rect(w: SimWorld, p: SimPlayer, rect: Rect2i) -> bool:
	return _rect_reaches(w, p, rect, SimPlayer.Fog.VISIBLE)


## True if any tile of `rect` has ever been seen.
static func has_explored_rect(w: SimWorld, p: SimPlayer, rect: Rect2i) -> bool:
	return _rect_reaches(w, p, rect, SimPlayer.Fog.EXPLORED)


static func _rect_reaches(w: SimWorld, p: SimPlayer, rect: Rect2i, least: int) -> bool:
	if p == null or p.vision.is_empty():
		return true
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if fog_at(w, p, Vector2i(x, y)) >= least:
				return true
	return false
