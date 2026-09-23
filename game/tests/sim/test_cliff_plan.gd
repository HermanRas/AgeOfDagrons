## `CliffPlan` derives a plateau's pieces from which tiles are high (#97).
##
## ## WHAT IS WORTH TESTING HERE, AND IT IS NOT "DOES IT EMIT PIECES"
##
## Every fault this class has had was a piece in the wrong PLACE or a piece missing at exactly
## one spot, and both shipped looking right. An assertion that counts entities passes through
## all of them. So these tests name tiles.
##
## Three of them are regressions of faults the owner found by eye:
##
##   - a face AND a crest on every tile of an N-S run (*"artifacts down the side"*)
##   - a corner stood down because ONE of its sides had a notch (*"the corners are missing"*)
##   - an `AXIS_D2` run collapsing to 1-tile pieces because it was walked from its far end
##
## The third never reached the owner because this file caught it, which is the argument for
## the file: it is invisible to anything that counts, and it is the stamped repeat coming back.
extends TestCase


## A solid rectangle of high ground.
func _rect(at: Vector2i, size: Vector2i) -> Dictionary:
	var high: Dictionary = {}
	for y in range(size.y):
		for x in range(size.x):
			high[at + Vector2i(x, y)] = true
	return high


## The plateau that is square ON SCREEN: a box in `(u, v) = (x + y, x - y)`. Its N-S sides are
## the staircase and its E-W sides are chains of notches, so it exercises every rule at once.
func _pedestal(centre: Vector2i, half_u: int, half_v: int) -> Dictionary:
	var high: Dictionary = {}
	var reach := half_u + half_v + 2
	for y in range(centre.y - reach, centre.y + reach + 1):
		for x in range(centre.x - reach, centre.x + reach + 1):
			var t := Vector2i(x, y)
			if absi((t.x + t.y) - (centre.x + centre.y)) <= half_u \
					and absi((t.x - t.y) - (centre.x - centre.y)) <= half_v:
				high[t] = true
	return high


func _at(plan: Array[Dictionary], tile: Vector2i) -> Array[StringName]:
	var out: Array[StringName] = []
	for r in plan:
		if r["tile"] == tile:
			out.append(r["def_id"])
	return out


func _count(plan: Array[Dictionary], def_id: StringName) -> int:
	var n := 0
	for r in plan:
		if r["def_id"] == def_id:
			n += 1
	return n


# ── the ladder ──────────────────────────────────────────────────────────────


## ⛔ NOT A GREEDY FILL, which is the difference from `WallPlan` and the reason it is separate.
## Every piece is a window onto one 16 m strip and every window opens at u = 0, so mixing
## lengths in one run restarts the rock at unrelated places. The owner photographed that seam.
func test_a_run_takes_the_longest_rung_that_divides_it_exactly() -> void:
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 9), 9, "nine is one long piece")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 18), 9, "and eighteen is two of them")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 12), 6, "twelve is two mediums, NOT 9 + 3")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 6), 6)
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 3), 3)
	# The stamped case, and it is deliberate: 8 divides by nothing on the ladder but 1, so it
	# is laid in fillers rather than left with a short tail of a different length.
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 8), 1, "eight has no rung, so it is fillers")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE, 1), 1)


## The diagonal ladder has no 6, so a 6-step run must fall to 3 and NOT to 1.
func test_a_six_step_diagonal_falls_to_two_threes_and_not_to_fillers() -> void:
	assert_false(CliffPlan.FACE_DIAG.has(6), "there is no 6-step diagonal -- its anchor is off-grid")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE_DIAG, 6), 3, "so a six-run is 3 + 3")
	assert_eq(CliffPlan.length_for(CliffPlan.FACE_DIAG, 9), 9)


# ── a grid-aligned plateau ──────────────────────────────────────────────────


func test_the_near_edges_take_the_face_and_the_far_edges_the_crest() -> void:
	var high := _rect(Vector2i(10, 10), Vector2i(9, 9))
	var plan := CliffPlan.plan(high)

	# ⚠️ **NAMED AT THE RUN'S START, WHICH IS WHERE A MERGED PIECE STANDS.** A nine-long face
	# covers (18,10)..(18,18) and its entity sits on the first of them; asking the middle tile
	# is how the first version of this test failed, and it fails identically whether the merge
	# worked or not.
	assert_true(_at(plan, Vector2i(18, 10)).has(&"building.cliff_face_long"),
			"the +x column is one nine-long face")
	assert_true(_at(plan, Vector2i(10, 9)).is_empty(),
			"nothing stands on the low ground above a far edge")
	assert_true(_at(plan, Vector2i(10, 10)).has(&"building.cliff_back_long"),
			"the -y row is one nine-long crest")


## ⛔ REGRESSION FOR `_drop_shadowed_runs`. The shared corner of this plateau carries the near
## column's face AND the far row's crest, so a per-tile suppression drops that one crest --
## taking the row from 9 to 8, which divides by no rung and reverts the WHOLE row to fillers
## while the near edges opposite it stay one long piece. Asserted as the length rather than as
## the corner, because the length is the thing that would be seen.
func test_a_far_row_keeps_its_full_length_through_the_corner_it_shares() -> void:
	var high := _rect(Vector2i(10, 10), Vector2i(9, 9))
	for run in CliffPlan.runs_of(high):
		if run["def_id"] == &"building.cliff_back" and int(run["axis"]) == WallPlan.AXIS_X:
			assert_eq(int(run["span"]), 9, "the far row runs the full nine")
			assert_eq(int(run["piece"]), 9, "so it is one long crest and not nine fillers")
			return
	assert_true(false, "no far crest row was planned at all")


