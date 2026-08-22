## Short wall segments finishing next to each other become one longer piece
## (`WallMerge`, PLAN.md 5.8).
##
## Almost all of this is about what must NOT be merged, and that is the right balance:
## the merge itself is one substitution, while the ways it could eat something it
## should not -- a foundation somebody is walking to, a gate, another player's wall, a
## wall crossing this one -- are each a different mistake with the same symptom, a
## building that vanished.
##
## On a BARE map (`setup` without `MapGen.build`), like `test_build`: every case here
## is about where pieces sit relative to each other, and a generated map's trees would
## only add a reason for a segment to fail to be placed at all. Nothing is `force`d
## down for the same reason -- if two fixtures overlap, the second spawn returns null
## and the test says so instead of quietly testing one wall.
##
## Built by spawning finished segments directly rather than by dragging and waiting, so
## a case is three lines instead of four hundred ticks. The test that goes through a
## villager and `BuildSystem` is at the bottom, because the hook that calls any of this
## is the part a unit test of `WallMerge` cannot prove.
extends TestCase

const SHORT := &"building.wall_wood_short"
const MEDIUM := &"building.wall_wood_medium"
const LONG := &"building.wall_wood_long"
const GATE := &"building.wall_wood_gate"
const STONE_SHORT := &"building.wall_stone_short"

## Room for eighteen tiles of wall in either direction with space around it.
const AT := Vector2i(10, 10)

var world: SimWorld


func before_each() -> void:
	world = SimWorld.new()
	world.setup(MatchConfig.debug_single_player())
	var p := world.player_for(1)
	if p != null:
		p.age = 2                      # a wood gate is an age-2 upgrade
		for kind in [&"wood", &"stone", &"food", &"gold"]:
			p.stock[kind] = 10_000


## One finished segment of `def_id` at `origin`, laid along `axis`.
func _segment(def_id: StringName, origin: Vector2i, axis: int = WallPlan.AXIS_X,
		owner: int = 1) -> SimBuilding:
	var bd: BuildingDef = world.building_def(def_id)
	var b := world.spawn_building(def_id, owner, origin, SimBuilding.Phase.COMPLETE, false,
			WallPlan.footprint_for(bd.footprint.x, axis), WallPlan.FACING_FOR_AXIS[axis])
	assert_not_null(b, "%s went down at %s" % [def_id, origin])
	return b


## `count` finished short segments in a row from `AT`, low end first.
func _row(count: int, axis: int = WallPlan.AXIS_X, owner: int = 1) -> Array[SimBuilding]:
	var length: int = world.building_def(SHORT).footprint.x
	var step := Vector2i(length, 0) if axis == WallPlan.AXIS_X else Vector2i(0, length)
	var out: Array[SimBuilding] = []
	for i in range(count):
		out.append(_segment(SHORT, AT + step * i, axis, owner))
	return out


func _walls() -> Array[SimBuilding]:
	var out: Array[SimBuilding] = []
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and String(e.def_id).begins_with("building.wall_"):
			out.append(e)
	return out


# ── merging ────────────────────────────────────────────────────────────────

func test_two_shorts_that_meet_become_one_medium() -> void:
	var row := _row(2)
	assert_true(WallMerge.apply(world, row[1]), "the second one finishing triggers it")

	assert_eq(_walls().size(), 1, "one wall where there were two")
	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_not_null(merged, "the piece at the low end is the one that survives")
	assert_eq(merged.def_id, MEDIUM)
	assert_eq(merged.footprint, Vector2i(6, WallPlan.DEPTH))
	assert_null(world.get_entity(row[1].id), "the other is gone")


func test_three_shorts_become_one_long() -> void:
	var row := _row(3)
	assert_true(WallMerge.apply(world, row[2]))
	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_eq(merged.def_id, LONG)
	assert_eq(merged.footprint, Vector2i(9, WallPlan.DEPTH))
	assert_eq(_walls().size(), 1)


