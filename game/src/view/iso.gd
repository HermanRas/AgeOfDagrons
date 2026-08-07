## The only place grid<->screen math lives (PLAN.md 6.3). Every other view
## script goes through this rather than doing its own projection.
##
## TILE_SIZE is a placeholder diamond, not the final art dimension -- that's
## chosen alongside the terrain tileset at phase 0.9/2.1 and only needs
## changing here.
class_name Iso
extends RefCounted

const TILE_SIZE := Vector2(64.0, 32.0)

## How much world one tile covers. Must match `metres_per_tile` in
## tools/isobake.toml -- it sets the scale of every baked atlas, so the two
## disagreeing means sprites render at the wrong size with nothing to warn you.
## test_visual_seam.gd asserts the atlases agree with PIXELS_PER_METRE below.
const METRES_PER_TILE := 2.0

## Camera elevation, derived rather than configured: a tile TILE_SIZE.y tall and
## TILE_SIZE.x wide is exactly asin(32/64) = 30 degrees. Not 35.264 -- that is
## the cube body-diagonal angle and would make a 64px tile 37px tall (PLAN.md 2.2).
const ELEVATION_RAD := 0.5235987755982989          # asin(0.5)

## Screen pixels per metre measured along a world axis, i.e. the scale isobake
## bakes at. Derived: one metre along world x moves TILE_SIZE.x / (2 * metres per
## tile) = 16 px in screen x, and that is the world axis foreshortened by the 45
## degree azimuth, so the unforeshortened figure is 16 / cos(45) = 22.627.
const PIXELS_PER_METRE := 22.62741699796952

## Screen pixels a metre of *height* (world z) moves up the screen. World z has no
## azimuth foreshortening, only the elevation cosine.
const VERTICAL_PX_PER_METRE := 19.595917942265423  # PIXELS_PER_METRE * cos(30)


static func tile_to_world(t: Vector2i) -> Vector2:
	return _project(Vector2(t))


## A ground-plane offset given in metres rather than tiles. Placeholder specs are
## authored in metres (PLAN.md 2.4) so they stay meaningful independently of
## TILE_SIZE, and so a placeholder occupies the space the real art will.
static func metres_to_world(m: Vector2) -> Vector2:
	return _project(m / METRES_PER_TILE)


## Screen offset of a point `h` metres above the ground at the same tile. Negative
## y because screen y grows downward.
static func height_to_world(h: float) -> Vector2:
	return Vector2(0.0, -h * VERTICAL_PX_PER_METRE)


## pos is sub-tile units (PLAN.md 1) -- fractional-tile precision, so a unit
## mid-step between tiles projects to a position between their diamonds.
static func sub_to_world(pos: Vector2i) -> Vector2:
	return _project(Vector2(pos) / float(SimWorld.SUBTILE))


## Ground directions for the 8 facings, in tile space, indexed to match
## AtlasEntry.FACINGS (S, SW, W, NW, N, NE, E, SE). S is toward the camera, which
## is +x+y in tile space because _project sends both to increasing screen y.
const FACING_TILE_DIRS: Array[Vector2] = [
	Vector2(1, 1),    # S  -- screen down
	Vector2(0, 1),    # SW
	Vector2(-1, 1),   # W  -- screen left
	Vector2(-1, 0),   # NW
	Vector2(-1, -1),  # N  -- screen up
	Vector2(0, -1),   # NE
	Vector2(1, -1),   # E  -- screen right
	Vector2(1, 0),    # SE
]


## Unit screen vector a facing points along. Used to draw a facing marker and to
## pick a stored sprite direction; the two must agree, hence one table.
static func facing_to_screen_dir(facing: int) -> Vector2:
	var dir := FACING_TILE_DIRS[posmod(facing, FACING_TILE_DIRS.size())]
	return _project(dir).normalized()


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
