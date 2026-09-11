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
	# ⚠️ **THE RULE THAT COMES FROM A MEASUREMENT RATHER THAN A PREFERENCE.** The pair below
	# is the one that shipped in scenario 2 for a few hours on 2026-09-02 and was then
	# withdrawn by the owner: 500 food AND age 2, where advancing to age 2 costs exactly 500
	# food and `AdvanceAgeCommand` deducts it when the advance STARTS. So the food row is
	# true at the moment the age is affordable and false from the instant it is bought, 100
	# ticks before the age arrives. ANDed live, the two are never true together and the
	# scenario is UNWINNABLE WHILE LOOKING CORRECT.
	#
	# **KEPT AS A TEST THOUGH NO SHIPPED SCENARIO IS THAT SHAPE ANY MORE**, because the
	# shape is what matters: any ANDed pair where satisfying one row SPENDS what satisfied
	# the other behaves this way, and a resource is only the most obvious such thing. This
	# is the case that would break first if the latch were ever taken out as unused.
	#
	# The spend is done directly, which is what the command does.
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


func test_a_gaia_row_counts_gaia_and_nobody_else() -> void:
	# Scenario 4's first row: *"kill the mother dragon"*, which is `unit.dragon` belonging
	# to owner 0 going to zero. The obvious spelling is `named_unit` and that is refused
	# until 16.7, so this is what an author has instead.
	w = _world([_row({"subject": "unit", "id": "unit.dragon", "owner": "gaia",
			"compare": "==", "value": 0})])
	_both_armed()
	var mother := w.spawn_unit(&"unit.dragon", 0, Vector2i(24, 24))
	# ONE OF EACH SIDE'S OWN, so a row that resolved gaia to "everybody" or to "not mine"
	# would come back with 3 rather than 1 and the assertion below would name it.
	w.spawn_unit(&"unit.dragon", 1, Vector2i(11, 11))
	w.spawn_unit(&"unit.dragon", 2, Vector2i(31, 31))
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1,
			"gaia's one dragon, not the two the players are holding")
	assert_false(w.match_over)

	mother.alive = false
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 0, "a corpse belongs to nobody")
	assert_true(w.match_over, "and the row is met with both players' dragons still flying")
	assert_eq(w.winner_id, 1)


func test_a_gaia_row_is_not_reached_through_diplomacy() -> void:
	# ⚠️ **THE ONE WAY `Owner.GAIA` COULD HAVE RE-OPENED TRAP 1.** `Diplomacy.allied(0, 0)`
	# is FALSE by that class's own rule -- *gaia allies with nobody* -- so implementing GAIA
	# by feeding 0 through `_side_of` would have filed it under NOT-ALLIED, which is the
	# enemy bucket. The row would then have counted every player's things as well as gaia's.
	# Two dragons per player against gaia's one is what tells the two apart.
	w = _world([_row({"subject": "unit", "id": "unit.dragon", "owner": "gaia",
			"compare": "==", "value": 1})])
	_both_armed()
	w.spawn_unit(&"unit.dragon", 0, Vector2i(24, 24))
	for i in range(2):
		w.spawn_unit(&"unit.dragon", 1, Vector2i(11 + i, 11))
		w.spawn_unit(&"unit.dragon", 2, Vector2i(31 + i, 31))
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1,
			"exactly gaia's, with four others on the map")