func test_the_merged_wall_keeps_the_ground_all_the_pieces_held() -> void:
	# The thing that would be worst to get wrong: occupancy is keyed by id over a rect,
	# so a merge that cleared the absorbed pieces and grew the survivor in the wrong
	# order would leave a walkable hole in a solid wall -- and the wall would still LOOK
	# continuous.
	var row := _row(3)
	var rect := Rect2i(row[0].origin_tile(), Vector2i(9, WallPlan.DEPTH))
	assert_true(WallMerge.apply(world, row[2]))

	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_eq(merged.footprint_rect(), rect, "the union of the three, exactly")
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			assert_eq(world.map.occupant(Vector2i(x, y)), merged.id,
					"tile %d,%d is held by the merged wall" % [x, y])
	assert_false(world.map.can_place_building(rect), "and nothing can be built on it")


func test_a_north_south_wall_merges_along_its_own_axis() -> void:
	# The transposed footprint is where an axis mix-up would show, and a wall lying
	# across its own run has the same origin and the same hash as one lying along it
	# (WallPlan's own warning) -- so it is asserted rather than looked at.
	var row := _row(3, WallPlan.AXIS_Y)
	assert_true(WallMerge.apply(world, row[2]))
	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_eq(merged.def_id, LONG)
	assert_eq(merged.footprint, Vector2i(WallPlan.DEPTH, 9), "grown along +y, not +x")
	assert_eq(merged.origin_tile(), AT, "and still standing where it started")


func test_health_is_the_sum_of_the_pieces() -> void:
	var row := _row(2)
	row[1].hp = 100                        # one of them has been chewed on
	assert_true(WallMerge.apply(world, row[1]))
	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_eq(merged.hp, 400 + 100, "400 undamaged plus the 100 left of the other")
	assert_eq(merged.max_hp, 800, "on a medium wall's bar")


func test_an_undamaged_merge_comes_out_undamaged() -> void:
	# Wall health is authored per tile, so this is exact rather than approximate -- and
	# if that proportion is ever broken in buildings.json, this is what says so.
	var row := _row(3)
	assert_true(WallMerge.apply(world, row[2]))
	var merged := world.get_entity(row[0].id) as SimBuilding
	assert_eq(merged.hp, merged.max_hp, "three full shorts are one full long")


func test_a_medium_and_a_short_make_a_long() -> void:
	# The case a player reaches by walling in stages: the merge does not care that the
	# pieces are different lengths, only that they add up to one the tier declares.
	var medium := _segment(MEDIUM, AT)
	var short := _segment(SHORT, AT + Vector2i(6, 0))
	assert_true(WallMerge.apply(world, short))
	assert_eq((world.get_entity(medium.id) as SimBuilding).def_id, LONG)
	assert_eq(_walls().size(), 1)


func test_six_shorts_become_two_longs_rather_than_three_mediums() -> void:
	# Longest-first, the same rule `WallPlan` fills a drag with, so a wall built in
	# stages ends up the shape one drag would have laid.
	var row := _row(6)
	assert_true(WallMerge.apply(world, row[5]), "the top three go first")
	assert_true(WallMerge.apply(world, row[0]), "then the bottom three")
	var walls := _walls()
	assert_eq(walls.size(), 2)
	for wall in walls:
		assert_eq(wall.def_id, LONG)


func test_a_merged_long_can_still_become_a_gate() -> void:
	# Worth its own test because it is the payoff and not a side effect: a gate is an
	# upgrade of the LONG piece, so until now a player who walled a gap in short pieces
	# could never put a door in their own wall.
	var row := _row(3)
	assert_true(WallMerge.apply(world, row[2]))
	var merged := world.get_entity(row[0].id) as SimBuilding
	var cmd := UpgradeBuildingCommand.new(1, merged.id)
	assert_true(cmd.validate(world), "the merged piece is a legal gate site")
	world.queue_command(cmd)
	world.step()
	assert_eq((world.get_entity(row[0].id) as SimBuilding).def_id, GATE)


# ── what must not be merged ────────────────────────────────────────────────

func test_a_lone_segment_is_left_alone() -> void:
	var row := _row(1)
	assert_false(WallMerge.apply(world, row[0]), "nothing to merge with")
	assert_eq((world.get_entity(row[0].id) as SimBuilding).def_id, SHORT)


