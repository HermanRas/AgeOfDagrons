## Where each unit of a group stands when it is ordered somewhere (PLAN.md 4.14).
##
## Pure static arithmetic over integers, like `SelectionActions` is over lists: it takes
## how many units there are, where they are now and where they are going, and returns one
## destination tile each. Nothing here touches `SimWorld`, so the whole formation model is
## assertable headlessly, and `MoveCommand` stays "ask for the tiles, request the paths".
##
## FOUR SHAPES, AND THEY WERE ALREADY CHOSEN. `SelectionActions.FORMATIONS` has listed
## line/grid/vee/box as disabled placeholders since 4.3, hanging off a military unit's
## Move action; this file is what makes those four live, so it does not get to invent a
## fifth or drop one.
##
## INTEGERS THROUGHOUT AND NOT MERELY BY HABIT. These tiles go into `PathService`, whose
## answers ride `state_hash()`, so a float here would be free to round differently on an
## ARM phone than on an x86 host and desync the match on the first group move. That is
## also why `_across` is an exact table rather than a rotation.
##
## AN UNREACHABLE SLOT NEEDS NO HANDLING HERE, and that is worth knowing before anyone
## adds any. A formation spread across a treeline will put slots inside the trees;
## `PathService` substitutes the nearest tile that can actually be stood on and
## `SimUnit.set_path` rewrites `task_target_tile` to wherever the route really ended
## (4.1). So the shape degrades into "as close to that as the ground allows", which is
## what a player expects and what every other order in the game already does.
class_name Formation
extends RefCounted

## No formation: every unit walks to the one tile it was given, which is what a move
## order has always done. `&""` rather than a fifth enum value so an old client, a test,
## and every AI order all mean it by simply not saying anything.
const NONE := &""

const LINE := &"line"
const GRID := &"grid"
const VEE := &"vee"
const BOX := &"box"

## Every shape this file answers for. `MoveCommand.validate` refuses anything else rather
## than falling back to NONE: a formation the server does not recognise is a client and a
## server that disagree about where an army is walking, and silently ignoring it would
## hide that.
const SHAPES: Array[StringName] = [LINE, GRID, VEE, BOX]

## Tiles between neighbouring slots. 1 is shoulder to shoulder on the grid, which is what
## `SeparationSystem` then holds them at anyway -- a wider spacing looks like a formation
## in a screenshot and walks like a crowd, because the separation pushes are what actually
## decide where units end up standing.
const SPACING := 1

## The eight compass directions in `SimUnit.facing` order (0 = +x, counter-clockwise in
## sim space), as exact integer deltas. A table rather than trigonometry: `cos(PI/4)` is
## not a rational number and the sim carries no floats, so a diagonal formation's slots
## have to be built from (1, 1) and not from 0.7071.
const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


## Whether `shape` names a real formation. `NONE` is not one -- it is the absence of one --
## so callers testing "did the player ask for a formation" and callers testing "is this a
## legal value" are asking different questions and get different answers.
static func is_shape(shape: StringName) -> bool:
	return SHAPES.has(shape)


## One destination tile per unit, in the same order as `unit_tiles`.
##
## `centre` is where the player tapped and stays the formation's anchor, so the shape
## forms up ON the order rather than short of it. `unit_tiles` is where each unit is
## standing now, and it is used for exactly one thing -- deciding which unit gets which
## slot -- never for the shape itself.
##
## WHICH UNIT GETS WHICH SLOT IS THE HALF THAT MAKES IT LOOK RIGHT. Handing out slots in
## id order marches the army through itself: the unit on the left walks to the right-hand
## slot and every path crosses. Instead both units and slots are ranked along the
## formation's own ACROSS axis, so whoever is furthest left goes to the leftmost slot and
## the group keeps its shape while it walks.
##
## Ties break by unit id, which is what makes the whole thing deterministic -- two units
## standing on the same rank must be ordered by something both hosts agree on, and
## position alone is not it.
static func destinations(shape: StringName, centre: Vector2i,
		unit_tiles: Array[Vector2i], unit_ids: Array[int]) -> Array[Vector2i]:
	var n := unit_tiles.size()
	var out: Array[Vector2i] = []
	if n == 0:
		return out
	if not is_shape(shape) or n == 1:
		# One unit has no formation to be in, whatever was asked for. Saying so here
		# rather than in the caller keeps "a lone soldier ignores the shape" true of
		# every caller there will ever be.
		for i in range(n):
			out.append(centre)
		return out

	var facing := _facing_of(_centroid(unit_tiles), centre)
	var forward := _DIRS[facing]
	var across := _DIRS[(facing + 2) % 8]

	var slots := _slots(shape, n)
	# Rank slots along the across axis. The slot list is already generated in a fixed
	# order, so this sort only has to be stable in the ties -- the index tie-break below
	# is what supplies that, since GDScript's sort is not documented as stable.
	var slot_order: Array[int] = []
	for i in range(slots.size()):
		slot_order.append(i)
	slot_order.sort_custom(func(a: int, b: int) -> bool:
		var ka := slots[a].x
		var kb := slots[b].x
		if ka != kb:
			return ka < kb
		return a < b)

	var unit_order: Array[int] = []
	for i in range(n):
		unit_order.append(i)
	unit_order.sort_custom(func(a: int, b: int) -> bool:
		var ka := _rank(unit_tiles[a] - centre, across)
		var kb := _rank(unit_tiles[b] - centre, across)
		if ka != kb:
			return ka < kb
		return unit_ids[a] < unit_ids[b])

	out.resize(n)
	for i in range(n):
		var slot: Vector2i = slots[slot_order[i]]
		# `slot.x` is across and `slot.y` is BACK from the anchor, in formation space.
		# Turned into map space by the two direction vectors, which is the only place the
		# facing enters -- the shapes below are all written facing "up the page".
		out[unit_order[i]] = centre + across * (slot.x * SPACING) \
				- forward * (slot.y * SPACING)
	return out


