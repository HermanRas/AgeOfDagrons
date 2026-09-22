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
## FOUR AXES SINCE 2026-09-22, AND EVERY FOOTPRINT IS STILL A BOX. A drag snaps to one
## of the two tile axes or one of the two tile DIAGONALS. The diagonals are laid as a
## STAIRCASE -- a run of segments each stepping one piece across and one piece down, each
## claiming an axis-aligned square -- which is the owner's option B on board card
## `wall-facings-reachable` (#98). So the two frames that used to be unreachable are
## reachable now, and nothing in the occupancy model changed to do it: `SimMap.occupancy`,
## `can_place_building` and `MapEdit`'s collision test all still ask a `Rect2i`.
##
## ⛔ **A STAIRCASE BLOCKS, AND THAT IS NOT LUCK.** Consecutive squares touch only at a
## corner, so a unit could in principle slip between them -- except `PathService` builds its
## grids with `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` precisely so *"a villager must not slip
## diagonally between two buildings that touch"*. The diagonal move across the join has both
## of its orthogonal neighbours inside the two squares, so it is refused. **If that mode is
## ever changed, diagonal walls leak**, and the leak is invisible in a screenshot.
class_name WallPlan
extends RefCounted

## Axis 0 runs along +x (east-west in tile space), axis 1 along +y.
const AXIS_X := 0
const AXIS_Y := 1

## The two tile DIAGONALS (#98). `AXIS_D1` steps (+1, +1) and `AXIS_D2` steps (+1, -1).
##
## ⚠️ **APPENDED, AND THE NUMBERING IS LOAD-BEARING.** `MapData`'s per-entity `axis` field
## (16.4c/#89) is an int that saved maps already contain, and every one of them holds 0 or 1.
## Adding 2 and 3 on the end leaves every map ever written reading back as the wall it was.
## Inserting a value would silently rotate them, which is the same trap `SimMap.Terrain`'s
## own header records for the terrain array.
const AXIS_D1 := 2
const AXIS_D2 := 3

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
## a wall is symmetric, so either of each pair would do.
##
## ⚠️ **THESE ARE SIM FACINGS AND THE TABLE ABOVE IS IN SPRITE ORDER, WHICH IS EXACTLY
## HOW THIS READS AS A BUG WHEN IT IS NOT.** `[6, 0]` are not columns of that table:
## `Iso.sim_facing_to_sprite` is `posmod(7 - facing, 8)`, so **sim 6 -> sprite 1 = SW**
## (axis X, leans +0.45) and **sim 0 -> sprite 7 = SE** (axis Y, leans -0.45). Read as
## sprite indices instead, 6 and 0 are E and S -- two of the four FLAT diagonal frames --
## and the constant looks precisely backwards. The art side raised it as a question on
## board card `wall-diagonal-butt-test` (#122) on 2026-09-22 having measured the sheet
## independently; their measurement and this table agree in full, and the answer is the
## conversion sitting between them.
##
## ⛔ **AND IT IS `test_wall_facing` THAT SETTLES IT RATHER THAN THIS COMMENT**, which is
## the point of that file: `_lean()` resolves each axis through `sim_facing_to_sprite`
## and regresses the staged pixels of the frame that comes back, over at least 60
## directional pairs. A green suite IS the measurement, taken through the same call the
## renderer makes.
##
## 📝 This paragraph used to end *"the low one is taken"*, which is true of axis X (SW=1
## over NE=5) and false of axis Y (SE=7 is taken over NW=3). Harmless -- the pair is
## symmetric -- but it is the sentence that made a careful reader suspect the constant,
## so it says what is actually taken now.
##
## Written out as a constant because the sim may not name an `Iso` -- that is a view
## class -- and this is the one place the two conventions have to agree about a
## building. `test_wall_facing` re-measures the atlases and fails if a rebake moves
## them, which is the check that was missing when this was first written: it said
## "verify these by looking", `preview_walls` photographed both axes, and looking is
## what did not happen for six days.
##
## ## THE TWO DIAGONAL ENTRIES (#98), AND WHY THEY ARE 5 AND 7
##
## Converted the same way: sim 5 -> sprite **2 (W)** and sim 7 -> sprite **0 (S)**, which are
## two of the four FLAT frames the table above measures at 0.00. Those four are the diagonal
## bakes, and **the pair is told apart by ASPECT rather than by lean** -- this file's own
## measurement records S/N at **412x166** and W/E at **64x336** for the long piece. So the wide
## frame is the wall that runs across the screen and the tall one is the wall that runs down
## it, and a lean regression cannot separate them because both are flat.
##
## `AXIS_D1` steps (+1, +1), which in this projection is straight DOWN the screen, so it takes
## the TALL frame (sprite 2). `AXIS_D2` steps (+1, -1), straight ACROSS, so it takes the WIDE
## one (sprite 0). `test_wall_facing` measures the aspect and fails if a rebake swaps them.
const FACING_FOR_AXIS := [6, 0, 5, 7]


