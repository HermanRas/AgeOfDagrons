## Phase 4.4: walk to a foundation and raise it, one villager's worth of progress
## per tick, until it completes.
extends TestCase

var w: SimWorld
var villager: SimUnit
var house: SimBuilding


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	house = w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, true)
	villager = w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))


func _order_build() -> void:
	w.queue_command(BuildCommand.new(1, [villager.id], house.id))


func _run_until(pred: Callable, max_ticks: int) -> int:
	for i in range(max_ticks):
		w.step()
		if pred.call():
			return i + 1
	return -1


func test_a_villager_walks_to_the_foundation_and_raises_it_to_completion() -> void:
	_order_build()
	var ticks := _run_until(func(): return house.is_complete(), 500)
	assert_true(ticks > 0, "it finished rather than stalling")
	assert_eq(house.phase, SimBuilding.Phase.COMPLETE)
	assert_eq(house.hp, house.max_hp, "full health on completion, not left at the starting sliver")
	assert_true(villager.is_idle(), "retired once there was nothing left to build")


func test_the_foundation_shows_progress_partway_through() -> void:
	_order_build()
	_run_until(func(): return house.build_progress > 0, 200)
	assert_true(house.build_progress < house.build_total, "still under way, not already done")
	assert_eq(house.phase, SimBuilding.Phase.UNDER_CONSTRUCTION)


func test_hp_rises_with_build_progress_instead_of_sitting_at_the_starting_sliver() -> void:
	# Found live in a playtest: the health bar is the only build-progress
	# indicator the panel draws (5.6), and it sat frozen at the spawn sliver
	# for the whole build instead of reading as "under way".
	_order_build()
	var starting_hp := house.hp
	_run_until(func(): return house.build_progress > house.build_total / 2, 300)
	assert_true(house.hp > starting_hp, "risen well past the starting sliver")
	assert_almost_eq(float(house.hp) / float(house.max_hp), house.build_fraction(), 0.01,
			"the health bar and the build bar agree")


# ── rejection ───────────────────────────────────────────────────────────────

func test_build_command_rejects_an_already_complete_building() -> void:
	var done := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	var cmd := BuildCommand.new(1, [villager.id], done.id)
	assert_false(cmd.validate(w))


func test_build_command_rejects_a_building_owned_by_someone_else() -> void:
	house.owner_id = 2
	var cmd := BuildCommand.new(1, [villager.id], house.id)
	assert_false(cmd.validate(w))


# ── carrying on to the next foundation (2026-08-22) ─────────────────────────
#
# Reported from play: "builder does not continue to build all the pieces, stops after
# 1". It did -- `BuildSystem._finished` called `stop()` for anything that was not a
# field, and there was no re-scan at all. Harmless while a placement was one building;
# a wall drag lays a dozen at once and spread its crew round-robin across them, so
# every villager downed tools after its first segment and the wall never went up.
#
# 1082 tests did not catch it, because every build fixture in the suite placed exactly
# one foundation -- so `stop()` was always the right answer and nothing ever asked for
# a second. That is the gap these fill.


## A second foundation `dx` tiles east of the first. A house is 4x4, so anything from
## `_another(4)` on clears the first one's 10..13.
func _another(dx: int, owner: int = 1) -> SimBuilding:
	return w.spawn_building(&"building.house", owner, Vector2i(10 + dx, 10),
			SimBuilding.Phase.FOUNDATION, true)


## A foundation the mate CANNOT finish first: a castle is 2000 ticks against a house's
## 250, so whenever the tests below need somebody still visibly working on something,
## this is what they put them on.
##
## The alternative -- a second house -- is a race, and it is one the fixture loses: the
## mate starts nearer, finishes its house before our villager finishes theirs, and by
## the time the ranking is asked the "claimed" foundation is complete and gone from the
## candidates. Two of these tests were written that way and asserted the wrong thing
## for the wrong reason. A castle is 7x7 and occupies y 10..16.
func _a_slow_foundation(dx: int) -> SimBuilding:
	return w.spawn_building(&"building.castle", 1, Vector2i(10 + dx, 10),
			SimBuilding.Phase.FOUNDATION, true)


## A second builder, standing SOUTH of the row of foundations rather than among them.
##
## The row occupies y 10..13, and the first version of this put its mate at y 12 --
## inside a footprint. A unit inside blocked ground is one `AStarGrid2D` will not plan
## a route out of, so its build order came back with an empty path and retired on the
## spot (`SimWorld._evict_from_footprint` records the same trap costing the AI a
## barracks). The mate then claimed nothing and the test blamed the ranking.
func _a_mate(x: int) -> SimUnit:
	return w.spawn_unit(&"unit.villager", 1, Vector2i(x, 20))


## Run until the first house is up, then one more tick so `_finished` has been seen.
func _build_the_first() -> void:
	_order_build()
	assert_true(_run_until(func(): return house.is_complete(), 600) > 0,
			"the first house went up")


func test_a_builder_moves_on_to_the_next_foundation_instead_of_stopping() -> void:
	var next := _another(5)
	_build_the_first()
	assert_eq(villager.task, SimUnit.Task.BUILD, "still working, not idle")
	assert_eq(villager.task_target_id, next.id, "and on the other foundation")


func test_the_crew_actually_finishes_a_whole_row_of_foundations() -> void:
	# The end-to-end shape of the report. One villager, four foundations, no further
	# orders -- before the fix exactly one of them would ever have been built.
	var all_four: Array[SimBuilding] = [house, _another(5), _another(9), _another(13)]
	_order_build()
	var done := func() -> bool:
		for b in all_four:
			if not b.is_complete():
				return false
		return true
	assert_true(_run_until(done, 4000) > 0, "all four went up off one order")


