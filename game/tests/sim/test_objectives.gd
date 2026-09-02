## Phase 15.2: `ObjectiveSystem` -- a scenario's authored win condition, evaluated in the
## sim on the server.
##
## ## WHAT THIS FILE IS REALLY GUARDING
##
## Every dangerous failure here has the same shape: **a rule that decides something it
## should not, on a world nobody has stood up yet.** `== 0` is a comparison an empty world
## PASSES, so the tests below spend as much effort on what must NOT happen as on what must.
## `WinConditionSystem._trophy()`'s header is the precedent -- *"you lose when your trophy
## dies"* on a map with no trophies defeats everybody on tick 1.
##
## The three that would each have shipped a broken campaign:
##
##   - **Conquest must not win a scenario.** Killing the Passive AI would otherwise end
##     scenario 1 with two villagers and no house.
##   - **Gaia must not be an enemy.** *"Leave the enemy nothing"* would otherwise mean
##     *shoot every deer*.
##   - **A win row must latch.** Scenario 2's two rows are never true on the same tick.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = _world([])


## A scenario world: the human as player 1, one bot as player 2, and `rows` as the
## authored objectives.
##
## The rows are built through `ObjectiveDef.from_dict` rather than by hand, so every test
## here is also a test that the LOADER accepts the shape it is given -- a fixture that
## assigned the fields directly could pass while no author could write the row.
func _world(rows: Array, teams: Array[int] = [0, 0]) -> SimWorld:
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = teams
	cfg.map_size = Vector2i(48, 48)
	cfg.mode = MatchConfig.Mode.SCENARIO
	cfg.objective_player_id = 1
	var problems: Array[String] = []
	var objectives: Array[ObjectiveDef] = []
	for r in rows:
		var o := ObjectiveDef.from_dict(r, problems)
		if o == null:
			fail("fixture row was refused by the loader: %s" % " | ".join(problems))
			continue
		objectives.append(o)
	cfg.objectives = objectives

	var world := SimWorld.new()
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	return world


## One unit each, so both players are genuinely in the game and the world is POPULATED --
## without which nothing here evaluates at all, on purpose (see `_world_is_populated`).
func _both_armed(world: SimWorld = null) -> Array[SimUnit]:
	var target: SimWorld = world if world != null else w
	return [target.spawn_unit(&"unit.villager", 1, Vector2i(10, 10)),
			target.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))]


func _villagers(world: SimWorld, owner: int, count: int) -> void:
	for i in range(count):
		world.spawn_unit(&"unit.villager", owner, Vector2i(6 + i, 6))


func _row(d: Dictionary) -> Dictionary:
	var base: Dictionary = {"owner": "self", "compare": ">=", "output": "win"}
	base.merge(d, true)
	return base


# ── the shape of a scenario win ─────────────────────────────────────────────────

func test_a_single_win_row_ends_the_match_on_the_tick_it_is_met() -> void:
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 3})])
	_both_armed()
	w.step()
	assert_false(w.match_over, "one villager is not three")

	_villagers(w, 1, 2)
	w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1, "the scenario's own player wins it")
	assert_false(w.player_for(1).defeated)


func test_two_win_rows_are_anded_and_neither_half_wins_alone() -> void:
	# Scenario 1's shape: "a house AND fifteen villagers" is one objective in two halves.
	w = _world([
		_row({"subject": "building", "id": "building.house", "value": 1}),
		_row({"subject": "unit", "id": "unit.villager", "value": 3}),
	])
	_both_armed()
	_villagers(w, 1, 2)
	w.step()
	assert_false(w.match_over, "three villagers and no house is half an objective")

	w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_true(w.match_over, "and now both halves")
	assert_eq(w.winner_id, 1)


func test_a_foundation_is_not_a_building_you_have_built() -> void:
	# ⚠️ Deliberately the POPULATION CAP's rule and deliberately NOT the elimination
	# rule's, which counts a foundation because it is answering a different question --
	# whether its owner is still in the game. "Build a house" is not satisfied by pegging
	# one out and walking away.
	w = _world([_row({"subject": "building", "id": "building.house", "value": 1})])
	_both_armed()
	var house := w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.FOUNDATION, true)
	w.step()
	assert_false(w.match_over, "a foundation is not a house")
	assert_eq(w.player_for(1).objective_progress[0], 0)

	house.phase = SimBuilding.Phase.COMPLETE
	w.step()
	assert_true(w.match_over)


