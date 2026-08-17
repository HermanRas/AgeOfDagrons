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
## COST is the thing to watch here, since it is per player per tick rather than per
## world. One pass to decay the grid (4096 bytes on the debug map) plus, per entity,
## the tiles in a box around its footprint: 81 for a villager at los 4, 676 for a
## 10x10 town centre at los 8. A settlement of thirty is a few thousand byte writes
## at 10 Hz, which is why this is a flat array and not a set of tiles.
class_name VisionSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	if w.map == null:
		return
	for p in w.players:
		_recompute(w, p)


func _recompute(w: SimWorld, p: SimPlayer) -> void:
	var count := w.map.size.x * w.map.size.y
	if count <= 0:
		return
	if p.vision.size() != count:
		# First tick, or a map that changed size under us. Allocating here rather
		# than in SimWorld.setup() is what gives "empty means no fog" its meaning --
		# see SimPlayer.vision's own header.
		p.vision.resize(count)
		p.vision.fill(SimPlayer.Fog.UNSEEN)

	for i in range(count):
		if p.vision[i] == SimPlayer.Fog.VISIBLE:
			p.vision[i] = SimPlayer.Fog.EXPLORED

	for e in w.entities.values():
		if not e.alive or e.owner_id != p.id:
			continue
		if not (e is SimUnit or e is SimBuilding):
			continue
		_reveal(w, p, _rect_of(e), e.vision_range)


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
static func _reveal(w: SimWorld, p: SimPlayer, rect: Rect2i, range_tiles: int) -> void:
	if range_tiles < 0:
		return
	var r2 := range_tiles * range_tiles
	var box := rect.grow(range_tiles)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var i := w.map.index_of(Vector2i(x, y))
			if i < 0:
				continue
			# Gap from the tile to the nearest point of the footprint, per axis: 0
			# while inside it, so every tile the building stands on is always seen.
			var dx := maxi(0, maxi(rect.position.x - x, x - (rect.end.x - 1)))
			var dy := maxi(0, maxi(rect.position.y - y, y - (rect.end.y - 1)))
			if dx * dx + dy * dy <= r2:
				p.vision[i] = SimPlayer.Fog.VISIBLE


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
