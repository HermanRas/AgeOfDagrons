## Phase 0.5: proves SimWorld/SimUnit/Command/SpatialHash work headless, with
## no scene and no view (PLAN.md 7.7). This is the literal example from
## PLAN.md 7.7 plus the ownership/rejection and query paths it implies.
extends TestCase

const _SimClockScript := preload("res://src/autoload/sim_clock.gd")

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


# ── the lobby's starting age (project owner, 2026-08-30) ────────────────────

func test_every_player_opens_in_age_one_by_default() -> void:
	for p in w.players:
		assert_eq(p.age, 1)


func test_the_config_can_open_every_player_in_a_later_age() -> void:
	# ONE age for everybody, which is what the owner asked for -- a per-slot version is
	# a handicap system and wants designing rather than falling out of a dropdown.
	var cfg := MatchConfig.debug_skirmish()
	cfg.starting_age = 3
	var world := SimWorld.new()
	world.setup(cfg)
	for p in world.players:
		assert_eq(p.age, 3)


func test_a_starting_age_past_the_ladder_is_clamped_rather_than_trusted() -> void:
	# It arrives off the wire on a joined client. An age past the end would put every
	# sprite on a skin that does not exist and AgeSystem on an advance with no target.
	var cfg := MatchConfig.debug_skirmish()
	cfg.starting_age = 99
	var world := SimWorld.new()
	world.setup(cfg)
	assert_eq(world.players[0].age, GameDataRegistry.age_count())

	cfg.starting_age = 0
	var floored := SimWorld.new()
	floored.setup(cfg)
	assert_eq(floored.players[0].age, 1)


func test_spawn_unit_lands_on_requested_tile() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	assert_eq(v.tile(), Vector2i(5, 5))
	assert_eq(v.owner_id, 1)
	assert_true(v.alive)


func test_move_command_reaches_target_within_60_ticks() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(10, 5)))
	for i in 60:
		w.step()
	assert_eq(v.tile(), Vector2i(10, 5), "villager reached target in 60 ticks")
	assert_true(v.is_idle(), "task retires to IDLE once the target is reached")


func test_move_command_rejected_for_non_owner() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.queue_command(MoveCommand.new(2, [v.id], Vector2i(10, 5)))
	for i in 10:
		w.step()
	assert_eq(v.tile(), Vector2i(5, 5), "command from a non-owner must not move the unit")


func test_stop_command_halts_mid_move() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(0, 0))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(20, 0)))
	for i in 3:
		w.step()
	var halted_tile := v.tile()
	w.queue_command(StopCommand.new(1, [v.id]))
	for i in 5:
		w.step()
	assert_eq(v.tile(), halted_tile, "stop freezes the unit where it was, not at the old target")
	assert_true(v.is_idle())


func test_despawn_removes_from_lookup_and_spatial_index() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(3, 3))
	var id := v.id
	w.despawn(id)
	assert_null(w.get_entity(id))
	assert_eq(w.entities_in_radius(Vector2i(3, 3), 1).size(), 0)


func test_entities_in_radius_finds_nearby_and_excludes_far() -> void:
	var near := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	var far := w.spawn_unit(&"unit.villager", 1, Vector2i(50, 50))
	var found := w.entities_in_radius(Vector2i(10, 10), 2)
	var found_ids: Array[int] = []
	for e in found:
		found_ids.append(e.id)
	assert_true(found_ids.has(near.id))
	assert_false(found_ids.has(far.id))


## PLAN.md 7.1: the HUD's idle/total villager count is a headcount over
## snapshots, so `task` has to be IN the snapshot for the view to answer it
## without reaching into SimWorld.
func test_a_units_snapshot_carries_its_task() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	assert_eq(v.to_snapshot()["task"], SimUnit.Task.IDLE)

	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(10, 5)))
	w.step()
	assert_eq(v.to_snapshot()["task"], SimUnit.Task.MOVE)


func test_command_dict_roundtrip() -> void:
	var original := MoveCommand.new(1, [7, 8], Vector2i(4, 9))
	var rebuilt := Command.from_dict(original.to_dict())
	assert_true(rebuilt is MoveCommand)
	assert_eq((rebuilt as MoveCommand).unit_ids, [7, 8])
	assert_eq((rebuilt as MoveCommand).target_tile, Vector2i(4, 9))


func test_sim_clock_accumulates_ticks_at_10hz() -> void:
	var clock := _SimClockScript.new()
	var fired: Array[int] = []
	clock.tick_advanced.connect(func(t: int) -> void: fired.append(t))

	clock.start()
	clock.advance(0.35)          # 3 full 100ms ticks, 50ms carried over
	assert_eq(clock.tick, 3)
	assert_eq(fired, [1, 2, 3])
	clock.free()


func test_sim_clock_stop_halts_accumulation() -> void:
	var clock := _SimClockScript.new()
	clock.start()
	clock.stop()
	clock.advance(1.0)
	assert_eq(clock.tick, 0, "advance() must no-op once stopped")
	clock.free()