func test_rubble_stops_counting_the_moment_it_falls() -> void:
	# Rubble lingers in `entities` for a minute (5.5), so counting it would keep an
	# objective reading as satisfied long after it stopped being true.
	w = _world([_row({"subject": "building", "id": "building.house", "value": 2})])
	_both_armed()
	var a := w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	w.spawn_building(&"building.house", 1, Vector2i(26, 26),
			SimBuilding.Phase.COMPLETE, true)
	a.alive = false
	w.step()
	assert_true(w.entities.has(a.id), "the wreckage is still there to be drawn")
	assert_eq(w.player_for(1).objective_progress[0], 1, "but it is not a house any more")
	assert_false(w.match_over)


func test_an_age_row_reads_the_player_rather_than_the_map() -> void:
	# Scenario 2's second half. `subject: age` counts no entities, and the value is the
	# age INDEX -- ages start at 1, so `>= 2` is "has advanced once".
	w = _world([_row({"subject": "age", "value": 2})])
	_both_armed()
	w.step()
	assert_false(w.match_over)
	assert_eq(w.player_for(1).objective_progress[0], 1, "still in the Age of Ash")

	w.player_for(1).age = 2
	w.step()
	assert_true(w.match_over)


# ── the resource subject, and the latch it forced (2026-09-02) ──────────────────

func test_a_resource_row_reads_the_stockpile() -> void:
	w = _world([_row({"subject": "resource", "id": "food", "value": 500})])
	_both_armed()
	w.player_for(1).add_resource(&"food", 499)
	w.step()
	assert_false(w.match_over, "499 is not 500")
	assert_eq(w.player_for(1).objective_progress[0], 499)

	w.player_for(1).add_resource(&"food", 1)
	w.step()
	assert_true(w.match_over)


func test_a_resource_row_counts_only_its_own_kind() -> void:
	# `stock` is a plain Dictionary, so a row that summed kinds -- or read the wrong one --
	# would be satisfied by a pile of stone.
	w = _world([_row({"subject": "resource", "id": "food", "value": 100})])
	_both_armed()
	w.player_for(1).add_resource(&"wood", 5000)
	w.player_for(1).add_resource(&"stone", 5000)
	w.player_for(1).add_resource(&"gold", 5000)
	w.step()
	assert_false(w.match_over, "wood is not food")
	assert_eq(w.player_for(1).objective_progress[0], 0)


func test_a_win_row_stays_met_after_the_player_spends_what_met_it() -> void:
	# ⚠️ **THE MOST LOAD-BEARING TEST IN THIS FILE, and it comes from a measurement rather
	# than from a preference.** Scenario 2 asks for 500 food AND age 2. Advancing to age 2
	# costs exactly 500 food and `AdvanceAgeCommand` deducts it when the advance STARTS, so
	# the food row is true at the moment the age is affordable and false from the instant it
	# is bought -- 100 ticks before the age arrives. ANDed live, the two are never true
	# together and the scenario is UNWINNABLE WHILE LOOKING CORRECT.
	#
	# So a satisfied win row latches. Simulated here by spending the food directly, which
	# is what the command does.
	w = _world([
		_row({"subject": "resource", "id": "food", "value": 500}),
		_row({"subject": "age", "value": 2}),
	])
	_both_armed()
	var p := w.player_for(1)
	p.add_resource(&"food", 500)
	w.step()
	assert_false(w.match_over, "the food is in but the age is not")
	assert_eq(p.objective_done[0], 1, "the food row is ticked off")
	assert_eq(p.objective_done[1], 0)

	# Buy the age: the food goes, and the age has not arrived yet.
	p.pay({&"food": 500})
	w.step()
	assert_eq(int(p.stock.get(&"food", 0)), 0)
	assert_eq(p.objective_progress[0], 0, "the live count follows the stockpile down")
	assert_eq(p.objective_done[0], 1, "but a ticked line does not untick")
	assert_false(w.match_over)

	p.age = 2
	w.step()
	assert_true(w.match_over, "both rows have been met, though never at the same instant")
	assert_eq(w.winner_id, 1)


