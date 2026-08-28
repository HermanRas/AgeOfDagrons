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


func test_a_square_drag_falls_to_the_x_axis() -> void:
	# `>=` in the comparison, so an exactly-45-degree drag has a defined answer
	# rather than depending on float noise. Which axis it picks matters less than
	# that both hosts pick the same one.
	var plan := WallPlan.plan(Vector2i(0, 0), Vector2i(9, 9), LENGTHS)
	assert_eq(int(plan["axis"]), WallPlan.AXIS_X)


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
