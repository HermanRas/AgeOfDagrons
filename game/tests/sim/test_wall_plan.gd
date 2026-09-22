## Turning a drag into segments (PLAN.md 5.8).
##
## `WallPlan` is the one function the ghost and the server both call, so it is the
## one place a wall can come out different from the wall a player saw. Everything
## here is pure arithmetic over tiles -- no world, no registry -- which is exactly
## why the segmentation was put in `src/sim/` rather than in the placement handler.
extends TestCase

## The shipped wall lengths, expressed as `plan()` wants them, without going near
## `GameDataRegistry` -- so a test that fails here has failed at the maths and not
## at the data.
const LENGTHS := {3: &"short", 6: &"medium", 9: &"long"}


func _lengths_of(plan: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for seg in plan["segments"]:
		out.append(int(seg["length"]))
	return out


func _total(plan: Dictionary) -> int:
	var n := 0
	for seg in plan["segments"]:
		n += int(seg["length"])
	return n


# ── which axis ──────────────────────────────────────────────────────────────

func test_a_mostly_horizontal_drag_makes_a_horizontal_wall() -> void:
	# A SLOPPY DIAGONAL IS STILL A WALL. The finger is on a phone and the grid is
	# isometric, so nobody drags a clean line -- refusing an imperfect one would make
	# the feature unusable on the device it is for.
	var plan := WallPlan.plan(Vector2i(10, 10), Vector2i(22, 12), LENGTHS)
	assert_eq(int(plan["axis"]), WallPlan.AXIS_X)


func test_a_mostly_vertical_drag_makes_a_vertical_wall() -> void:
	var plan := WallPlan.plan(Vector2i(10, 10), Vector2i(12, 22), LENGTHS)
	assert_eq(int(plan["axis"]), WallPlan.AXIS_Y)


## ⛔ THIS ASSERTED `AXIS_X` UNTIL 2026-09-22, AND THE FLIP IS THE WHOLE OF #98.
##
## A 45-degree drag used to fall to the x axis because a diagonal wall could not be built:
## the old comment said *"which axis it picks matters less than that both hosts pick the
## same one"*, which was the honest answer while both choices were wrong. The owner's option
## B made the diagonal a real wall, so the drag a player plainly meant as diagonal now lays
## one. Kept as an edit rather than a new test so the reversal is visible in the diff.
func test_a_square_drag_is_a_diagonal_wall() -> void:
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(9, 9), LENGTHS)
	assert_eq(int(plan["axis"]), WallPlan.AXIS_D1)


# ── the diagonals (#98) ─────────────────────────────────────────────────────

## The sign pair is the only thing separating the two diagonals, and getting it backwards
## draws a wall the mirror of the drag -- the same class of fault as the 2026-08-28 ninety
## degrees, and just as invisible in a footprint.
func test_the_sign_pair_picks_which_diagonal() -> void:
	assert_eq(int(WallPlan.plan(Vector2i(0, 0), Vector2i(9, 9), LENGTHS)["axis"]),
			WallPlan.AXIS_D1, "down-right is D1")
	assert_eq(int(WallPlan.plan(Vector2i(0, 9), Vector2i(9, 0), LENGTHS)["axis"]),
			WallPlan.AXIS_D2, "up-right is D2")
	# And backwards along each, which must name the SAME axis -- the wall does not care
	# which end the finger started at.
	assert_eq(int(WallPlan.plan(Vector2i(9, 9), Vector2i(0, 0), LENGTHS)["axis"]),
			WallPlan.AXIS_D1)
	assert_eq(int(WallPlan.plan(Vector2i(9, 0), Vector2i(0, 9), LENGTHS)["axis"]),
			WallPlan.AXIS_D2)