func test_two_pieces_with_a_gap_between_them_are_two_walls() -> void:
	var first := _segment(SHORT, AT)
	var second := _segment(SHORT, AT + Vector2i(4, 0))     # one tile short of touching
	assert_false(WallMerge.apply(world, second), "a wall with a hole is not one wall")
	assert_eq(_walls().size(), 2)
	assert_eq((world.get_entity(first.id) as SimBuilding).def_id, SHORT)


func test_an_unfinished_neighbour_is_not_absorbed() -> void:
	# The project owner's call, and the reason for it: the foundation is what a villager
	# is walking towards, and merging it away would send them to a building that no
	# longer exists.
	var done := _segment(SHORT, AT)
	var footprint := WallPlan.footprint_for(
			world.building_def(SHORT).footprint.x, WallPlan.AXIS_X)
	var digging := world.spawn_building(SHORT, 1, AT + Vector2i(3, 0),
			SimBuilding.Phase.FOUNDATION, false, footprint,
			WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_X])
	assert_not_null(digging)
	assert_false(WallMerge.apply(world, done))
	assert_eq(_walls().size(), 2)
	assert_not_null(world.get_entity(digging.id), "the foundation is still standing")

	# And it merges the moment it IS finished, which is the other half of the rule.
	digging.phase = SimBuilding.Phase.COMPLETE
	digging.hp = digging.max_hp
	assert_true(WallMerge.apply(world, digging))
	assert_eq((world.get_entity(done.id) as SimBuilding).def_id, MEDIUM)


func test_another_players_wall_is_not_absorbed() -> void:
	var mine := _segment(SHORT, AT, WallPlan.AXIS_X, 1)
	var theirs := _segment(SHORT, AT + Vector2i(3, 0), WallPlan.AXIS_X, 2)
	assert_false(WallMerge.apply(world, mine), "two players, two walls")
	assert_not_null(world.get_entity(theirs.id))
	assert_eq((world.get_entity(mine.id) as SimBuilding).def_id, SHORT)


func test_a_different_tier_is_not_absorbed() -> void:
	# Stone and wood pieces are the same size and the same shape. Merging across tiers
	# would either upgrade a wood wall for free or downgrade a stone one.
	var wood := _segment(SHORT, AT)
	var stone := _segment(STONE_SHORT, AT + Vector2i(3, 0))
	assert_false(WallMerge.apply(world, stone))
	assert_eq(_walls().size(), 2)
	assert_eq((world.get_entity(wood.id) as SimBuilding).def_id, SHORT)


func test_a_gate_is_never_merged_away() -> void:
	# Two shorts beside a gate: the shorts are one wall, the gate is a door and stays a
	# door. It falls out of the data -- no tier's `wall_lengths` names a gate -- rather
	# than being a rule in WallMerge, so this is the test that would catch the day one
	# does.
	var gate := _segment(GATE, AT)
	var row: Array[SimBuilding] = [
		_segment(SHORT, AT + Vector2i(9, 0)),
		_segment(SHORT, AT + Vector2i(12, 0)),
	]
	assert_true(WallMerge.apply(world, row[1]), "the two shorts still merge")
	assert_eq((world.get_entity(gate.id) as SimBuilding).def_id, GATE, "the gate is untouched")
	assert_eq((world.get_entity(row[0].id) as SimBuilding).def_id, MEDIUM)


func test_a_wall_crossing_this_one_is_not_part_of_it() -> void:
	# A T junction. The two are different walls, and merging them would claim a
	# footprint at right angles to itself.
	var along := _segment(SHORT, AT)
	var across := _segment(SHORT, AT + Vector2i(3, 0), WallPlan.AXIS_Y)
	assert_false(WallMerge.apply(world, along), "different axes are different walls")
	assert_eq(_walls().size(), 2)
	assert_not_null(world.get_entity(across.id))