func test_gaia_owns_buildings_too_so_the_nest_is_countable() -> void:
	# Not used by any shipped scenario and asserted anyway, because it is the half of
	# `Owner.GAIA` a future map condition is most likely to want -- *"the nest is still
	# standing"* -- and because `_census` files buildings and units in different buckets, so
	# one of them working does not prove the other does.
	w = _world([_row({"subject": "building", "id": "building.dragon_nest", "owner": "gaia",
			"compare": ">=", "value": 1})])
	_both_armed()
	w.spawn_building(&"building.dragon_nest", 0, Vector2i(24, 24),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_eq(w.player_for(1).objective_progress[0], 1)
	assert_true(w.match_over)


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
	# by hand: `ObjectiveDef.from_dict` refuses `named_unit`/`ticks` outright, so this covers
	# a future subject added to the enum without a case in `_count`.
	# ⚠️ **THE SUBJECT USED TO BE `AREA` AND 16.5 MADE IT MEASURABLE**, so it is `NAMED_UNIT`
	# now — a test whose premise is "this subject cannot be counted" has an expiry date, which
	# is §5's rule about a behaviour test tied to whichever piece of data happens to fit today.
	var o := ObjectiveDef.new()
	o.subject = ObjectiveDef.Subject.NAMED_UNIT
	o.compare = ObjectiveDef.Compare.EXACTLY
	o.value = 0
	o.output = ObjectiveDef.Output.WIN
	assert_false(ObjectiveSystem._satisfied(o, -1),
			"an unmeasurable rule must not pass '== 0'")
	o.compare = ObjectiveDef.Compare.AT_MOST
	assert_false(ObjectiveSystem._satisfied(o, -1), "nor '<= 0'")


# ── areas: named regions (PLAN.md 16.5) ───────────────────────────────────────

## A world whose map declares one region, so `MapGen.build_from()` puts it on `SimWorld.areas`.
##
## ⚠️ **THROUGH `MapGen.build_from()` AND NOT BY ASSIGNING `w.areas`, WHICH IS THE HALF THAT
## COULD SILENTLY NOT EXIST.** Writing regions into `MapData` and not reading them there is the
## exact shape of 16.4c's wall-axis gap — the tool would draw a region, save it, and hand the
## match a world in which the objective counting it can never tick, with the file agreeing with
## the tool. So the fixture carries a real `MapData` and lets the generator do the collapse.
func _world_with_area(rows: Array, regions: Array) -> SimWorld:
	var data := MapData.create(Vector2i(48, 48), SimMap.Terrain.GRASS)
	for r in regions:
		data.add_area(r[0], r[1])

	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = data.size
	cfg.map_data = data
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
	MapGen.build_from(world, data)
	return world


func test_a_map_declaring_a_region_reaches_the_world_that_evaluates_it() -> void:
	var world := _world_with_area([], [[&"ford", Rect2i(10, 10, 4, 4)]])
	assert_true(world.areas.has(&"ford"), "%s" % [world.areas.keys()])
	assert_eq((world.areas[&"ford"] as Array).size(), 1)
	# THE FLAT LIST COLLAPSES BY NAME: two entries sharing one are one region of two rects.
	var two := _world_with_area([], [[&"pass", Rect2i(4, 4, 2, 2)],
			[&"pass", Rect2i(20, 20, 2, 2)]])
	assert_eq((two.areas[&"pass"] as Array).size(), 2)


func test_an_area_row_counts_what_is_standing_in_the_region_and_not_outside_it() -> void:
	var world := _world_with_area(
			[_row({"subject": "area", "area": "ford", "value": 2})],
			[[&"ford", Rect2i(10, 10, 4, 4)]])
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))     # populates the world
	world.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))     # mine, and nowhere near it
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 0, "outside does not count")
	assert_false(world.match_over)

	world.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	world.spawn_unit(&"unit.villager", 1, Vector2i(13, 13))
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 2, "both corners are inside")
	assert_true(world.match_over)


## Two rectangles under one name are ONE region, so a unit in either counts — which is the whole
## reason `MapData.areas` is flat rather than one rect per region.
func test_a_region_of_two_rectangles_counts_a_unit_in_either() -> void:
	var world := _world_with_area(
			[_row({"subject": "area", "area": "pass", "value": 2})],
			[[&"pass", Rect2i(4, 4, 3, 3)], [&"pass", Rect2i(30, 30, 3, 3)]])
	world.spawn_unit(&"unit.villager", 2, Vector2i(20, 20))
	world.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	world.spawn_unit(&"unit.villager", 1, Vector2i(31, 31))
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 2)