## Whether `axis` is one of the two tile diagonals.
static func is_diagonal(axis: int) -> bool:
	return axis == AXIS_D1 or axis == AXIS_D2


## One step along `axis`, in tiles.
static func step_dir(axis: int) -> Vector2i:
	match axis:
		AXIS_X: return Vector2i(1, 0)
		AXIS_Y: return Vector2i(0, 1)
		AXIS_D1: return Vector2i(1, 1)
		AXIS_D2: return Vector2i(1, -1)
	return Vector2i.ZERO


## How far a piece `length` axis-tiles long reaches along a DIAGONAL, in tiles.
##
## ## ⛔ `floor(length / sqrt(2))`, AND IT IS NOT THE AXIS STEP
##
## A diagonal tile step is 2.83 m where an axis step is 2.0 m, so a piece sized in axis tiles
## covers 41% fewer of them laid corner to corner. **Laid at the axis count a diagonal run
## leaves a 50 px hole between every segment** -- the row of disconnected stubs #98 named as
## the risk. Measured on the art side across all 20 eight-direction wall, gate and reinforced
## atlases, every civ and every age: 3 -> 2, 6 -> 4, 9 -> 6, art always slightly longer than
## the step so every join overlaps rather than gapping.
##
## ⚠️ **INTEGER, NOT `sqrt()`.** The sim is deterministic and stays on ints (PLAN.md 7.1), so
## this is the largest `k` with `2k² <= length²` rather than a float floor -- exact, and the
## same answer on every machine. It agrees with the measured table by construction: 9 gives 6
## because 72 <= 81 and 98 does not.
##
## ⛔ **THE FLOOR OF 1 IS A DELIBERATE BREAK IN THAT RULE AND IT IS LOAD-BEARING.** A 1-tile
## piece reaches `floor(1 / sqrt(2))` = **0** diagonal tiles, which is the honest answer and an
## unusable one: `_plan_diagonal` advances its cursor by this number, so a step of 0 is a loop
## that never terminates -- inside a tick, with no way out. Clamping costs nothing real, because
## the shipped lengths are 3/6/9 and a 1-tile wall does not exist; it is here so that a def
## someone adds later cannot hang the sim. **`test_the_diagonal_step_never_exceeds_the_true_length`
## asserts the exact rule from 2 upwards and this case separately**, which is how the clamp was
## found to be undocumented in the first place.
static func diagonal_step(length: int) -> int:
	var k := 0
	while 2 * (k + 1) * (k + 1) <= length * length:
		k += 1
	return maxi(1, k)

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

	var axis := axis_for(from, to)
	if is_diagonal(axis):
		return _plan_diagonal(from, to, axis, lengths)

	var delta := to - from
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


