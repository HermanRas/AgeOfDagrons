## PLAN.md 11.1: the match ends, somebody wins, and the losers are told.
##
## Only Last Man Standing is implemented (`MatchConfig.Mode`), and the last two
## tests here are what pin the other two modes as INERT rather than half-built --
## a placeholder that quietly decided matches would be worse than no mode at all.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


func _player(id: int) -> SimPlayer:
	return w.player_for(id)


## One unit each, so both players are genuinely in the game before anything is
## taken away from them.
func _both_armed() -> Array[SimUnit]:
	return [w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10)),
			w.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))]


# ── last man standing ───────────────────────────────────────────────────────

func test_the_default_mode_is_last_man_standing() -> void:
	# The one mode that is built is the one an unconfigured match runs.
	assert_eq(w.mode, MatchConfig.Mode.LAST_MAN_STANDING)
	assert_eq(MatchConfig.new().mode, MatchConfig.Mode.LAST_MAN_STANDING)


func test_a_match_in_progress_is_not_over_and_nobody_is_defeated() -> void:
	_both_armed()
	w.step()
	assert_false(w.match_over)
	assert_eq(w.winner_id, 0)
	assert_false(_player(1).defeated)
	assert_false(_player(2).defeated)


func test_losing_everything_eliminates_you_and_the_survivor_wins() -> void:
	var units := _both_armed()
	w.step()
	assert_false(w.match_over, "still a fight at this point")

	units[1].alive = false
	w.step()

	assert_true(_player(2).defeated)
	assert_false(_player(1).defeated)
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)


func test_a_corpse_does_not_keep_a_player_in_the_game() -> void:
	# A dead unit stays in `entities` for ten seconds so it can be drawn (4.7). A
	# player whose last villager is lying on the ground has lost, and counting the
	# corpse would postpone the result by exactly that long -- the same `alive`
	# filter PopulationSystem counts population by.
	var units := _both_armed()
	units[1].alive = false
	w.step()
	assert_true(w.entities.has(units[1].id), "still there to be rendered")
	assert_true(w.match_over, "but not still in the match")


func test_rubble_does_not_keep_a_player_in_the_game() -> void:
	# The same for buildings, which linger as rubble for a minute (5.5).
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	var house := w.spawn_building(&"building.house", 2, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_false(w.match_over)

	house.alive = false
	w.step()
	assert_eq(house.phase, SimBuilding.Phase.DESTROYED, "DeathSystem got to it first")
	assert_true(w.entities.has(house.id), "the wreckage is still drawn")
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)


func test_a_foundation_keeps_a_player_in_the_game() -> void:
	# Deliberately unlike the population cap, which counts COMPLETE buildings only.
	# What a building PROVIDES and whether its owner is still playing are different
	# questions: a foundation holds ground and can still be raised.
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.spawn_building(&"building.house", 2, Vector2i(30, 30),
			SimBuilding.Phase.FOUNDATION, true)
	w.step()
	assert_false(_player(2).defeated, "pegged out is not eliminated")
	assert_false(w.match_over)


func test_a_solo_sandbox_is_never_decided() -> void:
	# "Last man standing" is trivially true of a player with no opponents, and
	# declaring victory on tick 1 of the single-player debug config would be
	# technically correct and useless.
	var solo := SimWorld.new()
	solo.setup(MatchConfig.debug_single_player())
	solo.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	for i in range(5):
		solo.step()
	assert_false(solo.match_over)
	assert_false(solo.player_for(1).defeated)


func test_an_empty_world_is_undecided_rather_than_drawn() -> void:
	# setup() allocates the grid and MapGen fills it afterwards, so an empty world
	# is one that has not been stood up -- which is what most of the sim suite runs
	# on. Read literally it is everyone eliminated on tick 1, and `match_over`
	# latches, so that verdict would stick for the whole run.
	for i in range(5):
		w.step()
	assert_false(w.match_over)
	assert_false(_player(1).defeated)
	assert_false(_player(2).defeated)


func test_mutual_annihilation_ends_the_match_with_no_winner() -> void:
	# Barely reachable in play, and the reason `match_over` and `winner_id` are two
	# fields: a match flagged over with a winner nobody can name would be worse.
	# It works because the corpses are still in `entities` on the tick it happens.
	var units := _both_armed()
	units[0].alive = false
	units[1].alive = false
	w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 0, "nobody to name")
	assert_true(_player(1).defeated)
	assert_true(_player(2).defeated)


func test_the_result_is_frozen_once_it_is_decided() -> void:
	# Corpses decay and rubble clears for a minute after a match ends, and a system
	# that kept re-evaluating would re-derive its answer from a board that is still
	# changing. It also means a late spawn cannot un-defeat anybody.
	var units := _both_armed()
	units[1].alive = false
	w.step()
	assert_eq(w.winner_id, 1)

	w.spawn_unit(&"unit.villager", 2, Vector2i(31, 31))
	for i in range(10):
		w.step()
	assert_true(w.match_over, "still over")
	assert_eq(w.winner_id, 1, "and still won by the same player")
	assert_true(_player(2).defeated, "elimination does not come undone")


func test_a_player_is_eliminated_the_tick_their_last_thing_falls() -> void:
	# WinConditionSystem runs after DeathSystem, so a loss lands on the tick it
	# happens rather than one tick later -- the ordering PLAN.md 5.1 specifies.
	var units := _both_armed()
	units[1].alive = false
	var before := w.tick
	w.step()
	assert_eq(w.tick, before + 1, "exactly one tick passed")
	assert_true(w.match_over)