func test_the_live_count_and_the_latch_are_two_different_facts() -> void:
	# 15.6 draws BOTH -- "Villagers 4 / 10" from the count, a tick from the latch -- so
	# collapsing them into one field would cost the tracker one of the two things it shows.
	#
	# A SECOND, UNREACHABLE ROW keeps the match running while the first row is met and then
	# un-met, which is the only way to watch the two fields disagree: with one row the
	# match would end on the tick it was satisfied and there would be nothing further to
	# observe.
	w = _world([
		_row({"subject": "unit", "id": "unit.villager", "value": 2}),
		_row({"subject": "age", "value": 4}),
	])
	_both_armed()
	var second := w.spawn_unit(&"unit.villager", 1, Vector2i(12, 12))
	w.step()
	var p := w.player_for(1)
	assert_eq(p.objective_progress[0], 2, "the live count")
	assert_eq(p.objective_done[0], 1, "and the verdict")

	second.alive = false
	w.step()
	assert_eq(p.objective_progress[0], 1, "one villager left, and the count says so")
	assert_eq(p.objective_done[0], 1, "while the ticked row stays ticked")
	assert_false(w.match_over, "the age row is still outstanding")


# ── whose things are counted ────────────────────────────────────────────────────

func test_gaia_is_not_an_enemy_so_leave_the_enemy_nothing_is_not_shoot_every_deer() -> void:
	# ⚠️ **THE TRAP THIS SYSTEM IS MOST LIKELY TO HAVE FALLEN INTO.** PLAN.md 11.8's own
	# example of *leave the enemy nothing* is an id-less `owner: enemy, == 0` row. Owner 0
	# owns the trees, the sheep, the deer AND the wolves, so an evaluator that counted
	# "entities not mine" would make that row mean "kill every animal on the map" -- an
	# objective the author never wrote and the player cannot guess.
	w = _world([_row({"subject": "unit", "owner": "enemy", "compare": "==", "value": 0})])
	var mine := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	var theirs := w.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))
	# Gaia's menagerie, which must be invisible to this rule.
	w.spawn_unit(&"unit.deer", 0, Vector2i(15, 15))
	w.spawn_unit(&"unit.wolf", 0, Vector2i(16, 16))
	w.spawn_unit(&"unit.sheep", 0, Vector2i(17, 17))
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1,
			"one enemy villager, and no animals")
	assert_false(w.match_over)

	theirs.alive = false
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 0)
	assert_true(w.match_over, "the wildlife is still standing and the objective is met")
	assert_eq(w.winner_id, 1)
	assert_true(mine.alive)


func test_self_counts_only_your_own_things() -> void:
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 4})])
	_both_armed()
	_villagers(w, 2, 10)
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1,
			"the opponent's ten villagers are not yours")
	assert_false(w.match_over)


func test_the_bot_cannot_win_the_players_objective() -> void:
	# ⚠️ **WHY `objective_player_id` IS CARRIED RATHER THAN DERIVED.** The Passive AI runs
	# its whole economy and trains villagers from its town centre, so an evaluator that
	# measured "self" for every player would hand the economy lesson to the bot and the
	# human would watch it happen.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 4})])
	_both_armed()
	_villagers(w, 2, 20)
	for i in range(5):
		w.step()
	assert_false(w.match_over, "player 2 has twenty villagers and has won nothing")
	assert_eq(w.player_for(2).objective_progress.size(), 0,
			"and no progress was written from a viewpoint nobody authored")


func test_an_ally_row_counts_your_whole_side_including_you() -> void:
	# `ALLY` means YOUR SIDE, which is the only reading a co-op scenario could use: a rule
	# that counted your teammate's houses while ignoring your own is a rule nobody would
	# author, and `SELF` already exists for the narrower question.
	var team := _world([_row({"subject": "unit", "id": "unit.villager", "owner": "ally",
			"value": 3})], [7, 7] as Array[int])
	_both_armed(team)
	assert_true(Diplomacy.allied(1, 2, team.teams), "the fixture really is a team")
	team.step()
	assert_eq(team.player_for(1).objective_progress[0], 2,
			"one each, and both are on your side")

	team.spawn_unit(&"unit.villager", 2, Vector2i(31, 31))
	team.step()
	assert_true(team.match_over, "a teammate's villager counts toward your side's total")
	assert_eq(team.winner_id, 1)
	assert_eq(team.winner_team, 7, "and the side is named, so a knocked-out ally is told")


