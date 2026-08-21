## The fog a client draws, computed here rather than shipped in every snapshot (12.1f).
##
## WHY THIS EXISTS. `vision` was one byte per tile of the whole board, sent to every
## player every tick. Measured with `dev_preview/preview_wire_size.tscn`:
##
##     board       tiles   total    vision  entities  frags
##     96x96       9,216   28,768    9,224    18,512     21
##     192x192    36,864   53,928   36,872    16,024     39
##
## On the 8-player board the lobby now offers it was 68% of the packet -- and it is a
## function of the MAP, not of the match, so it never gets smaller as anything else is
## optimised. Two players at 10 Hz was roughly 1 MB/s leaving the host, over WiFi, to a
## phone, against a 1392-byte MTU. Worse, `VisionSystem.VISION_INTERVAL` is 2, so half
## those grids were byte-for-byte identical to the one before them.
##
## THIS DOES NOT WEAKEN THE SECURITY PROPERTY, which is the objection to answer first.
## The grid on the wire was for DRAWING. The rule that matters -- "the server must not
## send a client entities it cannot see" (PLAN.md 5.1 step 6) -- is enforced in
## `SnapshotSystem._entry_for`, server-side, and has not moved. The server still computes
## every player's vision, because it still has to decide what to send them. What stopped
## is transmitting the picture. A client was never trusted to filter; it was handed a
## bitmap to paint, and now it paints its own.
##
## The two inputs are both already here: the map came once in the `MatchConfig` (12.1b),
## and a player's own entities are always sent in full whatever the fog says -- which is
## `_entry_for`'s first rule and not a coincidence. `vision_range` is NOT on the wire and
## does not need to be: it comes from `def_id` through `GameDataRegistry`, the same data
## file the server read it from. Static content, identical on both sides, already shipped.
##
## ── the known drawback, and the option not taken ────────────────────────────
##
## **Option 1, taken here: the client computes everything.** Zero bytes on the wire,
## forever. Its cost is that EXPLORED is cumulative: it is built up a tick at a time, and
## snapshots are `unreliable_ordered`, so a dropped snapshot is a tick of accumulation
## missed -- a thin rim of tiles this client believes it has never seen. It stays wrong
## until something of yours passes there again, at which point it corrects itself. Fog
## only: entity filtering is unaffected, because that is the server's answer and arrives
## with the entities. The visible symptom is a sliver of dark on ground you walked past
## during a lost packet.
##
## **Option 2, not taken: the server sends fog CHANGES on a reliable channel.** Tens of
## bytes rather than tens of thousands -- `FogOverlay`'s own header notes the difference
## between two ticks is the rim around whatever moved -- and it cannot drift, because
## reliable delivery means the client's grid is the server's grid. The cost is a second
## channel with its own ordering and its own reconnect story, and a client that must not
## draw fog until the first fog message lands.
##
## Option 1 was chosen because the failure mode is a few stale tiles rather than a
## mechanism, and because it costs nothing at all rather than a little. **If those slivers
## ever become a complaint, option 2 is the reinvestment** -- and this class is where it
## would land, since everything above `apply()` would stay as it is.
class_name ClientFog
extends RefCounted

## Row-major `SimPlayer.Fog` bytes, exactly the shape `FogOverlay` and `Minimap` already
## take. Owned here rather than passed around because `PackedByteArray` is copy-on-write:
## a function that received it and assigned to an element would mutate a copy.
var cells: PackedByteArray = PackedByteArray()

var _size: Vector2i = Vector2i.ZERO

## Indices lit on the previous update, so the decay costs the same order as the marking
## rather than a sweep of the whole board. The same reasoning -- and the same measurement
## -- as `VisionSystem`'s own cache.
var _visible_last: PackedInt32Array = PackedInt32Array()


## Give it the board. Until this is called there is no fog, and `cells` is empty -- which
## every reader already understands as "draw none" (see `SimPlayer.vision`).
func setup(size: Vector2i) -> void:
	_size = size
	var count := size.x * size.y
	if count <= 0:
		cells = PackedByteArray()
		return
	cells.resize(count)
	cells.fill(SimPlayer.Fog.UNSEEN)
	_visible_last = PackedInt32Array()