## Where each unit stands in FORMATION space: x along the across axis, y back from the
## anchor (0 is the front rank). Turned into map tiles by the caller.
##
## The across axis is 90 degrees counter-clockwise from the direction of travel, so a
## positive x is the group's LEFT -- but nothing here depends on which hand it is, only
## that the two ends stay apart and that units and slots are ranked by the same measure.
##
## Every shape produces exactly `n` DISTINCT slots, which matters more than symmetry and
## is why the centring below uses `n / 2` rather than `(n - 1) / 2`: integer halves of an
## even count collide, and two units sharing a destination tile is a pair that shoves each
## other for the rest of the match.
static func _slots(shape: StringName, n: int) -> Array[Vector2i]:
	match shape:
		LINE:
			return _line_slots(n)
		GRID:
			return _grid_slots(n)
		VEE:
			return _vee_slots(n)
		BOX:
			return _box_slots(n)
	return _line_slots(n)


## A single rank, shoulder to shoulder. The plainest shape and the one worth having: it
## is what you want when an army meets an army, because every unit reaches the enemy at
## the same moment instead of arriving in a column one at a time.
static func _line_slots(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(n):
		out.append(Vector2i(i - n / 2, 0))
	return out


## A block, as square as the count allows -- the marching shape, and the compact one.
## Columns are `ceil(sqrt(n))` so twelve units are 4x3 rather than 6x2; the last row is
## short and is left ragged rather than centred, because centring it would move a unit
## between two runs of the same order and read as the formation shuffling itself.
static func _grid_slots(n: int) -> Array[Vector2i]:
	var cols := 1
	while cols * cols < n:
		cols += 1
	var out: Array[Vector2i] = []
	for i in range(n):
		out.append(Vector2i(i % cols - cols / 2, i / cols))
	return out


## A wedge, apex forward. Unit 0 takes the point and the rest fall in behind it,
## alternating sides so the two arms grow evenly -- an odd count therefore leans one
## tile to the right rather than leaving a gap in the middle of a wing.
static func _vee_slots(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(0, 0)]
	for i in range(1, n):
		var rank := (i + 1) / 2
		var side := 1 if i % 2 == 1 else -1
		out.append(Vector2i(side * rank, rank))
	return out


## A hollow square, walked clockwise from its front-left corner. The shape for escorting
## something: the middle is deliberately empty, so a trade cart or a trebuchet ordered to
## the same tile ends up inside the ring rather than displacing a soldier out of it.
##
## The side is grown until the PERIMETER holds everybody, which is `4s - 4` for `s >= 2`;
## anything under four units cannot make a ring at all and gets a line, because three
## soldiers in a "box" is three soldiers standing in a corner.
static func _box_slots(n: int) -> Array[Vector2i]:
	if n < 4:
		return _line_slots(n)
	var side := 2
	while 4 * side - 4 < n:
		side += 1
	var half := side / 2

	var ring: Array[Vector2i] = []
	for x in range(side):
		ring.append(Vector2i(x - half, 0))                    # front, left to right
	for y in range(1, side - 1):
		ring.append(Vector2i(side - 1 - half, y))             # right side, going back
	for x in range(side - 1, -1, -1):
		ring.append(Vector2i(x - half, side - 1))             # back, right to left
	for y in range(side - 2, 0, -1):
		ring.append(Vector2i(-half, y))                       # left side, coming forward

	# The ring is usually longer than the count -- 9 units want side 4, whose perimeter
	# is 12 -- so the last three positions simply go unused. Taking a PREFIX rather than
	# spreading the gaps keeps the front rank full, which is the edge that meets whatever
	# the box is walking toward.
	return ring.slice(0, n)


## The integer average of a set of tiles. Truncating division, which is deterministic and
## is the only property that matters: this is a tie-break input, not a measurement, and
## being half a tile out cannot change which shape gets built.
static func _centroid(tiles: Array[Vector2i]) -> Vector2i:
	var sum := Vector2i.ZERO
	for t in tiles:
		sum += t
	return sum / tiles.size()


## Which of the eight compass directions `to` lies in from `from`, reusing
## `SimUnit.facing_toward` so a formation's forward axis is the same "east" a unit turns
## to face. Two definitions of the compass in one codebase is the duplication the
## `Diplomacy` header warns about, and it would show up as a line that forms across the
## direction of travel.
##
## A group already standing on its destination has no direction to take; 0 is as good as
## any, and the alternative -- refusing to form up -- would make the shape depend on how
## far away the order was given.
static func _facing_of(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	return SimUnit.facing_toward(to - from)


## How far along the across axis a unit sits, as a plain dot product in tiles. Used only
## for ordering, so its scale is irrelevant and its sign is everything.
static func _rank(offset: Vector2i, across: Vector2i) -> int:
	return offset.x * across.x + offset.y * across.y