## ⛔ THE BAND HAS TO HAVE EDGES, OR EVERY SLOPPY DRAG BECOMES A STAIRCASE.
##
## `test_a_mostly_horizontal_drag` above is the feature this could break: a wall dragged
## roughly along an axis must stay an axis wall, because that is what almost every drag is.
## The boundary is `tan(22.5°)`, the half-way line between an axis and a diagonal.
func test_a_gentle_slope_is_still_an_axis_wall() -> void:
	# 16 across and 4 down is well inside the axis half.
	assert_eq(int(WallPlan.plan(Vector2i(0, 0), Vector2i(16, 4), LENGTHS)["axis"]),
			WallPlan.AXIS_X)
	# 12 across and 5 down is just past the line and is a diagonal.
	assert_eq(int(WallPlan.plan(Vector2i(0, 0), Vector2i(12, 5), LENGTHS)["axis"]),
			WallPlan.AXIS_D1)


## ⛔ THE MEASURED TABLE, PINNED. These three numbers are the art side's, taken across all 20
## eight-direction wall, gate and reinforced atlases on #122 -- `floor(length / sqrt(2))`.
##
## **Laid at the AXIS count instead, a diagonal run leaves a 50 px hole between every
## segment.** That is the failure #98 named as the risk and the reason the card existed, so
## it is pinned here rather than left to the drawing.
func test_the_diagonal_step_is_the_measured_two_thirds() -> void:
	assert_eq(WallPlan.diagonal_step(3), 2)
	assert_eq(WallPlan.diagonal_step(6), 4)
	assert_eq(WallPlan.diagonal_step(9), 6)


## Integer, not `sqrt()`: the sim stays off floats (PLAN.md 7.1) and two hosts must agree
## exactly. This holds the property the integer form is standing in for.
##
## ⚠️ **FROM 2 UPWARDS, BECAUSE LENGTH 1 IS CLAMPED AND THE CLAMP IS THE POINT.** This test
## originally ran from 1 and failed, which is how the clamp came to be written down: a 1-tile
## piece truly reaches `floor(1 / sqrt(2))` = 0, and `_plan_diagonal` advances its cursor by
## this number, so the honest answer is a loop that never ends. The next test holds the clamp.
func test_the_diagonal_step_never_exceeds_the_true_length() -> void:
	for length in range(2, 40):
		var s := WallPlan.diagonal_step(length)
		assert_true(2 * s * s <= length * length,
				"a %d-tile piece cannot reach %d diagonal tiles" % [length, s])
		assert_true(2 * (s + 1) * (s + 1) > length * length,
				"a %d-tile piece reaches further than %d" % [length, s])


## ⛔ THE STEP IS NEVER ZERO, WHICH IS A LIVENESS PROPERTY AND NOT AN ARITHMETIC ONE.
##
## `_plan_diagonal` advances `offset` by the step until it reaches the run, so a step of 0
## hangs the sim inside a tick. The shipped lengths are 3/6/9 and never reach this, so the
## guard exists purely against a `wall_lengths` somebody adds later -- exactly the sort of
## thing that is never exercised until it is, and by then it is a freeze rather than a bug.
func test_the_step_is_never_zero_however_short_the_piece() -> void:
	for length in range(0, 4):
		assert_true(WallPlan.diagonal_step(length) >= 1,
				"a %d-tile piece still advances the run" % length)


## A diagonal segment claims a SQUARE, not a transposed box. `DEPTH` does not appear: at the
## step actually laid, the square IS the two-tile band.
func test_a_diagonal_segment_claims_a_square_of_its_step() -> void:
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(12, 12), LENGTHS)
	for seg in plan["segments"]:
		var f: Vector2i = seg["footprint"]
		assert_eq(f.x, f.y, "a diagonal claim is square")
		assert_eq(f.x, WallPlan.diagonal_step(int(seg["length"])))


