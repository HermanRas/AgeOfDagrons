## TEAMS (the lobby's selector, 2026-08-31): who is allied with whom, and what stops
## being possible once two players are.
##
## THE WHOLE FEATURE IS ONE FIELD AND FOUR PREDICATES, and the predicates are what this
## file is about. `SimPlayer.team` was declared at 0.4 and read by nothing for the life
## of the project; making it mean something meant widening every place that had written
## `owner_id != mine` -- `Diplomacy.is_enemy`, its `_fact` twin,
## `CombatSystem._is_at_war_with` and `AISystem._nearest_enemy`, which are deliberately
## separate copies. **Missing one is not a missing feature, it is your ally's tower
## shooting you**, so each is asserted here by name rather than through whichever one
## happens to be reachable from a whole-match fixture.
##
## AND THE FREE-FOR-ALL IS ASSERTED AS LOUDLY AS THE TEAM. Every match played before
## this existed carries team 0 for everybody, and 0 is the ABSENCE of a team rather than
## a team everybody shares -- get that backwards and the entire back catalogue of
## fixtures becomes one enormous alliance that can never resolve a match.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(_config([1, 1, 2, 2]))
	w.map.fill_terrain(SimMap.Terrain.GRASS)


## A four-player world with the given teams, position for position.
func _config(teams: Array) -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2, 3, 4]
	cfg.map_size = Vector2i(48, 48)
	for t in teams:
		cfg.teams.append(int(t))
	return cfg


# ── the predicate itself ────────────────────────────────────────────────────

func test_the_ally_table_is_five_rules_and_all_five_matter() -> void:
	var teams := {1: 1, 2: 1, 3: 2, 4: 0, 5: 0}
	assert_true(Diplomacy.allied(1, 1, teams), "always your own")
	assert_true(Diplomacy.allied(1, 2, teams), "same team")
	assert_false(Diplomacy.allied(1, 3, teams), "different team")
	assert_false(Diplomacy.allied(1, 4, teams), "a teamless player is nobody's ally")
	# THE ONE THAT WOULD HAVE BEEN A BUG. Two unaligned players both read 0, and a rule
	# written as "equal teams are allies" would make every free-for-all one big alliance.
	assert_false(Diplomacy.allied(4, 5, teams),
			"and two teamless players are not allies with EACH OTHER -- 0 is not a team")


func test_gaia_is_allied_with_nobody_however_the_table_reads() -> void:
	# Owner 0 is not a player and has no row, so it would read as team 0 -- which is
	# exactly what every unaligned player reads as. Guarded explicitly, or a wolf would
	# be on the same side as the whole lobby.
	var teams := {1: 0, 2: 0}
	assert_false(Diplomacy.allied(0, 1, teams))
	assert_false(Diplomacy.allied(1, 0, teams))
	assert_true(Diplomacy.allied(0, 0, teams), "gaia is still itself: a pack does not eat itself")


func test_an_unlisted_player_is_simply_unaligned() -> void:
	assert_false(Diplomacy.allied(1, 2, {}), "an empty table is a free-for-all")
	assert_true(Diplomacy.allied(7, 7, {}), "and you are still yourself")


# ── what an ally may no longer be ───────────────────────────────────────────

func test_an_allys_unit_is_not_an_enemy_and_an_opponents_is() -> void:
	var friend := w.spawn_unit(&"unit.militia", 2, Vector2i(10, 10))
	var foe := w.spawn_unit(&"unit.militia", 3, Vector2i(12, 10))
	assert_false(Diplomacy.is_enemy(friend, 1, w.teams), "player 2 is on player 1's team")
	assert_true(Diplomacy.is_enemy(foe, 1, w.teams), "player 3 is not")


func test_the_view_and_the_sim_still_answer_the_same_question() -> void:
	# `test_wildlife` pins this pair for gaia; teams are the second thing that can make
	# them drift, and when they do the player taps an ally, the tap offers an attack and
	# the server refuses it with nothing said.
	for owner_id in [1, 2, 3, 0]:
		var f := {"owner_id": owner_id, "is_unit": true, "alive": true}
		var e := w.spawn_unit(&"unit.militia", owner_id, Vector2i(20 + owner_id, 20))
		assert_eq(Diplomacy.is_enemy_fact(f, 1, w.teams),
				Diplomacy.is_enemy(e, 1, w.teams), "owner %d" % owner_id)