# ── the real test map (MatchConfig.debug_skirmish + MapGen) ─────────────────

func test_the_debug_map_is_a_match_that_can_be_won() -> void:
	# THE ONE THAT MATTERS FOR PLAYING IT. Everything above is built on hand-placed
	# entities; this is the actual config `Net.host_solo()` runs, with the actual
	# starting conditions MapGen lays down, and it is what makes 11.1 something you
	# can go and do rather than something the suite believes.
	#
	# The opponent owns DEBUG_ENEMY_SQUAD -- an archer and a knight -- and nothing
	# else, so killing both of them is the whole victory condition on this map.
	var real := SimWorld.new()
	real.setup(MatchConfig.debug_skirmish())
	MapGen.build_debug_map(real)
	real.step()

	assert_false(real.match_over, "a fresh match is not already decided")
	assert_false(real.player_for(1).defeated)
	assert_false(real.player_for(2).defeated)

	var enemies := 0
	for e in real.entities.values():
		if e is SimUnit and e.owner_id == 2:
			enemies += 1
			(e as SimUnit).alive = false
	assert_eq(enemies, MapGen.DEBUG_ENEMY_SQUAD.size(), "the squad is who we just killed")

	real.step()
	assert_true(real.match_over)
	assert_eq(real.winner_id, 1)
	assert_true(real.player_for(2).defeated)


func test_losing_the_town_centre_alone_does_not_lose_the_debug_map() -> void:
	# Conquest is EVERYTHING, not the town centre -- five villagers with an axe are
	# still a player in the game, and they can rebuild. A rule that ended the match
	# with the town centre would be Regicide wearing conquest's name.
	var real := SimWorld.new()
	real.setup(MatchConfig.debug_skirmish())
	MapGen.build_debug_map(real)

	for e in real.entities.values():
		if e is SimBuilding and e.owner_id == 1:
			(e as SimBuilding).alive = false
	real.step()

	assert_false(real.player_for(1).defeated, "the villagers are still theirs")
	assert_false(real.match_over)


# ── it reaches the client ───────────────────────────────────────────────────

func test_the_outcome_rides_the_snapshot() -> void:
	# The result screen is a READER of sim state (GameScene._refresh_result); a
	# client that worked out its own result could show victory over a match the host
	# thinks is still running.
	var units := _both_armed()
	units[1].alive = false
	w.step()

	var snap := SnapshotSystem.build(w, 1)
	assert_true(bool(snap["match_over"]))
	assert_eq(int(snap["winner_id"]), 1)
	assert_eq(int(snap["mode"]), int(MatchConfig.Mode.LAST_MAN_STANDING))
	assert_false(bool(snap["player_state"][1]["defeated"]))
	assert_true(bool(snap["player_state"][2]["defeated"]))


func test_an_undecided_match_says_so_on_the_wire() -> void:
	_both_armed()
	w.step()
	var snap := SnapshotSystem.build(w, 1)
	assert_false(bool(snap["match_over"]))
	assert_eq(int(snap["winner_id"]), 0)


func test_the_outcome_is_part_of_the_state_hash() -> void:
	# Two clients that disagree about who won have diverged on the only question the
	# match was asked -- and `defeated` is irreversible, so without it in the hash
	# they would agree on every tick until one of them declared a winner.
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	_both_armed()
	other.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	other.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))
	w.step()
	other.step()
	assert_eq(w.state_hash(), other.state_hash(), "identical worlds agree")

	# Same board, one of them decided. The only difference is the outcome itself.
	w.match_over = true
	w.winner_id = 1
	assert_ne(w.state_hash(), other.state_hash(), "the outcome is hashed")

	w.match_over = false
	w.winner_id = 0
	_player(2).defeated = true
	assert_ne(w.state_hash(), other.state_hash(), "and so is elimination on its own")


# ── the two placeholders (11.2) ─────────────────────────────────────────────

func test_trophy_mode_decides_nothing_yet() -> void:
	# It needs a `unit.dragon_baby` def and a MapGen that hands every player one
	# (PLAN.md 13.2). Running the four-line rule today would defeat every player on
	# tick 1, since nobody has a trophy to lose -- so it runs nothing, and this is
	# what says so out loud.
	w.mode = MatchConfig.Mode.TROPHY
	_both_armed()[1].alive = false
	for i in range(10):
		w.step()
	assert_false(w.match_over, "declared but not implemented")
	assert_false(_player(2).defeated, "and it eliminates nobody either")


func test_king_of_the_hill_decides_nothing_yet() -> void:
	# It needs the zone's position as map data, a per-player score, and the minimap
	# ring. Same reasoning as Trophy above.
	w.mode = MatchConfig.Mode.KING_OF_THE_HILL
	_both_armed()[1].alive = false
	for i in range(10):
		w.step()
	assert_false(w.match_over)
	assert_false(_player(2).defeated)


func test_the_declared_modes_are_the_three_that_were_asked_for() -> void:
	# The lobby (1.6/11.3) shows this list; the sim only acts on the first.
	assert_eq(MatchConfig.Mode.keys(),
			["LAST_MAN_STANDING", "TROPHY", "KING_OF_THE_HILL"])
	assert_eq(WinConditionSystem.KOTH_TARGET_SCORE, 1000)
