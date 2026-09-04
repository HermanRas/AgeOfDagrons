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


## The tile's own coordinate projected -- which is its top CORNER, not its middle.
## Equals sub_to_world() at exact tile multiples, and that is what makes it a
## corner: the sim puts an entity standing on tile t at `t * SUBTILE + SUBTILE/2`,
## so t itself is the boundary between t and its neighbours.
##
## For placing anything that sits ON a tile -- terrain art especially -- use
## tile_centre_to_world(). Confusing the two costs half a tile, which is invisible
## on uniform grass and obvious the moment two terrains meet.
static func tile_to_world(t: Vector2i) -> Vector2:
	return _project(Vector2(t))


## Screen-space box the whole map projects into, for clamping the camera (3.3).
##
## Measured from tile CORNERS, not centres: the map covers fractional tile
## coordinates [0, w] x [0, h], so its extreme points are the four corners of that
## square projected -- top (0,0), right (w,0), bottom (w,h), left (0,h). Using tile
## centres would shrink the box by half a tile on every side and let the camera
## stop with a sliver of ground still off-screen.
##
## The map is a DIAMOND inside this box. Clamping a rectangular viewport to a
## rectangular bound therefore still allows off-map void at the four corners --
## unavoidable without letterboxing the diamond, and the reason the background
## colour behind the world is a visible decision rather than an afterthought.
static func map_bounds(size: Vector2i) -> Rect2:
	var w := maxi(0, size.x)
	var h := maxi(0, size.y)
	var half := TILE_SIZE * 0.5
	return Rect2(
		Vector2(-float(h) * half.x, 0.0),
		Vector2(float(w + h) * half.x, float(w + h) * half.y))


## Middle of tile `t`, matching where the sim stands an entity on it (2.3:
## `spawn_unit` and `spawn_resource_node` both offset by half a tile, and
## SimBuilding.centre_of does the same for a footprint).
static func tile_centre_to_world(t: Vector2i) -> Vector2:
	return _project(Vector2(t) + Vector2(0.5, 0.5))


## Projection of a point given in fractional tiles, the exact inverse of
## world_to_tile_f(). The camera clamp works in tile space and has to come back.
static func tile_to_world_f(t: Vector2) -> Vector2:
	return _project(t)


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


## The sprite facing (an `AtlasEntry.FACINGS` index) for a sim facing.
##
## **THE TWO CONVENTIONS RUN OPPOSITE WAYS AND NEITHER IS WRONG.**
## `SimUnit.facing_toward` returns a maths octant in tile space -- 0 along +x,
## counting anticlockwise with the y axis flipped -- because the sim has no camera
## and no opinion about which way "south" is. `AtlasEntry.FACINGS` is a sprite
## table that starts at S (toward the camera) and runs the other way round,
## because that is the order isobake writes its directions in.
##
## Lined up tile-direction by tile-direction against `FACING_TILE_DIRS`, the two
## differ by exactly `7 - facing` for all eight, and this is the one place that
## knows it. Until 2026-08-20 the view passed the sim's number straight through,
## which draws the MIRROR of the right sprite: only 45 degrees out walking south,
## where it is easy to miss, but 135 degrees out walking north-east, which is what
## the project owner reported.
##
## Converted here rather than in the sim because `facing` is part of
## `state_hash()` -- changing its meaning would rewrite every recorded replay.
static func sim_facing_to_sprite(facing: int) -> int:
	return posmod(7 - facing, FACING_TILE_DIRS.size())


## Nearest tile COORDINATE to a point -- the inverse of tile_to_world(), which
## projects the tile's corner. Rounds, so it round-trips a corner back to its own
## index.
##
## This is not the same question as "which tile is this point inside", and using it
## for that is off by one half the time. Use tile_at() to hit-test.
static func world_to_tile(w: Vector2) -> Vector2i:
	var t := world_to_tile_f(w)
	return Vector2i(roundi(t.x), roundi(t.y))


## Which tile CONTAINS a point (PLAN.md 4.3, picking).
##
## Floors rather than rounds: tile t covers fractional coordinates [t, t+1), so a
## point anywhere inside it -- including its centre at t+0.5, where the sim stands
## entities -- belongs to t. Rounding would send the near half of every tile to its
## neighbour, which is a tap that selects the wrong thing half the time.
static func tile_at(w: Vector2) -> Vector2i:
	var t := world_to_tile_f(w)
	return Vector2i(floori(t.x), floori(t.y))


## Un-projected to FRACTIONAL tile coordinates -- the exact inverse of _project.
##
## Separate from world_to_tile() because rounding to a tile throws away what the
## camera clamp needs: clamping fractional tile coordinates to the [0, w] x [0, h]
## box is what confines a point to the map's DIAMOND in screen space, and it has
## to be done before any rounding.
static func world_to_tile_f(w: Vector2) -> Vector2:
	var half := TILE_SIZE * 0.5
	return Vector2(
		(w.x / half.x + w.y / half.y) * 0.5,
		(w.y / half.y - w.x / half.x) * 0.5)


## Screen offset from a footprint's CENTRE -- where its sprite is anchored, and
## where the sim keeps its `pos` -- to the middle of its FRONT tile, the one
## nearest the camera.
##
## This is the 3.1 depth fix (PLAN.md 13.1). Sorting a footprint by its centre is
## wrong and was visibly so: an 8x8 town centre sorted as though it stood on its
## middle tile, so units on the four tiles nearest the camera drew *behind* its
## roof -- the starting villagers appeared to stand on top of the town centre in
## dev_preview/preview_world.tscn at 2.6. Sorting by the front tile instead means
## a building sorts by the nearest ground it actually covers, which is the ground
## a unit has to be in front of to occlude it.
##
## Adding this to a view's position moves its SORT point without moving its art;
## EntityView.draw_offset carries the equal and opposite shift so the sprite stays
## put. A 1x1 footprint gets (0, 0) -- its front tile is itself -- so units and
## resource nodes are unaffected.
static func footprint_sort_offset(footprint: Vector2i) -> Vector2:
	var f := Vector2(maxi(1, footprint.x), maxi(1, footprint.y))
	return _project(f * 0.5 - Vector2(0.5, 0.5))


## Draw order key for painter's-order callers (PLAN.md 7.3). Larger is nearer the
## camera and therefore drawn later.
##
## Takes the screen point a view SORTS at, not a tile -- which is the whole fix.
## A tile-sum key cannot express "this building covers eight tiles"; a sort point
## can, because footprint_sort_offset() has already moved it to the front tile.
## Godot's own Y-sort keys off exactly this quantity, so a container with
## `y_sort_enabled` and a caller using this function agree by construction.
static func depth_sort_key(sort_point: Vector2) -> float:
	return sort_point.y


static func _project(tile_frac: Vector2) -> Vector2:
	var half := TILE_SIZE * 0.5
	return Vector2((tile_frac.x - tile_frac.y) * half.x, (tile_frac.x + tile_frac.y) * half.y)