## ⛔ SHORTEST PIECE ONLY, AND IT IS A FOOTPRINT RULE RATHER THAN AN ART ONE.
##
## The medium and long pieces butt on a diagonal too -- the art measured all three -- so this
## looks like an art limit and is not. A long piece steps 6, so it would claim a **36-tile**
## square for a band of roughly 17, and the 19 spare tiles are the triangular corners OUTSIDE
## the wall line: it would wall off the ground behind your own wall.
func test_a_diagonal_run_uses_only_the_shortest_piece() -> void:
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(30, 30), LENGTHS)
	assert_true(plan["segments"].size() > 1, "a long drag is several pieces")
	for seg in plan["segments"]:
		assert_eq(int(seg["length"]), 3, "every diagonal piece is the short one")


## ⛔ THE PROPERTY THE WHOLE STAIRCASE RESTS ON: consecutive squares touch at a CORNER, with
## no gap and no overlap.
##
## A gap is a wall a unit walks through. An overlap is a segment `can_place_building` refuses,
## so the second half of the wall silently does not get built. Neither is visible in a
## screenshot of one segment, which is why this is measured rather than looked at.
##
## ⚠️ **AND THE CORNER IS ONLY SEALED BECAUSE `PathService` USES
## `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`** -- the diagonal move across the join has both of its
## orthogonal neighbours inside these two squares. If that mode ever changes, this geometry
## stops being a wall and nothing here will say so.
func test_consecutive_diagonal_segments_touch_at_exactly_one_corner() -> void:
	for target in [Vector2i(24, 24), Vector2i(24, -24)]:
		var plan := WallPlan.plan(Vector2i(0, 0), target, LENGTHS)
		var segs: Array = plan["segments"]
		assert_true(segs.size() > 1)
		for i in range(1, segs.size()):
			var a := Rect2i(segs[i - 1]["origin"], segs[i - 1]["footprint"])
			var b := Rect2i(segs[i]["origin"], segs[i]["footprint"])
			assert_false(a.intersects(b),
					"%s overlaps %s -- the second would be refused placement" % [a, b])
			# Grown by one, they DO meet: that is corner contact rather than a gap.
			assert_true(a.grow(1).intersects(b),
					"%s and %s leave a hole a unit walks through" % [a, b])


## All four axes draw a different one of the eight bakes. Two sharing a facing is a wall lying
## across its own footprint -- and the diagonals are the pair most likely to be given the axis
## table's entries by a later edit, because the constant is indexed by axis.
func test_every_axis_gets_its_own_facing() -> void:
	var seen: Dictionary = {}
	for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y, WallPlan.AXIS_D1, WallPlan.AXIS_D2]:
		var facing: int = WallPlan.FACING_FOR_AXIS[axis]
		assert_false(seen.has(facing), "axis %d reuses facing %d" % [axis, facing])
		seen[facing] = true


## ⛔ THESE ARE NUMBERS IN A FILE FORMAT, NOT NAMES IN CODE. `axis` is written into
## `map.json` (16.4c) and indexes `FACING_FOR_AXIS`, so renumbering would silently rotate
## every wall on every saved map. APPENDED for that reason, and `FormatGuard` checks all four
## against the MapMaker's stand-in.
func test_the_axis_values_are_the_ones_saved_maps_carry() -> void:
	assert_eq(WallPlan.AXIS_X, 0)
	assert_eq(WallPlan.AXIS_Y, 1)
	assert_eq(WallPlan.AXIS_D1, 2)
	assert_eq(WallPlan.AXIS_D2, 3)


func test_the_footprint_is_transposed_for_a_vertical_wall() -> void:
	# The whole of what "8 orientations" reduces to once a footprint has to stay a
	# box on a square grid.
	var across := WallPlan.plan(Vector2i(0, 0), Vector2i(8, 0), LENGTHS)
	var down := WallPlan.plan(Vector2i(0, 0), Vector2i(0, 8), LENGTHS)
	assert_eq(across["segments"][0]["footprint"], Vector2i(9, WallPlan.DEPTH))
	assert_eq(down["segments"][0]["footprint"], Vector2i(WallPlan.DEPTH, 9))


