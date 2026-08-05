## Phase 0.7 layer 3: the same MatchConfig + command log run twice must hash
## identically, and an actually different run must hash differently -- both
## halves matter, since a hash that never changes would pass every
## regression test for the wrong reason (PLAN.md 7.7).
extends TestCase

func _run_scripted_match() -> SimWorld:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(8, 2)))
	for i in 40:
		w.step()
	return w


func test_identical_runs_produce_identical_hashes() -> void:
	var a := _run_scripted_match()
	var b := _run_scripted_match()
	assert_eq(a.state_hash(), b.state_hash())


func test_a_diverged_run_produces_a_different_hash() -> void:
	var a := _run_scripted_match()

	var b := SimWorld.new()
	b.setup(MatchConfig.debug_single_player())
	var v := b.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	b.queue_command(MoveCommand.new(1, [v.id], Vector2i(2, 8)))          # different target
	for i in 40:
		b.step()

	assert_ne(a.state_hash(), b.state_hash())


func test_hash_is_sensitive_to_tick_alone() -> void:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	var before := w.state_hash()
	w.step()
	assert_ne(before, w.state_hash(), "tick is part of the hashed state")