## ⚠️ **`id` STILL MEANS A DEF ID ON AN AREA ROW, WHICH IS WHY THE REGION HAS ITS OWN FIELD.**
## Putting the region in `id` would have made `_NAMES_AN_ID` a lie and left "five VILLAGERS in
## the ford" inexpressible — an author would have had to count everything they owned there.
func test_an_area_row_can_filter_by_def_or_count_everything() -> void:
	var world := _world_with_area([
		_row({"subject": "area", "area": "ford", "id": "unit.villager", "value": 2}),
		_row({"subject": "area", "area": "ford", "value": 3}),
	], [[&"ford", Rect2i(10, 10, 6, 6)]])
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	world.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	world.spawn_unit(&"unit.villager", 1, Vector2i(11, 11))
	world.spawn_unit(&"unit.scout_cavalry", 1, Vector2i(12, 12))
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 2, "two villagers")
	assert_eq(world.player_for(1).objective_progress[1], 3, "three things")


## ⚠️ **A BUILDING IS IN A REGION IF ANY OF ITS FOOTPRINT IS, AND AN ORIGIN TEST WOULD BE WRONG
## BY UP TO NINE TILES.** `SimBuilding.tile()` is the footprint's ORIGIN, so a 10x10 town centre
## whose middle sits in a region has its origin outside it — the same origin-versus-centre error
## `MapDocument._starts_inside()` and `preview_saved_map`'s second red run are the records of.
func test_a_building_overlapping_a_region_is_in_it() -> void:
	var world := _world_with_area(
			[_row({"subject": "area", "area": "base", "id": "building.town_center", "value": 1})],
			[[&"base", Rect2i(14, 14, 2, 2)]])
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	# ORIGIN AT 8,8 AND 10x10, so the region at 14,14 is inside the footprint and nowhere near
	# the origin. An origin test would count zero.
	var tc := world.spawn_building(&"building.town_center", 1, Vector2i(8, 8),
			SimBuilding.Phase.COMPLETE, true)
	assert_not_null(tc)
	# THE FIXTURE'S OWN PREMISE, ASSERTED: the region must NOT contain the origin, or this test
	# would pass under the origin test it exists to rule out.
	assert_false(Rect2i(14, 14, 2, 2).has_point(tc.tile()),
			"the region must miss the origin for this test to mean anything")
	assert_true(tc.footprint_rect().intersects(Rect2i(14, 14, 2, 2)),
			"and it must overlap the footprint")
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 1,
			"the town centre covers the region even though its origin does not")


## `_census`' two rules carried over, because both are ways a region reads as held when it is not:
## a pegged-out foundation is not a building on the ground, and rubble lingers a minute.
##
## THE TARGET IS 2 SO NOTHING EVER WINS, deliberately: the latch stops `process_tick` updating
## progress once a match is over, so a row that could be satisfied would freeze the very number
## this test is watching go down again.
func test_a_foundation_and_a_corpse_are_not_holding_a_region() -> void:
	var world := _world_with_area(
			[_row({"subject": "area", "area": "hill", "value": 2})],
			[[&"hill", Rect2i(20, 20, 4, 4)]])
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	var pegged := world.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.FOUNDATION, true)
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 0,
			"pegging one out is not holding the ground")

	pegged.phase = SimBuilding.Phase.COMPLETE
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 1)

	pegged.alive = false
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 0, "and rubble holds nothing")


## ⚠️ **UNITS AND BUILDINGS SHARE ONE BUCKET, AND THAT IS THE ANSWER TO "WHAT DOES AN AREA
## COUNT".** Splitting them would make *"the enemy has nothing in the crossing"* true of a
## crossing with an enemy fortress in it, which is the reading nobody wants and the one an author
## would never guess they had asked for.
func test_leave_the_enemy_nothing_here_is_not_satisfied_by_their_castle() -> void:
	var world := _world_with_area(
			[{"subject": "area", "area": "crossing", "owner": "enemy",
				"compare": "==", "value": 0, "output": "win"}],
			[[&"crossing", Rect2i(20, 20, 6, 6)]])
	world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	world.spawn_building(&"building.house", 2, Vector2i(21, 21),
			SimBuilding.Phase.COMPLETE, true)
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 1, "their house is holding it")
	assert_false(world.match_over)