func test_the_two_axes_get_different_facings() -> void:
	# A wall drawn at the same facing whichever way it was dragged is a wall lying
	# across half its own footprint. This holds only that the two DIFFER, which is as
	# much as a sim test can see; that each is the right one of the eight is measured
	# off the staged pixels by `test_wall_facing`, and it had to be, because both were
	# wrong for six days while this passed.
	var across := WallPlan.plan(Vector2i(0, 0), Vector2i(8, 0), LENGTHS)
	var down := WallPlan.plan(Vector2i(0, 0), Vector2i(0, 8), LENGTHS)
	assert_ne(int(across["segments"][0]["facing"]), int(down["segments"][0]["facing"]))


# ── how it fills ────────────────────────────────────────────────────────────

func test_a_nine_tile_run_is_one_long_segment() -> void:
	# Longest-first: fewer seams to attack, and fewer entities on the wire.
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(8, 0), LENGTHS)
	assert_eq(_lengths_of(plan), [9] as Array[int])


func test_a_twelve_tile_run_is_a_long_and_a_short() -> void:
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(11, 0), LENGTHS)
	assert_eq(_lengths_of(plan), [9, 3] as Array[int])


func test_a_fifteen_tile_run_is_a_long_and_a_medium() -> void:
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(14, 0), LENGTHS)
	assert_eq(_lengths_of(plan), [9, 6] as Array[int])


func test_a_run_always_fills_exactly() -> void:
	# The property that makes greedy longest-first safe: every declared length is a
	# multiple of the shortest, and the run is rounded to that multiple, so there is
	# never a stub left over. Checked across every span a drag could produce rather
	# than at three hand-picked ones.
	for span in range(0, 60):
		var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(span, 0), LENGTHS)
		var total := _total(plan)
		assert_eq(total % 3, 0, "span %d fills a whole number of shorts" % span)
		# And the segments are laid end to end with no gap and no overlap.
		var expected := 0
		for seg in plan["segments"]:
			assert_eq((seg["origin"] as Vector2i).x, expected,
					"span %d: segment starts where the last one ended" % span)
			expected += int(seg["length"])
		assert_eq(expected, total)


func test_a_single_tap_still_places_one_segment() -> void:
	# A tap-and-release is a drag of zero length, and it means "put a wall here"
	# rather than "put nothing here".
	var plan := WallPlan.plan(Vector2i(5, 5), Vector2i(5, 5), LENGTHS)
	assert_eq(_lengths_of(plan), [3] as Array[int])


func test_a_run_rounds_to_the_nearest_whole_segment() -> void:
	# Two tiles rounds DOWN to one short, four rounds down, five rounds up to two.
	# Halves up, so the wall is never shorter than half a segment's worth of intent.
	assert_eq(_total(WallPlan.plan(Vector2i(0, 0), Vector2i(1, 0), LENGTHS)), 3)
	assert_eq(_total(WallPlan.plan(Vector2i(0, 0), Vector2i(3, 0), LENGTHS)), 3)
	assert_eq(_total(WallPlan.plan(Vector2i(0, 0), Vector2i(4, 0), LENGTHS)), 6)


# ── which way round ─────────────────────────────────────────────────────────

func test_dragging_backwards_describes_the_same_wall() -> void:
	# Normalised to the +axis direction, so the ghost does not reshuffle itself when
	# a drag crosses back over its own anchor -- and so the segmentation cannot
	# depend on which way the finger moved.
	var forward := WallPlan.plan(Vector2i(10, 7), Vector2i(21, 7), LENGTHS)
	var backward := WallPlan.plan(Vector2i(21, 7), Vector2i(10, 7), LENGTHS)
	assert_eq(_lengths_of(forward), _lengths_of(backward))
	assert_eq(forward["segments"][0]["origin"], backward["segments"][0]["origin"])


