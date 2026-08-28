## Turning a drag into a run of wall segments (PLAN.md 5.8).
##
## ONE FUNCTION, TWO CALLERS, AND THAT IS THE WHOLE POINT. The placement ghost draws
## what `plan()` returns and `PlaceWallCommand` places what `plan()` returns, so the
## wall a player sees under their finger is the wall they get. Two implementations of
## "which segments fill this line" is two implementations that drift, and the drift
## would present as a wall that comes out one segment shorter than the preview -- the
## same class of bug the placement ghost's own header warns about for adjacency.
##
## IN `src/sim/`, not in `src/view/`. It is integer arithmetic over tiles with no
## textures, no nodes and no input, so it satisfies the boundary rule (PLAN.md 4) --
## and it has to live on the sim side because the SERVER is what actually lays the
## segments down. The view reading a sim class is the allowed direction.
##
## AXIS-ALIGNED ONLY. A segment's footprint is a box -- [9, 2] east-west, [2, 9]
## north-south -- and a box rotated 45 degrees does not tile a square grid, so a
## drag snaps to whichever axis it mostly ran along. The wall art is baked at eight
## directions and only two of them are reachable today: four are the 180-degree twins
## of the two (a wall is symmetric, so they draw the same picture) and the last two are
## the true diagonals, which would need a footprint model this does not have.
class_name WallPlan
extends RefCounted

## Axis 0 runs along +x (east-west in tile space), axis 1 along +y.
const AXIS_X := 0
const AXIS_Y := 1

## The SIM facing (SimBuilding.facing's convention) for a wall lying along each axis.
##
## **A WALL FACES ACROSS ITS OWN LENGTH, NOT ALONG IT**, and getting that backwards is
## what the project owner reported on 2026-08-28: *"i am dragging NE to SW, the walls
## look like NW to SE."* These numbers were derived from `Iso.FACING_TILE_DIRS` by
## reading the tile direction as the direction the wall RUNS -- tile (1, 0) is sprite
## facing 7, so axis X was given sim facing 0 -- and the art means the opposite. A
## segment baked at sprite facing SE is a wall lying along tile axis Y; SW is the one
## lying along axis X. Ninety degrees out, which on a symmetric wall is exactly the
## error nothing else in the game can feel: same footprint, same origin, same hash.
##
## MEASURED OFF THE STAGED ATLASES, not guessed a second time. Regressing the mean
## opaque-pixel y against x over each direction's frame gives the slope the sprite
## leans at, and one screen tile is (32, 16) px, so a wall along tile axis X leans
## +0.5 and one along axis Y leans -0.5:
##
##                     S     SW      W     NW      N     NE      E     SE
##   wall_long       0.00  +0.45   0.00  -0.45   0.00  +0.45   0.00  -0.45
##   wall_gate       0.00  +0.43   0.00  -0.42   0.00  +0.42   0.00  -0.43
##   foundation_9x3 -0.02  +0.38   0.18  -0.42  -0.01  +0.39   0.20  -0.42
##
## All twelve wall and gate atlases agree, and so do the foundations and the rubble --
## so the foundations in that report were being laid across the run too, and the
## "unreadable construction site" they were blamed on was the same ninety degrees.
## S/N and W/E are the two DIAGONAL walls (412x166 and 64x336 for the long piece), and
## no axis-aligned footprint can ever ask for them. SW/NE and NW/SE are 180 apart and
## a wall is symmetric, so either of each pair would do; the low one is taken.
##
## Written out as a constant because the sim may not name an `Iso` -- that is a view
## class -- and this is the one place the two conventions have to agree about a
## building. `test_wall_facing` re-measures the atlases and fails if a rebake moves
## them, which is the check that was missing when this was first written: it said
## "verify these by looking", `preview_walls` photographed both axes, and looking is
## what did not happen for six days.
const FACING_FOR_AXIS := [6, 0]

## How short a run may be: one short segment. A drag of one tile still means "put a
## wall here", so it rounds UP to this rather than placing nothing.
const MIN_RUN := 3

## How thick a wall is. Two tiles, from the measured art -- every civ 0 A.D. bakes a
## wall from is between 1.25 and 2 tiles deep, and they all round to this.
const DEPTH := 2


