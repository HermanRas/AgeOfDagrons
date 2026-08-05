## Tile-bucketed index of entity positions, for radius/rect queries that
## would otherwise scan every entity every tick. Keyed in tile units, not
## sub-tile -- callers pass SimEntity.tile(), not .pos.
class_name SpatialHash
extends RefCounted

var _cells: Dictionary = {}          # Vector2i tile -> Dictionary[int, bool]
var _positions: Dictionary = {}      # int id -> Vector2i tile


func insert(id: int, tile: Vector2i) -> void:
	_positions[id] = tile
	if not _cells.has(tile):
		_cells[tile] = {}
	_cells[tile][id] = true


func remove(id: int) -> void:
	if not _positions.has(id):
		return
	var tile: Vector2i = _positions[id]
	if _cells.has(tile):
		_cells[tile].erase(id)
		if _cells[tile].is_empty():
			_cells.erase(tile)
	_positions.erase(id)


func move(id: int, new_tile: Vector2i) -> void:
	if _positions.get(id, new_tile) == new_tile:
		return
	remove(id)
	insert(id, new_tile)


func query_radius(center: Vector2i, r: int) -> Array[int]:
	var found: Array[int] = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var t := center + Vector2i(dx, dy)
			if _cells.has(t) and Vector2(t - center).length() <= float(r):
				for id in _cells[t]:
					found.append(id)
	return found


func query_rect(rect: Rect2i) -> Array[int]:
	var found: Array[int] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var t := Vector2i(x, y)
			if _cells.has(t):
				for id in _cells[t]:
					found.append(id)
	return found
