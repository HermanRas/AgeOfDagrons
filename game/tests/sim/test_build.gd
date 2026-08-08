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
	assert_true(villager.is_idle(), "retired once there was nothing left to build")


func test_the_foundation_shows_progress_partway_through() -> void:
	_order_build()
	_run_until(func(): return house.build_progress > 0, 200)
	assert_true(house.build_progress < house.build_total, "still under way, not already done")
	assert_eq(house.phase, SimBuilding.Phase.UNDER_CONSTRUCTION)


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
