## Client-side root of the view layer (PLAN.md 6.3, 8). Turns a snapshot
## Dictionary (PLAN.md 7.2) into pooled EntityView updates and drives their
## interpolation every frame. Never touches SimWorld -- everything it knows
## comes from apply_snapshot().
class_name GameView
extends Node2D

var pool: EntityViewPool = EntityViewPool.new()
var terrain: TerrainLayer = TerrainLayer.new()
var selection: Selection = Selection.new()

var _last_tick: int = -1

## Last known snapshot facts per entity, keyed by id: {tile, owner_id, def_id,
## hp, max_hp, footprint}. Kept because picking and the detail panel both need to
## answer questions about an entity that the *view* nodes do not carry -- who owns
## it, what it is called, how hurt it is -- and the view may not reach into the sim
## to ask (PLAN.md 4).
var _facts: Dictionary = {}


func _ready() -> void:
	# Terrain first: it is a sibling of the entity pool, not a parent, so draw
	# order between the two is tree order and the ground is always underneath.
	add_child(terrain)

	# Y-sort the entities among themselves (PLAN.md 3.1). The engine keys off each
	# child's position.y, which is why apply_snapshot() positions a view at its
	# FRONT tile and pushes the art back with draw_offset -- see
	# Iso.footprint_sort_offset for why a footprint cannot sort by its centre.
	pool.y_sort_enabled = true
	add_child(pool)


## Hand the view the map to draw. Terrain bytes, not a SimMap: the view layer
## never holds a reference into the simulation (PLAN.md 4), and this is also the
## shape a networked client gets its map in.
func build_terrain(size: Vector2i, terrain_bytes: PackedByteArray) -> void:
	terrain.build(size, terrain_bytes)


func apply_snapshot(snap: Dictionary) -> void:
	_last_tick = int(snap.get("tick", _last_tick))

	for entry in snap.get("updated", []):
		var id := int(entry.get("id", 0))
		var view := pool.get_view(id)
		var is_new := view == null
		if is_new:
			view = pool.acquire(id, _visual_id_of(entry))
		else:
			# A building changes visual when its phase does -- foundation to complete
			# to rubble are three separate atlases (ASSET_MISSING.md 1.2), not states
			# inside one, so the view has to be re-pointed rather than just redrawn.
			var wanted := _visual_id_of(entry)
			if view.visual_id != wanted:
				view.visual_id = wanted

		var p: Dictionary = entry.get("pos", {})
		var sub_pos := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))

		# The node goes where the entity SORTS, the art goes where the entity IS.
		# For everything 1x1 those are the same point and the offset is zero.
		var sort_offset := Iso.footprint_sort_offset(_footprint_of(entry))
		view.draw_offset = -sort_offset
		var target := Iso.sub_to_world(sub_pos) + sort_offset
		if is_new:
			view.snap_to(target)
		else:
			view.set_target_transform(target, _last_tick)

		var max_hp := float(entry.get("max_hp", 0))
		if max_hp > 0.0:
			view.set_health_dot(float(entry.get("hp", 0)) / max_hp)

		var alive := bool(entry.get("alive", true))
		view.set_dead(not alive)
		# Only a unit's snapshot carries corpse_ticks_left (SimUnit.to_snapshot);
		# rubble (5.5) has no fade timer and stays fully opaque forever.
		if entry.has("corpse_ticks_left") and int(entry["corpse_ticks_left"]) >= 0:
			view.set_corpse_fade(clampf(
					float(entry["corpse_ticks_left"]) / float(SimUnit.CORPSE_FADE_TICKS), 0.0, 1.0))
		else:
			view.set_corpse_fade(1.0)
		if entry.has("anim"):
			view.play_anim(StringName(entry["anim"]), int(entry.get("facing", 0)))

		var def_id := StringName(entry.get("def_id", ""))
		_facts[id] = {
			"id": id,
			"tile": Vector2i(sub_pos / SimWorld.SUBTILE),
			"owner_id": int(entry.get("owner_id", 0)),
			"def_id": def_id,
			"hp": int(entry.get("hp", 0)),
			"max_hp": int(max_hp),
			"alive": alive,
			"footprint": _footprint_of(entry),
			# Asked of the registry rather than guessed from the snapshot's shape.
			# Inferring "no phase field means a unit" would call a resource node a
			# unit, and 3.6 would then send move orders naming trees.
			"is_unit": GameDataRegistry.unit(def_id) != null,
			# Present only on units (SimUnit.to_snapshot); absent on a building or
			# resource node entry, where it defaults to IDLE and is never read since
			# villager_counts() already filters those out by is_unit.
			"task": int(entry.get("task", SimUnit.Task.IDLE)),
			# Present only on buildings (SimBuilding.to_snapshot); 0 elsewhere, which
			# reads correctly as "nothing queued" rather than needing its own guard.
			"queue_len": int(entry.get("queue_len", 0)),
			"queue_fraction": float(entry.get("queue_fraction", 0.0)),
		}
		# A corpse or rubble is unselectable (4.7, 5.5) even if it was selected
		# the tick it died -- `alive` wins over a selection built before this.
		view.set_selected(alive and selection.contains(id))

	for id in snap.get("removed", []):
		pool.release(int(id))
		_facts.erase(int(id))

	# A selection holding a unit that has just died -- or fully despawned --
	# would build an order naming an entity the sim rejects, and the player
	# would see nothing happen at all.
	var selectable: Array[int] = []
	for fid in _facts:
		if bool(_facts[fid].get("alive", true)):
			selectable.append(int(fid))
	selection.retain_only(selectable)


