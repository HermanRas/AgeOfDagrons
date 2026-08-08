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
	assert_not_null(w.get_entity(house.id), "rubble stays in the world, unlike a unit corpse")


func test_rubble_frees_its_tiles_for_a_new_building() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_destroy(house.id)
	var rebuilt := w.spawn_building(&"building.house", 1, Vector2i(10, 10),
			SimBuilding.Phase.FOUNDATION, false)
	assert_not_null(rebuilt, "the ground the rubble stands on is buildable again")


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