func test_an_enemy_row_excludes_your_ally_as_well_as_gaia() -> void:
	var team := _world([_row({"subject": "unit", "owner": "enemy", "compare": "==",
			"value": 0})], [7, 7] as Array[int])
	_both_armed(team)
	team.spawn_unit(&"unit.deer", 0, Vector2i(15, 15))
	team.step()
	assert_eq(team.player_for(1).objective_progress[0], 0,
			"an ally is not an enemy and neither is a deer")
	assert_true(team.match_over, "so 'no enemies left' is already true here")


func test_an_owner_index_names_one_player_whatever_the_alliances_do() -> void:
	# The escort mission's shape: "player 2 must survive" does not change meaning when the
	# teams do. `INDEX` is per-OBJECTIVE, which is why it cannot come out of one table
	# built per tick.
	w = _world([_row({"subject": "unit", "owner": 2, "compare": ">=", "value": 1})])
	var units := _both_armed()
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1, "player 2's own villager")
	assert_true(w.match_over)

	# And the same row against a player who owns nothing counts zero rather than erroring.
	var other := _world([_row({"subject": "unit", "owner": 2, "compare": ">=", "value": 1})])
	other.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	other.step()
	assert_eq(other.player_for(1).objective_progress[0], 0)
	assert_false(other.match_over)
	assert_true(units[1].alive)


# ── the comparisons ────────────────────────────────────────────────────────────

func test_all_three_comparisons_are_evaluated_as_written() -> void:
	# ONE VILLAGER FOR PLAYER 1 IN EVERY CASE, and the target is 2 in every case, so the
	# three comparisons are the only thing that differs: `>= 2` and `== 2` are false
	# against one, `<= 2` is true. A comparison read as the wrong one shows up as exactly
	# one of these three flipping.
	var cases := {">=": false, "==": false, "<=": true}
	for compare: String in cases:
		var world := _world([_row({"subject": "unit", "id": "unit.villager",
				"compare": compare, "value": 2})])
		_both_armed(world)
		world.step()
		assert_eq(world.match_over, bool(cases[compare]),
				"'%s 2' against one villager" % compare)
		assert_eq(world.player_for(1).objective_progress[0], 1,
				"'%s' measured the same count either way" % compare)


func test_exactly_stops_being_satisfied_when_the_count_passes_it() -> void:
	# `==` is the comparison a latch could hide a bug in, so it is worth seeing it fail
	# UPWARDS: two villagers satisfies `== 2` and three does not.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "compare": "==",
			"value": 3})])
	_both_armed()
	_villagers(w, 1, 3)
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 4)
	assert_false(w.match_over, "four is not exactly three")


func test_at_most_zero_is_not_satisfied_by_an_unmeasurable_subject() -> void:
	# `_count` returns -1 for a subject it cannot measure and `_satisfied` refuses it,
	# because 0 is a value that PASSES `== 0` and `<= n`. Reached here through a def built
	# by hand: `ObjectiveDef.from_dict` refuses `area`/`named_unit`/`ticks` outright, so
	# this covers a future subject added to the enum without a case in `_count`.
	var o := ObjectiveDef.new()
	o.subject = ObjectiveDef.Subject.AREA
	o.compare = ObjectiveDef.Compare.EXACTLY
	o.value = 0
	o.output = ObjectiveDef.Output.WIN
	assert_false(ObjectiveSystem._satisfied(o, -1),
			"an unmeasurable rule must not pass '== 0'")
	o.compare = ObjectiveDef.Compare.AT_MOST
	assert_false(ObjectiveSystem._satisfied(o, -1), "nor '<= 0'")


# ── conquest's loss without conquest's win (11.8's fork) ───────────────────────

func test_wiping_out_the_opponent_does_not_win_a_scenario() -> void:
	# ⚠️ **DECISION 5'S NAMED FAILURE, AND THE ONE THE SCENARIO FILE ITSELF SHOUTS ABOUT.**
	# Mapping SCENARIO onto LAST_MAN_STANDING would win scenario 1 by killing the Passive
	# AI's five villagers, with two villagers and no house -- teaching the opposite of the
	# scenario's name.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 15})])
	var units := _both_armed()
	units[1].alive = false
	for i in range(5):
		w.step()
	assert_true(w.player_for(2).defeated, "owning nothing is still defeat")
	assert_eq(w.player_for(2).defeat_reason, SimPlayer.Defeat.ELIMINATED)
	assert_false(w.match_over, "but outlasting them is not victory")
	assert_eq(w.winner_id, 0)
	assert_false(w.player_for(1).defeated)


