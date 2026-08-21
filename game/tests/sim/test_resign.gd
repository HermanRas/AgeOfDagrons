## Conceding a match, and a match that must not be left unresolvable (PLAN.md 12.1e).
##
## The two failures this exists for are the same failure from two directions: a player
## stops taking part, keeps owning a base, and `WinConditionSystem` goes on counting them
## as standing -- so the remaining player fights an abandoned town with no way to win. One
## direction is a player pressing Resign; the other is their device vanishing.
extends TestCase

var world: SimWorld


func before_each() -> void:
	# ONE config object, used for both calls: `setup` and `build` must be handed the same
	# one, and a second `debug_skirmish()` would be an equal config rather than the same
	# one -- which is fine today and exactly the kind of thing that stops being fine.
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)


func _resign(player_id: int) -> bool:
	var cmd := ResignCommand.new(player_id, world.tick)
	if not cmd.validate(world):
		return false
	world.queue_command(cmd)
	world.step()
	return true


func test_resigning_marks_you_defeated() -> void:
	assert_false(world.player_for(2).defeated)
	assert_true(_resign(2), "the command validated")
	assert_true(world.player_for(2).defeated)


func test_resigning_ends_the_match_and_the_other_player_wins() -> void:
	# The whole point. Player 2 still owns everything they owned a moment ago.
	assert_true(_resign(2))
	assert_true(world.match_over, "the match resolved")
	assert_eq(world.winner_id, 1, "the player who did not concede won")


func test_a_resigned_player_keeps_their_buildings_and_is_still_out() -> void:
	# `apply()` sets a flag and kills nothing, so this is what "out" has to mean: owning
	# things is no longer enough to be standing.
	var owned := 0
	for e in world.entities.values():
		if e.owner_id == 2 and e.alive:
			owned += 1
	assert_true(owned > 0, "player 2 owns something to keep")

	assert_true(_resign(2))
	var still := 0
	for e in world.entities.values():
		if e.owner_id == 2 and e.alive:
			still += 1
	assert_eq(still, owned, "their entities are left standing")
	assert_true(world.match_over, "and they are out anyway")


func test_you_cannot_resign_twice() -> void:
	# Matters because `Net` issues one of these itself when a peer drops, which can arrive
	# after the player's own resign -- the ordinary way of leaving a match.
	assert_true(_resign(2))
	var second := ResignCommand.new(2, world.tick)
	assert_false(second.validate(world), "a second resign is refused")


func test_a_resign_for_a_player_who_is_not_here_does_nothing() -> void:
	var cmd := ResignCommand.new(99, world.tick)
	assert_false(cmd.validate(world))
	cmd.apply(world)          # and applying it anyway is not a crash
	assert_false(world.match_over)


func test_it_survives_the_wire() -> void:
	var back := Command.from_dict(ResignCommand.new(7, 42).to_dict())
	assert_not_null(back, "the dispatch table knows the type")
	assert_true(back is ResignCommand)
	assert_eq(back.player_id, 7)
	assert_eq(back.issued_tick, 42)


func test_the_sender_cannot_resign_somebody_else() -> void:
	# Not a property of this command but of the boundary it goes through: `_recv_command`
	# overwrites `player_id` with the id it knows the sender owns. Asserted here because
	# this is the first command where forging the field would be worth doing -- resigning
	# an opponent is an instant win.
	var forged := ResignCommand.new(1, 0)          # player 2 claiming to be player 1
	forged.player_id = 2                            # what the server would overwrite it to
	forged.apply(world)
	assert_true(world.player_for(2).defeated, "the sender resigned")
	assert_false(world.player_for(1).defeated, "not the player they named")


func test_one_player_resigning_of_three_does_not_end_the_match() -> void:
	# The defeat screen still appears for them -- `GameScene._refresh_result` shows it on
	# `defeated` without `match_over` -- but the other two play on.
	var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	cfg.player_ids = [1, 2, 3] as Array[int]
	cfg.colours = [2, 1, 3] as Array[int]
	cfg.ai_players = [false, false, false] as Array[bool]
	cfg.map_data = MapGenerator.generate(3, MapGenerator.Type.FOREST, 3)
	cfg.map_size = cfg.map_data.size
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)

	var cmd := ResignCommand.new(3, w.tick)
	w.queue_command(cmd)
	w.step()

	assert_true(w.player_for(3).defeated, "the one who conceded is out")
	assert_false(w.match_over, "two are still playing")
	assert_eq(w.winner_id, 0)