func test_a_parallel_wall_on_the_next_row_is_not_part_of_it() -> void:
	# Two east-west walls stacked, offset along the run so their corners touch
	# diagonally. Neither is on the other's line.
	var first := _segment(SHORT, AT)
	var beside := _segment(SHORT, AT + Vector2i(3, WallPlan.DEPTH))
	assert_false(WallMerge.apply(world, first), "a wall on the next row is not this wall")
	assert_eq((world.get_entity(beside.id) as SimBuilding).def_id, SHORT)


func test_a_run_that_adds_up_to_nothing_declared_is_left_as_it_is() -> void:
	# A long and a short: twelve tiles, and no tier declares twelve. This is exactly
	# what a single drag of twelve lays down, so merging here would be the system
	# undoing its own segmentation on the next completion.
	var long := _segment(LONG, AT)
	var short := _segment(SHORT, AT + Vector2i(9, 0))
	assert_false(WallMerge.apply(world, short))
	assert_eq(_walls().size(), 2)
	assert_eq((world.get_entity(long.id) as SimBuilding).def_id, LONG)


func test_the_result_does_not_depend_on_which_piece_finished_last() -> void:
	# Two hosts can complete the same wall in a different order -- the builders are
	# spread round-robin and one may be interrupted -- so which piece triggers the merge
	# must not change what comes out of it, or they desync.
	var row := _row(3)
	var from_last := WallMerge.plan(world, row[2])
	var from_first := WallMerge.plan(world, row[0])
	var from_middle := WallMerge.plan(world, row[1])
	assert_eq(from_last["survivor_id"], from_first["survivor_id"])
	assert_eq(from_last["survivor_id"], from_middle["survivor_id"])
	assert_eq(from_last["def_id"], from_first["def_id"])
	assert_eq(from_last["origin"], from_middle["origin"])


func test_a_merge_reports_no_destruction() -> void:
	# `despawn` is the silent removal and the destruction path (5.5) is not: a merged
	# piece must leave no rubble, because rubble is how a player reads "something of
	# mine was killed here".
	var row := _row(2)
	assert_true(WallMerge.apply(world, row[1]))
	for e in world.entities.values():
		if e is SimBuilding:
			assert_ne((e as SimBuilding).phase, SimBuilding.Phase.DESTROYED,
					"nothing was destroyed by a merge")
	assert_true(world.removed_this_tick.has(row[1].id),
			"the absorbed piece is reported as gone, so clients drop its view node")


# ── the hook ───────────────────────────────────────────────────────────────

func test_finishing_a_segment_in_a_real_tick_merges_it() -> void:
	# The tests above call WallMerge directly. This is the only one that proves anything
	# ever calls it: a villager puts the last point of progress into the second segment,
	# and the wall becomes one piece on that tick.
	var first := _segment(SHORT, AT)
	var footprint := WallPlan.footprint_for(
			world.building_def(SHORT).footprint.x, WallPlan.AXIS_X)
	var second := world.spawn_building(SHORT, 1, AT + Vector2i(3, 0),
			SimBuilding.Phase.UNDER_CONSTRUCTION, false, footprint,
			WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_X])
	assert_not_null(second)
	# One tick short of done, so this costs a walk rather than 120 ticks of building.
	second.build_progress = second.build_total - 1

	# `spawn_unit` takes a TILE and puts the unit in the middle of it; passing a
	# sub-tile position here spawns a villager thousands of tiles off the map, which
	# is exactly what the first draft of this test did.
	var builder := world.spawn_unit(&"unit.villager", 1, AT + Vector2i(4, -3))
	assert_not_null(builder)
	world.queue_command(BuildCommand.new(1, [builder.id], second.id))

	var absorbed := false
	for i in range(60):
		world.step()
		if world.get_entity(second.id) == null:
			absorbed = true
			break
	assert_true(absorbed, "the villager arrived, finished it, and it was merged away")

	var merged := world.get_entity(first.id) as SimBuilding
	assert_eq(merged.def_id, MEDIUM, "the wall is one medium segment")
	assert_eq(merged.footprint, Vector2i(6, WallPlan.DEPTH))
	assert_eq(merged.origin_tile(), AT)