func test_losing_everything_still_loses_a_scenario() -> void:
	# The other half of the fork: elimination is the loss on every map in this game
	# whatever a file declares, which is why `ScenarioDef` has no lose-condition field.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 15})])
	var units := _both_armed()
	units[0].alive = false
	w.step()
	assert_true(w.player_for(1).defeated)
	assert_eq(w.player_for(1).defeat_reason, SimPlayer.Defeat.ELIMINATED)
	assert_true(w.match_over, "a scenario ends when its player is out")
	assert_eq(w.winner_id, 0, "the teaching opponent did not win anything")


func test_the_opponent_is_not_marked_defeated_when_the_scenario_is_won() -> void:
	# `SimPlayer.defeat` records a REASON and there is no true one: the Passive bot that
	# just lost scenario 1 still owns its town centre. Writing ELIMINATED would be the
	# forfeit bug again -- true about the outcome, false about how it happened -- and
	# `GameScene._victory_subtitle` reads exactly that field to write its sentence.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 2})])
	_both_armed()
	w.spawn_unit(&"unit.villager", 1, Vector2i(12, 12))
	w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)
	assert_false(w.player_for(2).defeated,
			"the opponent lost a lesson, not a war")
	assert_eq(w.player_for(2).defeat_reason, SimPlayer.Defeat.NONE)


func test_a_lose_row_defeats_the_player_and_says_it_was_the_objective() -> void:
	w = _world([
		_row({"subject": "unit", "id": "unit.villager", "value": 99}),
		_row({"subject": "building", "id": "building.town_center", "compare": "==",
				"value": 0, "output": "lose"}),
	])
	_both_armed()
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_false(w.match_over, "the town centre is standing")

	tc.alive = false
	w.step()
	assert_true(w.player_for(1).defeated)
	assert_eq(w.player_for(1).defeat_reason, SimPlayer.Defeat.OBJECTIVE_FAILED,
			"they still own a villager, so this is not an elimination")
	assert_true(w.match_over)
	assert_eq(w.winner_id, 0)


func test_two_lose_rows_are_ored_rather_than_anded() -> void:
	# The asymmetry with WIN is deliberate: two failure conditions that had to be true
	# SIMULTANEOUSLY would be a scenario you can only lose by bad luck.
	w = _world([
		_row({"subject": "unit", "id": "unit.villager", "value": 99}),
		_row({"subject": "building", "id": "building.house", "compare": "==",
				"value": 0, "output": "lose"}),
		_row({"subject": "building", "id": "building.barracks", "compare": "==",
				"value": 0, "output": "lose"}),
	])
	_both_armed()
	# A house but no barracks: the second lose row is true, the first is not.
	w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_true(w.player_for(1).defeated, "one failure condition is enough")
	assert_eq(w.player_for(1).defeat_reason, SimPlayer.Defeat.OBJECTIVE_FAILED)


# ── what must NOT be decided ───────────────────────────────────────────────────

func test_an_empty_world_decides_nothing_however_the_row_reads() -> void:
	# ⚠️ **THE `_trophy()` TRAP, WHICH THIS SYSTEM IS THE MOST EXPOSED THING IN THE SIM
	# TO.** In a world with no entities, "the enemy has 0 units" is TRUE -- so a naive
	# evaluator declares victory on tick 1 of every world that has not been stood up yet,
	# which is most of the sim suite and any tool that inspects one. `match_over` latches,
	# so that verdict would then stick for the whole run.
	w = _world([_row({"subject": "unit", "owner": "enemy", "compare": "==", "value": 0})])
	for i in range(5):
		w.step()
	assert_false(w.match_over)
	assert_eq(w.winner_id, 0)
	assert_eq(w.player_for(1).objective_progress.size(), 0,
			"and nothing was even measured")