## A staircase run along one of the two tile diagonals (#98, the owner's option B).
##
## ## ⛔ THE SHORTEST PIECE ONLY, AND THE REASON IS THE FOOTPRINT RATHER THAN THE ART
##
## The medium and long pieces butt perfectly on a diagonal too -- the art side measured all
## three -- so this is not an art limit and reads like one. It is `Rect2i`. A diagonal segment
## has to claim a SQUARE of its own step, and the square is only a fair likeness of a
## two-tile-thick wall band while the step is small:
##
##   short, step 2 -> a 2x2 claim for a band that fills about 2x2. Honest.
##   long,  step 6 -> a **36-tile** claim for a band of roughly 17. The 19 spare tiles are
##                    the two triangular corners OUTSIDE the wall line, so a long diagonal
##                    piece would wall off the ground BEHIND your own wall and refuse
##                    buildings a comfortable distance from it.
##
## So a diagonal run is more entities than an axis run of the same length, and that is the
## price of the footprint staying a box. ⚠️ **If a non-rectangular footprint ever lands
## (#98's option C), this restriction is the first thing that should go** -- the greedy
## longest-first fill in `plan()` is what it would go back to.
static func _plan_diagonal(from: Vector2i, to: Vector2i, axis: int,
		lengths: Dictionary) -> Dictionary:
	var length := _shortest(lengths)
	var step := diagonal_step(length)
	var dir := step_dir(axis)

	# BOTH LEGS ARE WITHIN THE BAND `axis_for` ALLOWS, so the longer one is the honest
	# reading of how far the finger actually went. Inclusive of both ends, then rounded up to
	# a whole number of pieces, exactly as the axis case does.
	var d := to - from
	var span := maxi(absi(d.x), absi(d.y))
	var run := maxi(step, _round_to(span + 1, step))

	# LAID FROM WHICHEVER END IS FURTHER LEFT, for `plan()`'s reason: a drag right-to-left
	# describes the same wall, and normalising stops the ghost reshuffling when a drag crosses
	# back over its own anchor. x alone settles it for both diagonals, because `step_dir` is
	# +1 in x for each of them and only the y sign differs.
	var start := to if to.x < from.x else from

	var segments: Array[Dictionary] = []
	var offset := 0
	while offset < run:
		# The square is built from its two ENDS rather than from an assumed corner: `origin`
		# is the top-left that `MapData` and `spawn_building` both expect, and for `AXIS_D2`
		# the run travels UP the grid, so the lead tile is the box's bottom-left rather than
		# its top-left. Taking the min of each component is what makes one line serve both.
		var lead := start + Vector2i(offset * dir.x, offset * dir.y)
		var tail := lead + Vector2i((step - 1) * dir.x, (step - 1) * dir.y)
		segments.append({
			"def_id": lengths[length] as StringName,
			"origin": Vector2i(mini(lead.x, tail.x), mini(lead.y, tail.y)),
			"footprint": Vector2i(step, step),
			"facing": FACING_FOR_AXIS[axis],
			"length": length,
		})
		offset += step

	return {"axis": axis, "segments": segments}


## Which of the four axes a drag describes.
##
## ## WHICHEVER THE DRAG MOSTLY RAN ALONG, and a sloppy line still lays a wall
##
## A drag is never clean: the finger is on a phone and the grid is isometric, so nobody
## traces a lattice direction exactly. The question is only which of the four it is CLOSEST
## to, and that is a comparison of the shorter leg against the longer.
##
## `mini * 12 >= maxi * 5` is the diagonal band, i.e. the shorter leg is at least ~0.417 of
## the longer. The exact half-way line between an axis and a diagonal is `tan(22.5°)` =
## 0.4142; 5/12 is 0.4167, which is that number in integers and well inside the slop of a
## thumb. **Integer on purpose** -- `plan()` is sim code and PLAN.md 7.1 keeps it off floats.
static func axis_for(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	var ax := absi(d.x)
	var ay := absi(d.y)
	var small := mini(ax, ay)
	var big := maxi(ax, ay)
	if big > 0 and small * 12 >= big * 5:
		# The sign pair picks WHICH diagonal. A drag with dx and dy of the same sign runs
		# (+1, +1); opposite signs run (+1, -1). Zero cannot reach here -- `small * 12 >=
		# big * 5` with big > 0 forces small > 0.
		return AXIS_D1 if (d.x > 0) == (d.y > 0) else AXIS_D2
	return AXIS_X if ax >= ay else AXIS_Y


## A segment's footprint on the grid. Depth is `DEPTH` across the run and `length`
## along it, transposed for a north-south wall -- which is the whole of what
## "8 orientations" reduces to once the footprint has to stay a box.
##
## ⛔ **A DIAGONAL SEGMENT CLAIMS A SQUARE OF ITS STEP, AND `DEPTH` DOES NOT APPEAR.** At the
## step `_plan_diagonal` actually lays -- 2, the shortest piece -- a square laid corner to
## corner with its neighbours IS a band about two tiles thick across the diagonal, which is
## what `DEPTH` says a wall is. Adding `DEPTH` on top would claim the triangular corners
## OUTSIDE the wall line and block the ground behind your own wall. **The likeness gets worse
## as the step grows, which is exactly why `_plan_diagonal` refuses the longer pieces** --
## that function has the arithmetic.
static func footprint_for(length: int, axis: int) -> Vector2i:
	if is_diagonal(axis):
		var s := diagonal_step(length)
		return Vector2i(s, s)
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