## ⛔ **THE TRAP THIS SUBJECT BROUGHT WITH IT, AND THE REASON `MapData.has_area()` EXISTS.** An
## area row is evaluable and can still name a region the map has not got — a misspelling, or a
## scenario pointed at a re-authored map whose regions were renamed. "Nothing is in a region that
## does not exist" is **0**, which PASSES `== 0` and `<= n`, so an unwinnable scenario would
## announce victory on tick 1. `_in_area` answers -1 instead.
func test_a_region_the_map_has_not_got_is_unmeasurable_and_not_zero() -> void:
	var world := _world_with_area(
			[{"subject": "area", "area": "nowhere", "owner": "enemy",
				"compare": "==", "value": 0, "output": "win"}],
			[[&"somewhere_else", Rect2i(4, 4, 2, 2)]])
	world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], -1,
			"unmeasurable, so no comparison passes")
	assert_false(world.match_over, "and above all it did not win on tick 1")


## The other half of that: a region that DOES exist and happens to be empty is a real 0, and an
## `at_most` row about it is genuinely satisfied. Conflating the two would make one of these two
## tests impossible to write.
func test_a_region_that_exists_and_is_empty_really_counts_zero() -> void:
	var world := _world_with_area(
			[{"subject": "area", "area": "crossing", "owner": "enemy",
				"compare": "==", "value": 0, "output": "win"}],
			[[&"crossing", Rect2i(20, 20, 4, 4)]])
	world.spawn_unit(&"unit.villager", 1, Vector2i(2, 2))
	world.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	world.step()
	assert_eq(world.player_for(1).objective_progress[0], 0, "nobody there, and that is a count")
	assert_true(world.match_over)


## ⚠️ **A REUSED WORLD MUST NOT KEEP THE LAST MATCH'S REGIONS.** `preview_ai_match` steps four
## rungs through one world and every `dev_preview` tool reuses a config, so a scenario followed by
## a skirmish would otherwise leave the skirmish holding regions and an area row measuring a map
## nobody is playing. `SimWorld.setup()` clears them for `trophy_def_id`'s reason.
func test_setting_a_world_up_again_forgets_the_last_maps_regions() -> void:
	var world := _world_with_area([], [[&"ford", Rect2i(10, 10, 4, 4)]])
	assert_true(world.areas.has(&"ford"))
	var plain := MatchConfig.new()
	plain.player_ids = [1, 2]
	plain.teams = [0, 0]
	plain.map_size = Vector2i(48, 48)
	world.setup(plain)
	assert_true(world.areas.is_empty(), "%s" % [world.areas.keys()])


## One walk of the entity list however many area rows there are — `_census`' own argument applied
## to the second question. Four rows about the same place must not be four walks.
func test_the_area_census_is_one_pass_for_every_region_any_row_names() -> void:
	var world := _world_with_area([
		_row({"subject": "area", "area": "a", "value": 1}),
		_row({"subject": "area", "area": "a", "id": "unit.villager", "value": 1}),
		_row({"subject": "area", "area": "b", "value": 1}),
	], [[&"a", Rect2i(4, 4, 4, 4)], [&"b", Rect2i(20, 20, 4, 4)]])
	assert_eq(ObjectiveSystem._areas_named(world).size(), 2,
			"two distinct regions from three rows")
	# AND NO CENSUS AT ALL WHEN NOTHING ASKS, which is every match in the game today.
	var plain := _world([_row({"subject": "unit", "id": "unit.villager", "value": 1})])
	assert_true(ObjectiveSystem._areas_named(plain).is_empty())
	assert_true(ObjectiveSystem._area_census(plain, {}).is_empty())


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
