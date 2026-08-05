## The only place grid<->screen math lives (PLAN.md 6.3). Every other view
## script goes through this rather than doing its own projection.
##
## TILE_SIZE is a placeholder diamond, not the final art dimension -- that's
## chosen alongside the terrain tileset at phase 0.9/2.1 and only needs
## changing here.
class_name Iso
extends RefCounted

const TILE_SIZE := Vector2(64.0, 32.0)


static func tile_to_world(t: Vector2i) -> Vector2:
	return _project(Vector2(t))


## pos is sub-tile units (PLAN.md 1) -- fractional-tile precision, so a unit
## mid-step between tiles projects to a position between their diamonds.
static func sub_to_world(pos: Vector2i) -> Vector2:
	return _project(Vector2(pos) / float(SimWorld.SUBTILE))


static func world_to_tile(w: Vector2) -> Vector2i:
	var half := TILE_SIZE * 0.5
	var tx := (w.x / half.x + w.y / half.y) * 0.5
	var ty := (w.y / half.y - w.x / half.x) * 0.5
	return Vector2i(roundi(tx), roundi(ty))


## Draw order key for Y-sorting (PLAN.md 7.3). Naive tile-sum for now; revisit
## if profiling at 0.7 shows entity height needs to factor in too.
static func depth_sort_key(p: Vector2i) -> float:
	return float(p.x + p.y)


static func _project(tile_frac: Vector2) -> Vector2:
	var half := TILE_SIZE * 0.5
	return Vector2((tile_frac.x - tile_frac.y) * half.x, (tile_frac.x + tile_frac.y) * half.y)