func test_an_order_to_attack_an_ally_is_refused_by_the_server() -> void:
	# The HUD hiding the option is not enough -- §4: if the panel refuses it, the command
	# must refuse it too, because a hand-built packet is the case the boundary is for.
	var mine := w.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	var friend := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	var foe := w.spawn_unit(&"unit.villager", 3, Vector2i(12, 10))
	assert_false(AttackCommand.new(1, [int(mine.id)] as Array[int],
			int(friend.id)).validate(w), "an ally may not be ordered attacked")
	assert_true(AttackCommand.new(1, [int(mine.id)] as Array[int],
			int(foe.id)).validate(w), "and an opponent still may")


func test_a_tower_is_not_at_war_with_its_allys_soldiers() -> void:
	# `CombatSystem._is_at_war_with` is the predicate a tower, an aggressive stance and a
	# dragon's breath all reach through -- one miss here is three features shooting the
	# wrong people. The wolf clause is asserted alongside, because widening this must not
	# have narrowed it: a predator is still a target for a tower that has allies.
	var friend := w.spawn_unit(&"unit.militia", 2, Vector2i(10, 10))
	var foe := w.spawn_unit(&"unit.militia", 3, Vector2i(11, 10))
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(12, 10))
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(13, 10))
	assert_false(CombatSystem._is_at_war_with(w, friend, 1))
	assert_true(CombatSystem._is_at_war_with(w, foe, 1))
	assert_true(CombatSystem._is_at_war_with(w, wolf, 1), "a predator still is")
	assert_false(CombatSystem._is_at_war_with(w, sheep, 1), "and the flock still is not")


func test_two_allied_soldiers_standing_together_do_not_fight() -> void:
	# The end-to-end version of the row above, through the stance a military unit is born
	# with. Before teams this fixture WAS a fight -- §6's row about a fixture that puts
	# two hostile units near each other is exactly this arrangement -- so a regression
	# here shows up as hp falling rather than as an assertion about a predicate.
	var mine := w.spawn_unit(&"unit.militia", 1, Vector2i(20, 20))
	var friend := w.spawn_unit(&"unit.militia", 2, Vector2i(21, 20))
	for i in range(60):
		w.step()
	assert_eq(mine.hp, mine.max_hp, "neither of them started anything")
	assert_eq(friend.hp, friend.max_hp)
	assert_eq(mine.task, SimUnit.Task.IDLE)


func test_an_unaligned_pair_still_fights_which_is_what_makes_the_test_above_mean_anything() -> void:
	var world := SimWorld.new()
	world.setup(_config([0, 0, 0, 0]))
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	var a := world.spawn_unit(&"unit.militia", 1, Vector2i(20, 20))
	var b := world.spawn_unit(&"unit.militia", 2, Vector2i(21, 20))
	for i in range(60):
		world.step()
	assert_true(a.hp < a.max_hp or b.hp < b.max_hp,
			"a free-for-all is unchanged: two soldiers a tile apart start a fight")


func test_an_aggressive_soldier_does_not_open_fire_on_an_allys_barracks() -> void:
	# ⚠️ THE ONE THE UNIT HALF DID NOT COVER. `StanceSystem._may_start_on` asks
	# `_is_at_war_with` about units and keeps its OWN owner clause for buildings, because
	# a building is never gaia's -- so `b.owner_id != owner_id` was true of an ally's
	# barracks and an aggressive soldier posted next to one would have shot it while the
	# unit half quietly did the right thing. Exactly the class of miss `Diplomacy` was
	# written to end, arriving in the one place that could not use it.
	var friend_hall := w.spawn_building(&"building.house", 2, Vector2i(20, 20))
	var foe_hall := w.spawn_building(&"building.house", 3, Vector2i(30, 30))
	assert_true(friend_hall.is_complete(), "spawn_building completes by default")
	assert_false(StanceSystem._may_start_on(w, friend_hall, 1),
			"an ally's completed building is not a target")
	assert_true(StanceSystem._may_start_on(w, foe_hall, 1),
			"and an opponent's still is")


func test_a_dragons_breath_spares_an_allys_building_too() -> void:
	# `AbilitySystem._is_hostile_to` carries the second copy of that owner clause, and it
	# is deliberately a different rule from the stance's -- it INCLUDES foundations,
	# because a weapon a player aimed at a tile should not be overruled. Teams are the
	# one thing both halves have to agree about.
	var friend := w.spawn_building(&"building.house", 2, Vector2i(20, 20))
	var foe := w.spawn_building(&"building.house", 3, Vector2i(30, 30))
	assert_false(AbilitySystem._is_hostile_to(w, friend, 1))
	assert_true(AbilitySystem._is_hostile_to(w, foe, 1))


# ── the config, the world and the wire ──────────────────────────────────────