func test_it_prefers_a_foundation_nobody_is_already_raising() -> void:
	# What preserves `PlaceWallCommand`'s round-robin spread. Without it the first
	# villager to finish joins the second one's segment, they finish it together, and
	# the crew walks the wall as a single pack -- correct, and about as slow as one
	# villager doing the lot.
	# The claimed one is deliberately the NEARER of the two -- a castle two tiles away
	# against a house nine tiles away -- so distance alone would pick the wrong answer
	# and only the claim check can produce the right one.
	var taken := _a_slow_foundation(4)
	var free := _another(11)
	var mate := _a_mate(16)
	w.queue_command(BuildCommand.new(1, [mate.id], taken.id))

	_build_the_first()
	assert_false(taken.is_complete(), "the mate is still on it, so it is really claimed")
	assert_eq(villager.task_target_id, free.id,
			"took the unclaimed foundation over the nearer claimed one")


func test_a_lone_claimed_foundation_is_still_better_than_standing_still() -> void:
	# Ranked, not filtered: a crew larger than the number of foundations must all find
	# work rather than stopping the moment every site has somebody on it.
	var only := _a_slow_foundation(5)
	var mate := _a_mate(16)
	w.queue_command(BuildCommand.new(1, [mate.id], only.id))

	_build_the_first()
	assert_false(only.is_complete(), "still going, so it is the only work there is")
	assert_eq(villager.task_target_id, only.id, "joined it rather than idling")


func test_it_does_not_go_further_than_the_same_work_radius() -> void:
	# The bound that keeps this "the site I am on" rather than "every building site I
	# own". A villager who finishes a house must not set off across the map on an
	# order the player did not give and cannot see coming.
	var far := _another(SimSystem.SAME_WORK_RADIUS + 12)
	_build_the_first()
	assert_true(villager.is_idle(), "nothing within reach, so it stands down")
	assert_false(far.is_complete())


func test_it_does_not_pick_up_somebody_elses_foundation() -> void:
	var theirs := _another(5, 2)
	_build_the_first()
	assert_true(villager.is_idle(), "an enemy's building site is not work")
	assert_eq(theirs.build_progress, 0)


func test_a_finished_building_is_not_mistaken_for_work() -> void:
	w.spawn_building(&"building.house", 1, Vector2i(15, 10),
			SimBuilding.Phase.COMPLETE, true)
	_build_the_first()
	assert_true(villager.is_idle(), "there is nothing left to raise")


func test_rubble_is_not_mistaken_for_work() -> void:
	# Rubble stays in `entities` with `alive` false and a phase of its own (5.5). It is
	# not complete, so a check that only asked `is_complete()` would send a villager to
	# rebuild a corpse.
	var wreck := _another(5)
	wreck.phase = SimBuilding.Phase.DESTROYED
	wreck.alive = false
	_build_the_first()
	assert_true(villager.is_idle(), "wreckage is not a foundation")


func test_a_field_still_puts_its_builder_straight_to_farming() -> void:
	# The 2026-08-17 rule, which the re-scan must not have displaced: a field is
	# harvestable the moment it is up, and farming it beats walking off to another
	# foundation even when one is standing right there.
	var other := _another(5)
	var field := w.spawn_building(&"building.field", 1, Vector2i(4, 4),
			SimBuilding.Phase.FOUNDATION, true)
	w.queue_command(BuildCommand.new(1, [villager.id], field.id))
	assert_true(_run_until(func(): return field.is_complete(), 600) > 0)
	assert_eq(villager.task, SimUnit.Task.GATHER, "farming its own crop")
	assert_eq(villager.gather_node_id, field.id)
	assert_eq(other.build_progress, 0, "and it did not wander off to the house")


## A world with one villager and four foundations, two of them equidistant from the
## first. Built by ONE function so both copies spawn in the same order and therefore
## carry the same entity ids -- doing it inline twice is how the first version of the
## test below diverged on tick 1 and blamed the sim.
func _a_building_site() -> SimWorld:
	var world := SimWorld.new()
	world.setup(MatchConfig.debug_single_player())
	var first := world.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, true)
	var worker := world.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	for dx in [5, -5, 8]:
		world.spawn_building(&"building.house", 1, Vector2i(10 + dx, 10),
				SimBuilding.Phase.FOUNDATION, true)
	world.queue_command(BuildCommand.new(1, [worker.id], first.id))
	return world


func test_two_worlds_carry_on_to_the_same_next_foundation() -> void:
	# The re-scan picks one of several candidates, so it is a desync risk in exactly
	# the way `GatherSystem._retarget_near` and `CombatSystem._reacquire` are. The two
	# foundations five tiles either side of the first are the case where a "first one
	# found" walk over `entities` would be free to disagree -- they tie on distance,
	# so only the id tiebreak separates them.
	var a := _a_building_site()
	var b := _a_building_site()
	for i in range(900):
		a.step()
		b.step()
		assert_eq(a.state_hash(), b.state_hash(), "diverged on tick %d" % (i + 1))


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_worlds_given_the_same_build_order_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	var other_house := other.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, true)
	var other_villager := other.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))

	_order_build()
	other.queue_command(BuildCommand.new(1, [other_villager.id], other_house.id))

	for i in range(300):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