func test_the_run_stays_on_the_row_the_drag_started_on() -> void:
	# The PERPENDICULAR coordinate comes from the anchor, not from where the finger
	# ended up -- otherwise a wall would slide sideways off the line the player
	# aimed at as the drag wobbled.
	var plan := WallPlan.plan(Vector2i(4, 9), Vector2i(20, 13), LENGTHS)
	for seg in plan["segments"]:
		assert_eq((seg["origin"] as Vector2i).y, 9)


func test_a_backwards_drag_extends_from_the_anchor_not_past_it() -> void:
	# Laid from the lower end, so a leftward drag covers the tiles between the two
	# fingers-worth of intent and does not spill out the far side of the anchor.
	var plan := WallPlan.plan(Vector2i(20, 5), Vector2i(12, 5), LENGTHS)
	var first: Vector2i = plan["segments"][0]["origin"]
	assert_eq(first.x, 12)
	assert_eq(_total(plan), 9, "12..20 inclusive is 9 tiles")


# ── degenerate data ─────────────────────────────────────────────────────────

func test_no_lengths_means_no_segments() -> void:
	# Reachable from a `wall_lengths` naming only defs that do not exist.
	# `PlaceWallCommand.validate` refuses on this rather than applying a no-op.
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(9, 0), {})
	assert_true((plan["segments"] as Array).is_empty())


func test_one_declared_length_still_works() -> void:
	# A tier with only a short piece is not something the data ships, and it must not
	# be an infinite loop either.
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(8, 0), {3: &"short"})
	assert_eq(_lengths_of(plan), [3, 3, 3] as Array[int])


# ── against the shipped data ────────────────────────────────────────────────

func test_every_shipped_tier_declares_three_usable_lengths() -> void:
	# `lengths_of` reads each segment's own `footprint.x` rather than a length field
	# beside it, so this is also the assertion that the footprints and the tier list
	# agree -- a `wall_lengths` naming a def whose footprint is square would collapse
	# two entries onto one key and silently lose a length.
	for tier in [&"building.wall_wood_short", &"building.wall_stone_short",
			&"building.wall_reinforced_short"]:
		var bd: BuildingDef = GameDataRegistry.building(tier)
		assert_not_null(bd, "%s exists" % tier)
		assert_true(bd.is_wall_run(), "%s is the tier's menu entry" % tier)
		var lengths := WallPlan.lengths_of(bd.wall_lengths, GameDataRegistry.building)
		assert_eq(lengths.size(), 3, "%s offers three lengths, got %s" % [tier, lengths])
		assert_eq(_by_content(lengths.keys()), [3, 6, 9] as Array,
				"%s is 3/6/9 tiles, got %s" % [tier, lengths.keys()])


func test_every_wall_piece_is_two_tiles_deep() -> void:
	# The measured art rounds to 2 for every civ (buildings.json), and the
	# segmentation assumes it: `footprint_for` writes DEPTH across the run.
	for id in GameDataRegistry.building_ids():
		if not String(id).begins_with("building.wall_"):
			continue
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_eq(bd.footprint.y, WallPlan.DEPTH, "%s is %s" % [id, bd.footprint])


func test_a_gate_spans_exactly_a_long_segment() -> void:
	# A gate has to be substitutable for a long piece or it cannot sit in a run
	# without leaving a gap -- 0 A.D. makes the gate an UPGRADE of a long wall for
	# this reason, and the price here is a half-tile of art overhang.
	for pair in [[&"building.wall_wood_gate", &"building.wall_wood_long"],
			[&"building.wall_stone_gate", &"building.wall_stone_long"],
			[&"building.wall_reinforced_gate", &"building.wall_reinforced_long"]]:
		var gate: BuildingDef = GameDataRegistry.building(pair[0])
		var long: BuildingDef = GameDataRegistry.building(pair[1])
		assert_eq(gate.footprint, long.footprint, "%s matches %s" % pair)
		assert_true(gate.is_gate, "%s is flagged a gate" % pair[0])


func _by_content(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(v)
	out.sort()
	return out