## What a drag from `from` to `to` should lay down.
##
## Returns `{axis, segments}` where each segment is
## `{def_id, origin, footprint, facing, length}` -- everything `spawn_building` needs
## and nothing it does not. Empty `segments` only when `lengths` is unusable.
##
## `lengths` is `BuildingDef.wall_lengths` resolved to `{length: def_id}`, which the
## caller builds with `lengths_of()` -- passed in rather than looked up here so this
## function touches no registry and a test can plan against invented lengths.
static func plan(from: Vector2i, to: Vector2i, lengths: Dictionary) -> Dictionary:
	if lengths.is_empty():
		return {"axis": AXIS_X, "segments": []}

	# WHICHEVER AXIS THE DRAG MOSTLY RAN ALONG. A sloppy diagonal becomes a straight
	# wall rather than a refusal: the finger is on a phone, the grid is isometric, and
	# nobody drags a clean line across a rotated lattice.
	var delta := to - from
	var axis := AXIS_X if absi(delta.x) >= absi(delta.y) else AXIS_Y
	var span := absi(delta.x) if axis == AXIS_X else absi(delta.y)

	# INCLUSIVE of both ends, then rounded to a whole number of short segments. Every
	# length is a multiple of 3 (see buildings.json), so rounding to a multiple of the
	# shortest is what makes the greedy fill below exact rather than leaving a stub.
	var step := _shortest(lengths)
	var run := maxi(step, _round_to(span + 1, step))

	# ALWAYS LAID IN THE +AXIS DIRECTION, from whichever end is lower. A drag
	# right-to-left describes the same wall as left-to-right, and normalising here
	# means the segmentation cannot depend on which way the finger moved -- so the
	# ghost does not reshuffle itself when a drag crosses back over its own anchor.
	#
	# The PERPENDICULAR coordinate comes from `from`, the anchor: the wall stays on the
	# row the drag started on rather than sliding onto the row it ended on.
	var start := from
	if axis == AXIS_X:
		start.x = mini(from.x, to.x)
	else:
		start.y = mini(from.y, to.y)

	var segments: Array[Dictionary] = []
	var offset := 0
	while offset < run:
		var length := _largest_fitting(lengths, run - offset)
		if length <= 0:
			break                       # unreachable while `run` is a multiple of step
		var origin := start
		if axis == AXIS_X:
			origin.x += offset
		else:
			origin.y += offset
		segments.append({
			"def_id": lengths[length] as StringName,
			"origin": origin,
			"footprint": footprint_for(length, axis),
			"facing": FACING_FOR_AXIS[axis],
			"length": length,
		})
		offset += length

	return {"axis": axis, "segments": segments}


## A segment's footprint on the grid. Depth is `DEPTH` across the run and `length`
## along it, transposed for a north-south wall -- which is the whole of what
## "8 orientations" reduces to once the footprint has to stay a box.
static func footprint_for(length: int, axis: int) -> Vector2i:
	return Vector2i(length, DEPTH) if axis == AXIS_X else Vector2i(DEPTH, length)


## `{length_in_tiles: def_id}` for one tier, read off the defs' own footprints.
##
## LENGTH COMES FROM THE FOOTPRINT, never from a separate number in the data. A
## `length: 9` field beside a `footprint: [9, 2]` is two statements of one fact, and
## the day they disagreed the wall would claim different ground than it was planned
## on. `footprint.x` because every wall def is authored along the x axis; `plan()`
## transposes for the other one.
static func lengths_of(defs: Array[StringName], lookup: Callable) -> Dictionary:
	var out: Dictionary = {}
	for def_id in defs:
		var bd: BuildingDef = lookup.call(def_id)
		if bd == null or bd.footprint.x <= 0:
			continue
		out[bd.footprint.x] = def_id
	return out


## The shortest declared length, which is the granularity the whole run rounds to.
static func _shortest(lengths: Dictionary) -> int:
	var best := 0
	for length in lengths:
		if best == 0 or int(length) < best:
			best = int(length)
	return maxi(1, best)


## The longest length that fits in `remaining`, or 0 if none does. Greedy
## longest-first, which on a run that is a multiple of the shortest length always
## fills exactly: 12 becomes 9 + 3, 15 becomes 9 + 6, 18 becomes 9 + 9.
##
## Longest-first because a wall of fewer, bigger pieces is a wall with fewer seams to
## attack -- and because it is fewer entities, which matters when a player drags forty
## tiles and every segment is a vision circle and a snapshot entry.
static func _largest_fitting(lengths: Dictionary, remaining: int) -> int:
	var best := 0
	for length in lengths:
		var l := int(length)
		if l <= remaining and l > best:
			best = l
	return best


## `value` to the nearest multiple of `step`, halves rounding UP. Integer only: this
## runs inside `apply()`, where a float would be free to round differently on an ARM
## phone than on an x86 host.
static func _round_to(value: int, step: int) -> int:
	if step <= 0:
		return value
	return ((value + step / 2) / step) * step