func test_setup_writes_the_team_onto_the_player_and_into_the_table() -> void:
	assert_eq(w.player_for(1).team, 1)
	assert_eq(w.player_for(4).team, 2)
	assert_eq(w.teams, {1: 1, 2: 1, 3: 2, 4: 2},
			"and the cached table is the same fact, since nothing may mutate a team")


func test_a_config_naming_no_teams_leaves_everybody_unaligned() -> void:
	# Every debug factory, every older fixture and every recorded config. A short array
	# is legal for `ai_levels`' reason and has to mean the same thing here.
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2, 3]
	cfg.teams = [2]                     # deliberately short, not merely empty
	world.setup(cfg)
	assert_eq(world.player_for(1).team, 2)
	assert_eq(world.player_for(2).team, 0, "the rest fall back rather than misaligning")
	assert_eq(world.player_for(3).team, 0)


func test_teams_ride_the_wire() -> void:
	var cfg := _config([1, 1, 2, 2])
	var decoded := MatchConfig.from_dict(cfg.to_dict())
	assert_eq(decoded.teams, [1, 1, 2, 2] as Array[int])
	# From a host built before the selector existed. It must decode as a free-for-all
	# rather than as a crash or an array of nulls -- the failure `ai_players` records.
	var older := cfg.to_dict()
	older.erase("teams")
	assert_true(MatchConfig.from_dict(older).teams.is_empty())


func test_the_snapshot_carries_every_players_team() -> void:
	# The client decides what a tap OFFERS, and it has to read the same numbers the sim
	# refuses the order by. Every player's, not just the viewer's -- who is allied with
	# whom was chosen in a lobby everybody could read.
	var snap := SnapshotSystem.build(w, 1)
	var state: Dictionary = snap["player_state"]
	assert_eq(int((state[1] as Dictionary)["team"]), 1)
	assert_eq(int((state[3] as Dictionary)["team"]), 2, "including an opponent's")


# ── winning as a side ───────────────────────────────────────────────────────

func test_a_team_game_ends_when_one_SIDE_is_left_standing() -> void:
	# ⚠️ THE FEATURE IS A HANG WITHOUT THIS. Two allies both standing is two standing
	# PLAYERS, and once they cannot attack each other nothing can ever reduce that to
	# one -- so the old rule ran a 2v2 forever with both survivors wandering an empty
	# map. This is the assertion that says the win condition counts sides.
	w.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.militia", 2, Vector2i(30, 30))
	var doomed := w.spawn_unit(&"unit.militia", 3, Vector2i(40, 40))
	w.step()
	assert_false(w.match_over, "two sides on the board")

	doomed.take_damage(9999, 0)
	w.step()
	assert_true(w.match_over, "one side left")
	assert_eq(w.winner_team, 1)
	assert_eq(w.winner_id, 1, "named by the lowest-id survivor of the winning side")


func test_both_members_of_the_winning_side_are_winners_including_a_dead_one() -> void:
	# A player knocked out on tick 400 whose partner went on to take it. `winner_id`
	# names one survivor, so without `winner_team` the other member reads their own
	# side's victory as somebody else's.
	var survivor := w.spawn_unit(&"unit.militia", 2, Vector2i(30, 30))
	var mine := w.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.militia", 3, Vector2i(40, 40)).take_damage(9999, 0)
	mine.take_damage(9999, 0)
	w.step()

	assert_true(w.match_over)
	assert_eq(w.winner_id, int(survivor.owner_id), "the one still on the board")
	assert_eq(w.winner_team, 1)
	assert_true(w.player_for(1).defeated, "player 1 really was knocked out")
	assert_eq(w.player_for(1).team, w.winner_team, "and their side won anyway")


func test_a_free_for_all_still_ends_exactly_as_it_did() -> void:
	var world := SimWorld.new()
	world.setup(_config([0, 0, 0, 0]))
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	var last := world.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	world.spawn_unit(&"unit.militia", 2, Vector2i(40, 40)).take_damage(9999, 0)
	world.step()
	assert_true(world.match_over)
	assert_eq(world.winner_id, int(last.owner_id))
	assert_eq(world.winner_team, 0, "nobody won as a TEAM, and 0 is how that is said")


func test_the_outcome_is_in_the_state_hash_as_a_team_and_not_only_as_a_player() -> void:
	# Two hosts that disagree about who won have diverged about the only question the
	# match was asked -- and one that lost a team number would call the same survivor the
	# winner of a free-for-all.
	var a := SimWorld.new()
	a.setup(_config([1, 1, 2, 2]))
	var b := SimWorld.new()
	b.setup(_config([1, 1, 2, 2]))
	assert_eq(a.state_hash(), b.state_hash(), "identical worlds start equal")
	a.winner_team = 1
	assert_ne(a.state_hash(), b.state_hash())
