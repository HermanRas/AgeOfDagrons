## PLAN.md 4.6/4.7 (unit death, corpse, fade) and 5.5/5.6 (building destruction,
## rubble). MVP has no combat yet, so DebugDestroyCommand is what brings hp to 0
## in every test here -- exactly the path a debug button on the client uses.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


func _destroy(id: int, owner: int = 1) -> void:
	w.queue_command(DebugDestroyCommand.new(owner, id))
	w.step()


# ── units (4.6, 4.7) ─────────────────────────────────────────────────────────

func test_debug_destroy_kills_a_unit() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	_destroy(v.id)
	assert_false(v.alive)
	assert_eq(v.hp, 0)


func test_a_dead_unit_drops_its_cargo() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	v.carry_kind = &"wood"
	v.carry_amount = 7
	_destroy(v.id)
	assert_eq(v.carry_amount, 0)
	assert_eq(v.carry_kind, &"")


## Killed in mid-stride, a villager used to WALK ON to wherever it had been sent
## and only stop on arriving (project owner, 2026-08-20). `MovementSystem` drives
## anything with a waypoint left, and death cleared the unit but not its orders.
func test_a_unit_killed_in_mid_stride_stops_where_it_fell() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(25, 5)))

	# Far enough to be genuinely under way, nowhere near arriving.
	for i in range(12):
		w.step()
	var setting_off := v.tile()
	assert_true(setting_off.x > 5, "it was actually walking when it died")
	assert_true(setting_off.x < 25, "and nowhere near the far end yet")

	_destroy(v.id)
	var fell := v.pos
	assert_false(v.alive)

	for i in range(60):
		w.step()
	assert_eq(v.pos, fell, "the corpse stayed where it fell rather than walking on")
	assert_false(v.has_waypoint(), "and its route was cancelled, not merely ignored")


func test_a_dead_unit_plays_the_die_anim_then_decays_before_despawning() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	_destroy(v.id)
	assert_eq(v.anim, &"die")

	for i in range(SimUnit.CORPSE_TOTAL_TICKS - SimUnit.CORPSE_FADE_TICKS - 1):
		w.step()
	assert_not_null(w.get_entity(v.id), "still a corpse, not yet despawned")
	assert_eq(v.anim, &"die")

	w.step()          # crosses into the fade window
	assert_eq(v.anim, &"decay")

	for i in range(SimUnit.CORPSE_FADE_TICKS):
		w.step()
	assert_null(w.get_entity(v.id), "despawned once the corpse timer ran out")


func test_a_dead_unit_is_excluded_from_radius_queries() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	_destroy(v.id)
	assert_eq(w.entities_in_radius(Vector2i(5, 5), 1).size(), 0)


func test_debug_destroy_rejected_for_non_owner() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.queue_command(DebugDestroyCommand.new(2, v.id))
	w.step()
	assert_true(v.alive, "a non-owner's destroy command must not apply")


# ── buildings (5.5, 5.6) ─────────────────────────────────────────────────────

func test_debug_destroy_turns_a_building_to_rubble() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	assert_false(house.alive)
	assert_eq(house.phase, SimBuilding.Phase.DESTROYED)
	assert_not_null(w.get_entity(house.id),
			"rubble stays in the world for a while, like a unit corpse")


func test_rubble_frees_its_tiles_for_a_new_building() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	var rebuilt := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, false)
	assert_not_null(rebuilt, "the ground the rubble stands on is buildable again")


# ── rubble does not last (project owner, 2026-08-16) ─────────────────────────

func test_rubble_clears_itself_after_a_minute() -> void:
	# It used to stay forever, which silted a razed settlement up with debris
	# nothing could remove, sitting on ground that was already rebuilt.
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	assert_eq(house.rubble_ticks_left, SimBuilding.RUBBLE_TOTAL_TICKS,
			"the timer starts on the tick it falls")

	for i in range(SimBuilding.RUBBLE_TOTAL_TICKS - 1):
		w.step()
	assert_not_null(w.get_entity(house.id), "still there a tick short of the minute")
	w.step()
	assert_null(w.get_entity(house.id), "and gone on the tick the minute is up")