func test_no_win_row_at_all_never_wins_on_tick_one() -> void:
	# `ScenarioDef` refuses `mode: scenario` with no win row, so this is reachable only
	# from a config built by hand -- a test, or a future editor. It matters because the
	# ANDed check starts TRUE: with no rows to falsify it, a list of pure alerts would be
	# a match won immediately.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 1,
			"output": "alert"})])
	_both_armed()
	for i in range(5):
		w.step()
	assert_false(w.match_over, "an alert decides nothing")
	assert_eq(w.player_for(1).objective_progress[0], 1, "but it is still measured for 15.6")
	assert_eq(w.player_for(1).objective_done[0], 1, "and latched, so 15.6 fires it once")


func test_objectives_are_ignored_outside_scenario_mode() -> void:
	# Not a guard against a scenario file -- the loader refuses `last_man_standing` with
	# objectives -- but against this system becoming a second place that decides what a
	# mode means.
	var lms := _world([_row({"subject": "unit", "id": "unit.villager", "value": 1})])
	lms.mode = MatchConfig.Mode.LAST_MAN_STANDING
	_both_armed(lms)
	lms.step()
	assert_false(lms.match_over, "conquest is undecided with both players standing")
	assert_eq(lms.player_for(1).objective_progress.size(), 0,
			"and no objective was evaluated")


func test_a_result_is_never_overwritten_by_the_ticks_after_it() -> void:
	# `match_over` latches for `WinConditionSystem`'s reason: corpses and rubble settle in
	# the seconds after a result, and re-deciding would let them change it.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 2})])
	var units := _both_armed()
	w.spawn_unit(&"unit.villager", 1, Vector2i(12, 12))
	w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)

	# Now take everything away from the winner and keep ticking.
	units[0].alive = false
	for e in w.entities.values():
		e.alive = false
	for i in range(10):
		w.step()
	assert_eq(w.winner_id, 1, "still the winner")
	assert_false(w.player_for(1).defeated, "and not retroactively eliminated")


func test_a_defeated_player_cannot_then_win_the_objective() -> void:
	# The elimination rule runs directly AFTER this system, so a player wiped out on tick
	# N is defeated on tick N -- and must not be handed a win on tick N+1 by a row that
	# happens to still read as satisfied (an `at_most` row is satisfied by owning nothing).
	w = _world([_row({"subject": "unit", "id": "unit.villager", "compare": "<=",
			"value": 0})])
	# ONLY THE OPPONENT OWNS ANYTHING, so player 1 has zero villagers and the row above is
	# SATISFIED -- which is what makes this a real test rather than a tautology. Player 1
	# resigns, the way `ResignCommand` and a vanished peer both do.
	w.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))
	w.player_for(1).defeat(SimPlayer.Defeat.RESIGNED)
	for i in range(3):
		w.step()
	assert_true(w.player_for(1).defeated)
	assert_eq(w.player_for(1).defeat_reason, SimPlayer.Defeat.RESIGNED,
			"and the reason is not rewritten by the elimination pass")
	assert_ne(w.winner_id, 1, "a player who is out does not win, satisfied row or not")
	assert_eq(w.player_for(1).objective_progress.size(), 0,
			"nothing was even measured for them")


# ── the wire and the hash ──────────────────────────────────────────────────────

func test_progress_and_the_latch_ride_the_snapshot() -> void:
	# 15.6's tracker reads these off `player_state`. The DEFS are already on the client --
	# every client builds its own world from the same config (2.4a) -- so only the numbers
	# travel; sending the text every tick would be sending a scenario file at 10 Hz.
	w = _world([
		_row({"subject": "unit", "id": "unit.villager", "value": 2}),
		_row({"subject": "age", "value": 4}),
	])
	_both_armed()
	w.spawn_unit(&"unit.villager", 1, Vector2i(12, 12))
	w.step()

	var snap := SnapshotSystem.build(w, 1)
	var mine: Dictionary = (snap["player_state"] as Dictionary)[1]
	assert_eq(mine["objective_progress"], [2, 1] as Array[int])
	assert_eq(int((mine["objective_done"] as PackedByteArray)[0]), 1)
	assert_eq(int((mine["objective_done"] as PackedByteArray)[1]), 0)
	assert_eq(int(snap["mode"]), int(MatchConfig.Mode.SCENARIO),
			"the result screen needs the rule that decided it")