## ⛔ THE NEAR-NEAR CORNER, which has no notch tile to address it -- both its diagonal
## neighbours are low -- so it is addressed by the HIGH corner instead.
func test_the_outer_corner_gets_a_diagonal_addressed_by_the_high_tile() -> void:
	var high := _rect(Vector2i(10, 10), Vector2i(9, 9))
	var plan := CliffPlan.plan(high)
	assert_true(_at(plan, Vector2i(18, 18)).has(&"building.cliff_face_diag"),
			"the near-near corner carries the diagonal")
	assert_true(_at(plan, Vector2i(10, 10)).has(&"building.cliff_back_diag"),
			"and the far-far corner carries the crest diagonal")


# ── the screen-aligned plateau, where the two reported faults were ──────────


## ⛔ REGRESSION, owner 2026-09-23: *"the up and down piece still has artifacts down the side."*
##
## `+x` and `-y` are BOTH the screen-right side of a tile. A grid-aligned plateau never has a
## drop on both, so the rules could treat them independently; this shape has one on every tile
## of both N-S runs and drew a face and a crest from the same anchor.
func test_an_n_s_run_takes_faces_and_no_crest_over_them() -> void:
	var high := _pedestal(Vector2i(40, 40), 10, 6)
	var plan := CliffPlan.plan(high)

	var doubled: Array[Vector2i] = []
	for r in plan:
		var here := _at(plan, r["tile"] as Vector2i)
		var has_face := here.has(&"building.cliff_face") or here.has(&"building.cliff_face_short") \
				or here.has(&"building.cliff_face_medium") or here.has(&"building.cliff_face_long")
		var has_back := here.has(&"building.cliff_back") or here.has(&"building.cliff_back_short") \
				or here.has(&"building.cliff_back_medium") or here.has(&"building.cliff_back_long")
		if has_face and has_back and not doubled.has(r["tile"]):
			doubled.append(r["tile"] as Vector2i)
	assert_eq(doubled, [] as Array[Vector2i],
			"no tile carries an axis face and an axis crest at once")


## ⛔ REGRESSION, owner 2026-09-23: *"the corners are still missing."* A notch covers the gap on
## ITS OWN side alone, so testing whether EITHER side had one cancelled the corner at a run's
## end, where one side is off the plateau and has none.
func test_a_corner_survives_a_notch_on_one_side_of_it() -> void:
	var high := _pedestal(Vector2i(40, 40), 10, 6)
	var singles := CliffPlan._classify(high)
	var diag_at: Dictionary = {}
	for r in singles:
		if r["def_id"] == &"building.cliff_face_diag":
			diag_at[r["tile"]] = true

	# ⛔ **STATED AS THE RULE RATHER THAN AS ONE TILE I WORKED OUT BY HAND.** Naming a tile here
	# is how the first version of this test failed: I picked the shape's down-screen extreme,
	# which legitimately carries nothing because it has a notch on BOTH sides. Checking the
	# rule over every tile cannot be wrong about which tile is which.
	var wrong: Array[Vector2i] = []
	for t in high:
		var tile: Vector2i = t
		if high.has(tile + Vector2i(1, 0)) or high.has(tile + Vector2i(0, 1)):
			continue          # not an outer corner at all
		var both := CliffPlan._near_notch(tile + Vector2i(1, 0), high) \
				and CliffPlan._near_notch(tile + Vector2i(0, 1), high)
		if diag_at.has(tile) == both:
			wrong.append(tile)
	assert_eq(wrong, [] as Array[Vector2i],
			"a corner is stood down when BOTH its sides are notches and never when one is")


# ── merging, and the fault this file caught before the owner did ────────────


## ⛔ REGRESSION: an `AXIS_D2` run steps (+1, -1), so in a list ordered by y its FIRST record is
## its LAST tile. Walking forward from there finds nothing and every diagonal becomes a run of
## one -- the E-W edge silently reverting to the stamped 1-tile repeat, invisible to any test
## that counts entities rather than naming them.
func test_a_diagonal_run_merges_rather_than_collapsing_to_fillers() -> void:
	var high := _pedestal(Vector2i(40, 40), 10, 6)
	var runs := CliffPlan.runs_of(high)
	var longest := 0
	for r in runs:
		if int(r["axis"]) == WallPlan.AXIS_D2:
			longest = maxi(longest, int(r["span"]))
	assert_true(longest >= 3,
			"the E-W notch chain is found as one run, not as %d runs of one" % longest)


## A merged diagonal is ART ONLY, so it brings its own blockers -- and they come AFTER it,
## because `SimMap.set_occupied` assigns the blocking byte rather than merging into it.
func test_a_merged_diagonal_brings_blockers_and_the_art_goes_first() -> void:
	var high := _pedestal(Vector2i(40, 40), 10, 6)
	var plan := CliffPlan.plan(high)

	var art := -1
	for i in range(plan.size()):
		if plan[i]["def_id"] == &"building.cliff_face_diag_short" \
				or plan[i]["def_id"] == &"building.cliff_face_diag_long":
			art = i
			break
	if art < 0:
		return          # this shape merged nothing; the run test above is what guards that
	assert_eq(plan[art + 1]["def_id"], CliffPlan.BLOCKER,
			"the blockers follow the art immediately, so they cannot be cleared by it")


## A 1-tile diagonal blocks on its own and must NOT be given blockers as well.
func test_an_unmerged_diagonal_is_left_alone() -> void:
	var high := _rect(Vector2i(10, 10), Vector2i(9, 9))
	var plan := CliffPlan.plan(high)
	assert_eq(_count(plan, CliffPlan.BLOCKER), 0,
			"a plateau whose diagonals are all single corners needs no blockers")


func test_an_empty_plateau_plans_nothing() -> void:
	assert_eq(CliffPlan.plan({}).size(), 0, "no high ground, no cliff, and no crash")