func test_the_view_is_told_the_rubble_went() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	for i in range(SimBuilding.RUBBLE_TOTAL_TICKS):
		w.step()
	assert_true(w.removed_this_tick.has(house.id),
			"removed[] is how the pooled EntityView is freed (7.2)")


func test_the_rubble_timer_rides_the_snapshot_so_the_view_can_fade_it() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	var snap := SnapshotSystem.build(w, 1)
	for entry in snap["updated"]:
		if int((entry as Dictionary)["id"]) == house.id:
			assert_eq(int((entry as Dictionary)["rubble_ticks_left"]),
					SimBuilding.RUBBLE_TOTAL_TICKS)
			return
	assert_true(false, "the rubble is missing from the snapshot entirely")


func test_a_living_building_carries_the_not_destroyed_sentinel() -> void:
	# -1, not 0: 0 would be indistinguishable from "the minute just ran out" and
	# the view would draw a healthy building at zero alpha.
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_eq(house.rubble_ticks_left, -1)


# ── building over rubble clears it early ─────────────────────────────────────

func test_building_over_rubble_clears_it_immediately() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var ruin := house.id
	_destroy(ruin)
	assert_not_null(w.get_entity(ruin), "still standing as rubble")

	w.spawn_building(&"building.house", 1, Vector2i(10, 10), SimBuilding.Phase.FOUNDATION)
	assert_null(w.get_entity(ruin), "the new foundation took the wreckage with it")


func test_a_partial_overlap_takes_the_whole_ruin() -> void:
	# ANY overlap, not an exact match: half-cleared wreckage sticking out from
	# under a new building would look worse than leaving all of it.
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var ruin := tc.id
	_destroy(ruin)

	# A 4x4 house on one corner of the fallen 10x10 town centre.
	w.spawn_building(&"building.house", 1, Vector2i(9, 9), SimBuilding.Phase.FOUNDATION)
	assert_null(w.get_entity(ruin))


func test_rubble_somewhere_else_is_left_alone() -> void:
	var far := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(far.id)
	w.spawn_building(&"building.house", 1, Vector2i(10, 10), SimBuilding.Phase.FOUNDATION)
	assert_not_null(w.get_entity(far.id), "only what is built OVER is cleared")


func test_two_worlds_clearing_rubble_stay_identical() -> void:
	# Clearing reaches `removed[]`, so two clients doing it in a different order
	# would disagree about the wire format for no reason.
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	for world: SimWorld in [w, other]:
		var a: SimBuilding = world.spawn_building(&"building.house", 1, Vector2i(10, 10),
				SimBuilding.Phase.COMPLETE, true)
		var b: SimBuilding = world.spawn_building(&"building.house", 1, Vector2i(14, 10),
				SimBuilding.Phase.COMPLETE, true)
		world.queue_command(DebugDestroyCommand.new(1, a.id))
		world.queue_command(DebugDestroyCommand.new(1, b.id))
	for i in range(3):
		w.step()
		other.step()
	for world: SimWorld in [w, other]:
		world.spawn_building(&"building.town_center", 1, Vector2i(9, 9),
				SimBuilding.Phase.FOUNDATION, true)
	assert_eq(w.state_hash(), other.state_hash())


func test_rubble_is_unselectable_via_nearest_drop_off() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	assert_null(w.nearest_drop_off(1, &"wood", Vector2i(10, 10)))


func test_destroyed_building_stops_training_its_queue() -> void:
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	tc.enqueue_training(&"unit.villager", 5, {})
	_destroy(tc.id)
	var before := w.entities.size()
	for i in range(20):
		w.step()
	assert_eq(w.entities.size(), before, "no villager trained out of rubble")


# ── determinism (7.1) ────────────────────────────────────────────────────────

func test_two_worlds_given_the_same_destroy_order_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	var other_v := other.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))

	w.queue_command(DebugDestroyCommand.new(1, v.id))
	other.queue_command(DebugDestroyCommand.new(1, other_v.id))

	for i in range(SimUnit.CORPSE_TOTAL_TICKS + 5):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