func test_objective_state_is_folded_into_the_state_hash() -> void:
	# ⚠️ **WHICH entities were counted depends on `Diplomacy` and the team table**, so two
	# hosts that resolved `owner: enemy` differently would agree about every entity in the
	# world and disagree about how far along the objective was -- silently, for a whole
	# match, and then announce victory on different ticks.
	w = _world([_row({"subject": "unit", "id": "unit.villager", "value": 9})])
	_both_armed()
	w.step()
	var before := w.state_hash()

	w.player_for(1).objective_progress[0] = 4
	assert_ne(w.state_hash(), before, "the live count is hashed")

	w.player_for(1).objective_progress[0] = 1
	assert_eq(w.state_hash(), before, "and only that")

	# The latch is hashed BESIDE the count rather than instead of it: it is irreversible,
	# so two hosts that ticked the same row on different ticks would go on agreeing about
	# the count for the rest of the match while carrying different verdicts about it.
	w.player_for(1).objective_done[0] = 1
	assert_ne(w.state_hash(), before, "and so is the latch, separately")


func test_the_same_scenario_run_twice_hashes_identically() -> void:
	# PLAN.md 7.7 layer 3, applied to the newest thing in the tick order. An objective
	# evaluated out of a Dictionary walk would be the obvious way to break this.
	var rows := [
		_row({"subject": "unit", "id": "unit.villager", "value": 4}),
		_row({"subject": "resource", "id": "food", "value": 300}),
	]
	var a := _world(rows)
	var b := _world(rows)
	# TYPED loop variable: an untyped one over a literal array has no set type, which makes
	# `:=` on anything derived from it a PARSE error rather than a runtime one -- the trap
	# `test_scenario_launch` records for failing to compile a whole file.
	for world: SimWorld in [a, b]:
		_both_armed(world)
		_villagers(world, 1, 2)
		world.player_for(1).add_resource(&"food", 150)
		for i in range(20):
			world.step()
	assert_eq(a.state_hash(), b.state_hash())
	assert_false(a.match_over, "three villagers and 150 food is neither row")


# ── the loader's half of the resource subject ──────────────────────────────────

func test_a_resource_row_must_name_a_kind_and_it_must_be_a_real_one() -> void:
	# `stock` is a plain Dictionary and `stock.get(&"foood", 0)` is 0, so a typo reads as
	# "the player has none and never will" -- an unwinnable scenario whose only symptom is
	# that nothing ever happens. Caught at LOAD, where somebody is reading a file.
	var problems: Array[String] = []
	assert_null(ObjectiveDef.from_dict(
			{"subject": "resource", "compare": ">=", "value": 500}, problems),
			"a resource row with no id cannot be measured")
	assert_true(problems[0].contains("must name which resource"), problems[0])

	problems.clear()
	assert_null(ObjectiveDef.from_dict(
			{"subject": "resource", "id": "foood", "compare": ">=", "value": 500}, problems))
	assert_true(problems[0].contains("unknown resource"), problems[0])

	problems.clear()
	for kind in ObjectiveDef.RESOURCE_KINDS:
		var o := ObjectiveDef.from_dict(
				{"subject": "resource", "id": kind, "compare": ">=", "value": 1}, problems)
		assert_not_null(o, "'%s' is a real kind: %s" % [kind, " | ".join(problems)])


func test_the_declared_resource_kinds_are_the_ones_a_player_actually_holds() -> void:
	# ⚠️ Two lists of four in two files, and nothing else says they are the same list.
	# `MapGen.STARTING_STOCK` is what a player is given; `RESOURCE_KINDS` is what a
	# scenario may ask about. A kind in one and not the other is a row that can never be
	# satisfied, or a resource no scenario can name.
	var declared := ObjectiveDef.RESOURCE_KINDS.duplicate()
	declared.sort()
	var granted: Array[String] = []
	for kind in MapGen.STARTING_STOCK:
		granted.append(String(kind))
	granted.sort()
	assert_eq(declared, granted)


func test_the_declared_subjects_are_in_wire_order() -> void:
	# `subject` travels as an int, so inserting a member rather than appending one
	# renumbers the rest and reinterprets every objective already recorded or in flight.
	# RESOURCE reads better beside AGE and is deliberately not there.
	assert_eq(ObjectiveDef.Subject.keys(),
			["UNIT", "BUILDING", "AGE", "AREA", "NAMED_UNIT", "TICKS", "RESOURCE"])
	assert_eq(int(ObjectiveDef.Subject.RESOURCE), 6, "appended, so the older six keep theirs")