## Recompute from this tick's snapshot entries -- `snap["updated"]`, the RAW wire entries,
## not `GameView._facts`.
##
## THAT DISTINCTION IS A BUG I ALREADY MADE. `_facts` is the view's own processed form: it
## carries `tile`, already divided down to whole tiles, and no `pos` at all. Reading a
## missing `pos` from it gave every entity tile (0, 0) and lit a wedge of fog at the map
## origin while the player's actual base sat in the dark -- caught by looking at a
## screenshot, since every test in `test_client_fog` feeds it wire entries and passed.
##
## The wire entries carry `pos` in SUB-TILE units, which is what the server's own
## `SimEntity.tile()` and `SimBuilding.origin_tile()` work from, so working from the same
## field is what keeps the two arithmetics identical.
##
## A player's own entities are in `updated` every tick whatever the fog says -- that is
## `SnapshotSystem._entry_for`'s first rule -- so this sees all of them and needs no
## memory of previous snapshots.
##
## Asymmetric, like the server's: VISIBLE decays to EXPLORED every update and is re-marked
## by whatever can see it, while EXPLORED never returns to UNSEEN. Ground you have walked
## past stays drawn.
func apply(updated: Array, local_player_id: int) -> void:
	if cells.is_empty():
		return

	for i in _visible_last:
		if cells[i] == SimPlayer.Fog.VISIBLE:
			cells[i] = SimPlayer.Fog.EXPLORED

	var lit := PackedInt32Array()
	for entry in updated:
		var f: Dictionary = entry
		if int(f.get("owner_id", 0)) != local_player_id:
			continue
		if not bool(f.get("alive", false)):
			# A unit killed this tick grants no vision, which is the rule `VisionSystem`
			# follows for the same reason: the scout you just lost should not still be
			# lighting up the map.
			continue
		var range_tiles := _range_of(f)
		if range_tiles <= 0:
			continue
		for i in VisionSystem.tiles_in_range(_size, _rect_of(f), range_tiles):
			cells[i] = SimPlayer.Fog.VISIBLE
			lit.append(i)
	_visible_last = lit


## How far this entity sees, from the shipped data rather than from the wire.
##
## Buildings and units both read `los` off their own def, which is where `SimWorld` read
## it when it spawned them. Nothing changes `vision_range` at runtime today; the day
## something does -- a scouting upgrade -- it has to arrive in the snapshot, and this is
## the function that would have to read it from there instead.
func _range_of(f: Dictionary) -> int:
	var def_id := StringName(f.get("def_id", &""))
	var unit := GameDataRegistry.unit(def_id)
	if unit != null:
		return unit.los
	var building := GameDataRegistry.building(def_id)
	if building != null:
		return building.los
	return 0


## The tiles this entity occupies, measured the way the server measures them: a unit is
## its own tile, a building is its whole footprint. A 10x10 town centre looking 8 tiles
## from its centre would leave a blind spot exactly where your base is.
## MIRRORS `SimEntity.tile()` AND `SimBuilding.origin_tile()` deliberately, arithmetic and
## all, because the snapshot carries the sub-tile `pos` those methods work from but not the
## tile they produce. Written out rather than approximated: `origin_tile()` subtracts half
## a footprint before dividing, and rounding it differently here would slide a big
## building's vision half a tile off the server's.
func _rect_of(f: Dictionary) -> Rect2i:
	var pos := _pos_of(f)
	var building := GameDataRegistry.building(StringName(f.get("def_id", &"")))
	if building == null:
		return Rect2i(pos / SimWorld.SUBTILE, Vector2i.ONE)

	# A building's `pos` is its footprint CENTRE (2.3), so the origin comes back out the
	# way `SimBuilding.origin_tile()` takes it out.
	var footprint: Vector2i = building.footprint
	var half := Vector2i(footprint.x * SimWorld.SUBTILE,
			footprint.y * SimWorld.SUBTILE) / 2
	return SimMap.footprint_rect((pos - half) / SimWorld.SUBTILE, footprint)


## `pos` is a `Vector2i` on the wire since 12.1f. The dictionary shape is still accepted
## because a fixture or a replay written against the old format should load rather than
## quietly read (0, 0) -- the exact failure this class shipped with for an afternoon, and
## the reason `GameView._sub_pos` tolerates both too.
func _pos_of(f: Dictionary) -> Vector2i:
	var p: Variant = f.get("pos", Vector2i.ZERO)
	if p is Vector2i:
		return p
	if p is Dictionary:
		return Vector2i(int((p as Dictionary).get("x", 0)), int((p as Dictionary).get("y", 0)))
	return Vector2i.ZERO
