## Phase 0.7 layer 4: a recorded MatchConfig + command log must reproduce the
## exact same run when replayed, including round-tripping through the JSON
## file format (PLAN.md 7.7) -- that file-round-trip is the actual point,
## since a recorded session on a phone has to replay on a desktop later.
extends TestCase

const _REPLAY_PATH := "user://test_replay.json"


func _record_a_match() -> Dictionary:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	var replay := Replay.new()
	replay.cfg = MatchConfig.debug_single_player()

	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(1, 1))
	var cmd := MoveCommand.new(1, [v.id], Vector2i(6, 1))
	replay.record(w.tick, cmd)
	w.queue_command(cmd)

	for i in 30:
		w.step()
		if i == 10:
			var stop := StopCommand.new(1, [v.id])
			replay.record(w.tick, stop)
			w.queue_command(stop)

	return {"world": w, "replay": replay, "unit_id": v.id}


func test_playback_reproduces_the_recorded_run() -> void:
	var original := _record_a_match()
	var original_world: SimWorld = original["world"]

	var replayed := SimWorld.new()
	replayed.setup(original["replay"].cfg)
	replayed.spawn_unit(&"unit.villager", 1, Vector2i(1, 1))          # id 1, same as the original
	original["replay"].play(replayed, 30)

	assert_eq(replayed.state_hash(), original_world.state_hash())


func test_replay_round_trips_through_a_json_file() -> void:
	var original := _record_a_match()
	var replay: Replay = original["replay"]

	var save_err := replay.save(_REPLAY_PATH)
	assert_eq(save_err, OK)

	var loaded := Replay.load_from_file(_REPLAY_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.cfg.player_ids, replay.cfg.player_ids)
	assert_eq(loaded.commands.size(), replay.commands.size())

	var replayed := SimWorld.new()
	replayed.setup(loaded.cfg)
	replayed.spawn_unit(&"unit.villager", 1, Vector2i(1, 1))
	loaded.play(replayed, 30)

	var original_world: SimWorld = original["world"]
	assert_eq(replayed.state_hash(), original_world.state_hash(),
			"a replay loaded back from disk must reproduce the original run")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(_REPLAY_PATH))