## Facts about one entity, or {} if it is not currently in view.
func facts_for(id: int) -> Dictionary:
	return _facts.get(id, {})


## Replace the selection and repaint the rings.
func select(ids: Array[int]) -> void:
	for id in selection.current():
		var previous := pool.get_view(id)
		if previous != null:
			previous.set_selected(false)
	for id in selection.set_selection(ids):
		var view := pool.get_view(id)
		if view != null:
			view.set_selected(true)


## The entity at a point in this node's LOCAL space, or 0 (PLAN.md 4.3).
##
## Local, not screen: the caller undoes the camera once, and picking does not have
## to know a camera exists.
##
## Picks by tile rather than by sprite bounds. A tap is a fingertip, not a
## pixel, and the tall art makes bounds misleading -- a 10 m tree's sprite covers
## the six tiles behind it, so bounds-picking would select the tree when the player
## clearly tapped the ground in front of it. The tile under the finger is what the
## player is pointing at, and it is also what an order is expressed in.
##
## `owner` restricts the pick to one player's things; pass 0 to pick anything.
## Units win ties, because a villager standing on a tree's tile is the thing worth
## tapping and the tree is not going anywhere.
func pick(local: Vector2, owner: int = 0) -> int:
	var tile := Iso.tile_at(local)
	var best := 0
	var best_is_unit := false
	for id in _facts:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue          # a corpse or rubble is unselectable (4.7, 5.5)
		if owner != 0 and int(f["owner_id"]) != owner:
			continue
		if not _covers(f, tile):
			continue
		var is_unit: bool = f["is_unit"]
		if best == 0 or (is_unit and not best_is_unit):
			best = int(id)
			best_is_unit = is_unit
	return best


## Every unit of `owner` standing inside a box, in LOCAL space (PLAN.md 8.3).
##
## **Units only, and only the owner's.** Dragging a box across your settlement and
## catching the town centre, four trees and a deer in it is not what anyone means
## by a box select; every RTS filters this way and the player expects it.
##
## Tested against each unit's ground point rather than its sprite, for the same
## reason picking goes by tile: a sprite is mostly air above the tile it stands on,
## so a box drawn over empty grass would catch whatever tall thing was leaning into
## it from behind.
func units_in_box(box: Rect2, owner: int) -> Array[int]:
	var found: Array[int] = []
	var ids := _facts.keys()
	# Sorted so a box that catches more than MAX_SELECTED takes the same units on
	# every machine, rather than whichever the Dictionary happened to yield first.
	ids.sort()
	for id in ids:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue          # a corpse is unselectable (4.7)
		if not bool(f["is_unit"]) or int(f["owner_id"]) != owner:
			continue
		if box.has_point(Iso.tile_centre_to_world(f["tile"])):
			found.append(int(id))
	return found


## The selected entities that can actually be given a move order (PLAN.md 3.6).
##
## Filtered rather than passed whole: `MoveCommand.validate()` rejects the ENTIRE
## command if any id is not a unit, so a selection containing the town centre would
## silently cancel the move for the villagers selected alongside it.
func movable_selection() -> Array[int]:
	var movable: Array[int] = []
	for id in selection.current():
		if bool(_facts.get(id, {}).get("is_unit", false)):
			movable.append(id)
	return movable


## Idle vs. total units belonging to `owner`, for the population counter
## (PLAN.md 7.1). By unit-ness rather than by `unit.villager` specifically --
## MVP has exactly one unit type, so today the two questions have the same
## answer, and this does not have to change the day a second one lands.
func villager_counts(owner: int) -> Vector2i:
	var idle := 0
	var total := 0
	for f in _facts.values():
		if not bool(f.get("alive", true)):
			continue          # a corpse (4.7) is not a villager to count any more
		if not bool(f.get("is_unit", false)) or int(f.get("owner_id", 0)) != owner:
			continue
		total += 1
		if int(f.get("task", -1)) == SimUnit.Task.IDLE:
			idle += 1
	return Vector2i(idle, total)


func _covers(f: Dictionary, tile: Vector2i) -> bool:
	var footprint: Vector2i = f["footprint"]
	var centre: Vector2i = f["tile"]
	# A footprint's `tile` is its centre; recover the rect it actually holds.
	var origin := centre - footprint / 2
	return Rect2i(origin, footprint).has_point(tile)


## Snapshots carry the entity's DEFINITION id (`unit.villager`); the asset seam is
## keyed by VISUAL id (`vis.villager`). Translating between them is exactly what
## GameDataRegistry is for -- passing def_id straight to the seam resolves to the
## magenta unknown and renders a whole match in placeholder colours without
## reporting anything (found at 2.6).
## `footprint` is present only for buildings (SimBuilding.to_snapshot); units and
## resource nodes stand on one tile, so the default is right for them rather than
## merely safe.
func _footprint_of(entry: Dictionary) -> Vector2i:
	var f: Dictionary = entry.get("footprint", {})
	return Vector2i(int(f.get("x", 1)), int(f.get("y", 1)))


func _visual_id_of(entry: Dictionary) -> StringName:
	var def_id := StringName(entry.get("def_id", ""))
	# `phase` is present only for buildings (SimBuilding.to_snapshot).
	return GameDataRegistry.visual_for(def_id, int(entry.get("phase", -1)))


func _process(delta: float) -> void:
	pool.advance_all(delta)
