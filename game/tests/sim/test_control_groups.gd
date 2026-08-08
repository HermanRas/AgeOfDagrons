## PLAN.md 10.1/10.2/10.6: control groups are sim state (SimPlayer.control_groups),
## not view state, so they survive reconnect and must be command-driven,
## validated, and hashed like everything else that changes a player's state.
extends TestCase

var w: SimWorld
var a: SimUnit
var b: SimUnit


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	a = w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	b = w.spawn_unit(&"unit.villager", 1, Vector2i(6, 5))


func test_assigning_a_group_stores_it_on_the_player() -> void:
	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id, b.id]))
	w.step()
	assert_eq(w.player_for(1).control_groups[0], [a.id, b.id])


func test_slot_must_be_in_range() -> void:
	var cmd := SetControlGroupCommand.new(1, SimPlayer.CONTROL_GROUP_COUNT, [a.id])
	assert_false(cmd.validate(w))
	var negative := SetControlGroupCommand.new(1, -1, [a.id])
	assert_false(negative.validate(w))


func test_an_empty_assignment_is_rejected_rather_than_clearing_the_slot() -> void:
	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id]))
	w.step()
	w.queue_command(SetControlGroupCommand.new(1, 0, []))
	w.step()
	assert_eq(w.player_for(1).control_groups[0], [a.id], "the empty command must not have applied")


func test_rejects_an_entity_owned_by_someone_else() -> void:
	var enemy := w.spawn_unit(&"unit.villager", 2, Vector2i(9, 9))
	var cmd := SetControlGroupCommand.new(1, 0, [a.id, enemy.id])
	assert_false(cmd.validate(w))


func test_rejects_a_dead_entity() -> void:
	w.queue_command(DebugDestroyCommand.new(1, a.id))
	w.step()
	var cmd := SetControlGroupCommand.new(1, 0, [a.id])
	assert_false(cmd.validate(w))


func test_reassigning_a_slot_replaces_its_old_members() -> void:
	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id]))
	w.step()
	w.queue_command(SetControlGroupCommand.new(1, 0, [b.id]))
	w.step()
	assert_eq(w.player_for(1).control_groups[0], [b.id])


func test_groups_are_independent_per_slot() -> void:
	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id]))
	w.queue_command(SetControlGroupCommand.new(1, 1, [b.id]))
	w.step()
	assert_eq(w.player_for(1).control_groups[0], [a.id])
	assert_eq(w.player_for(1).control_groups[1], [b.id])


func test_control_groups_ride_the_snapshot_player_state() -> void:
	w.queue_command(SetControlGroupCommand.new(1, 2, [a.id, b.id]))
	w.step()
	var snap := SnapshotSystem.build(w, 1)
	var mine: Dictionary = snap["player_state"][1]
	assert_eq(mine["control_groups"][2], [a.id, b.id])


# ── determinism (7.1) ────────────────────────────────────────────────────────

func test_two_worlds_given_the_same_assignment_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	var other_a := other.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	var other_b := other.spawn_unit(&"unit.villager", 1, Vector2i(6, 5))

	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id, b.id]))
	other.queue_command(SetControlGroupCommand.new(1, 0, [other_a.id, other_b.id]))

	for i in range(20):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))


func test_a_diverging_assignment_produces_a_different_hash() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	other.spawn_unit(&"unit.villager", 1, Vector2i(6, 5))

	w.queue_command(SetControlGroupCommand.new(1, 0, [a.id, b.id]))
	w.step()
	other.step()          # no assignment on the other world

	assert_ne(w.state_hash(), other.state_hash())
