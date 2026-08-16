## Who is hidden behind what (PLAN.md 3.1), and who therefore gets an outline.
##
## Pure tile geometry, so it can be asserted rather than judged from a
## screenshot -- which matters because the two bugs this rule has had were both
## found by LOOKING: villagers clipping at drop-off, then villagers standing on
## the town centre's roof after that was cured too broadly.
extends TestCase

## A 10x10 town centre at (10, 10), so tiles 10..19 in both axes. Its front tile
## -- the one it sorts by -- is (19, 19).
const TC := Rect2i(10, 10, 10, 10)


# ── which side of the building are we on ────────────────────────────────────

func test_past_the_south_or_east_extent_is_in_front() -> void:
	# The two directions Iso projects DOWN-screen, and the only two that earn a
	# unit the sort lift over a building.
	assert_true(Occlusion.is_in_front(Vector2i(15, 20), TC), "one tile south")
	assert_true(Occlusion.is_in_front(Vector2i(20, 15), TC), "one tile east")
	assert_true(Occlusion.is_in_front(Vector2i(20, 20), TC), "the south-east corner")


func test_north_and_west_are_not_in_front() -> void:
	# This is the roof-standing bug in one assertion. Both of these touch the
	# footprint, and touching used to be the whole test.
	assert_false(Occlusion.is_in_front(Vector2i(15, 9), TC), "one tile north")
	assert_false(Occlusion.is_in_front(Vector2i(9, 15), TC), "one tile west")
	assert_false(Occlusion.is_in_front(Vector2i(9, 9), TC), "the north-west corner")


# ── who is hidden ───────────────────────────────────────────────────────────

func test_a_unit_just_behind_the_building_is_hidden() -> void:
	assert_true(Occlusion.hides(TC, Vector2i(15, 9)), "against the north edge")
	assert_true(Occlusion.hides(TC, Vector2i(9, 15)), "against the west edge")


func test_a_unit_in_front_is_never_hidden() -> void:
	# It is drawn over the building, so an outline would be a rim around a sprite
	# the player can already see.
	assert_false(Occlusion.hides(TC, Vector2i(15, 20)))
	assert_false(Occlusion.hides(TC, Vector2i(20, 15)))
	assert_false(Occlusion.hides(TC, Vector2i(25, 25)), "well clear in front")


func test_the_reach_stops_at_five_tiles() -> void:
	# Buildings are tall but not endless. Outlining everything behind a wonder
	# would be noise rather than information.
	assert_true(Occlusion.hides(TC, Vector2i(15, 10 - Occlusion.BEHIND_TILES)),
			"five tiles back is still under the sprite")
	assert_false(Occlusion.hides(TC, Vector2i(15, 10 - Occlusion.BEHIND_TILES - 1)),
			"six is not")


func test_a_unit_beside_the_building_on_screen_is_not_hidden() -> void:
	# The subtle one, and the reason the column test exists at all. Iso sends
	# (x - y) to screen x, so tile distance and screen distance are different
	# questions: a unit can be five tiles away in the grid and either squarely
	# behind the sprite or well off to one side of it, depending on direction.
	#
	# The town centre's own column range is -9..9. These two are outside it.
	assert_false(Occlusion.hides(TC, Vector2i(5, 17)),
			"column -12, off the building's left-hand side on screen")
	assert_false(Occlusion.hides(TC, Vector2i(17, 5)),
			"column 12, off its right")


func test_five_tiles_away_can_still_be_squarely_behind_it() -> void:
	# The same distance in the other diagonal. (5, 14) is column -9 -- exactly
	# the column of the town centre's west corner -- and ten depth-steps up from
	# it, which on a 190 px-tall sprite is underneath. Distance alone would have
	# called this "beside" and left a villager invisible with no outline.
	assert_true(Occlusion.hides(TC, Vector2i(5, 14)))


func test_a_unit_standing_on_the_footprint_is_not_hidden() -> void:
	# Cannot happen -- a footprint is occupied ground -- but the rule must not
	# answer nonsense if it ever does.
	assert_false(Occlusion.hides(TC, Vector2i(15, 15)))


func test_a_degenerate_footprint_hides_nothing() -> void:
	assert_false(Occlusion.hides(Rect2i(0, 0, 0, 0), Vector2i(0, 0)))


func test_a_one_tile_building_still_hides_what_is_behind_it() -> void:
	# Every rule here is written against a 10x10; a 1x1 exercises the edges of
	# the same arithmetic, where an off-by-one would show.
	var hut := Rect2i(10, 10, 1, 1)
	assert_true(Occlusion.hides(hut, Vector2i(9, 10)))
	assert_true(Occlusion.hides(hut, Vector2i(10, 9)))
	assert_false(Occlusion.hides(hut, Vector2i(11, 10)), "east of it is in front")
	assert_false(Occlusion.hides(hut, Vector2i(10, 11)), "south of it is in front")


# ── the gap measurement it shares with the rest of the sim ──────────────────

func test_the_gap_is_measured_to_the_footprint_not_its_centre() -> void:
	# Same rule as CombatSystem.tile_gap and GatherSystem.harvest_rect: a big
	# building measured centre-out is wrong by half its own size.
	assert_eq(Occlusion.gap_to(Vector2i(15, 15), TC), 0, "inside")
	assert_eq(Occlusion.gap_to(Vector2i(9, 15), TC), 1, "touching the west edge")
	assert_eq(Occlusion.gap_to(Vector2i(5, 15), TC), 5)
