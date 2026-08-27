## The PlayTest AI (PLAN.md 12.2a): does it play, and does a match against it END?
##
## The last question is the one this file exists for. An AI that gathers politely
## forever is not a regression test; an AI that finishes a match exercises the win
## condition, the result path and the whole command surface in one run, with nobody
## holding two phones.
extends TestCase

## Long enough for the opening to get going at 10 Hz, and **no longer**.
##
## Kept deliberately tight. The AI runs inside the tick and does real work, so every
## hundred ticks here is real seconds of suite time -- at 3000 these tests took the whole
## run from 30 seconds to over ten minutes, which is a suite nobody runs. A full match
## belongs in `dev_preview/preview_ai_match.tscn`, which is on-demand; what these assert
## is that the machinery works, and 1200 ticks is two minutes of game time.
const RUN_TICKS := 1200


func _match(players: int = 2, p_seed: int = 3) -> SimWorld:
	var cfg := MatchConfig.debug_generated(p_seed, MapGenerator.Type.FOREST, players)
	# Player 1 is the AI here, so a test does not have to drive a human to see it play.
	cfg.ai_players = [true, false] as Array[bool]
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	return w


func _ai(w: SimWorld) -> AISystem:
	for s in w._systems:
		if s is AISystem:
			return s
	return null


func _count(w: SimWorld, owner: int, def_id: StringName) -> int:
	var n := 0
	for e in w.entities.values():
		if e.alive and e.owner_id == owner and e.def_id == def_id:
			n += 1
	return n


func _run(w: SimWorld, ticks: int = RUN_TICKS) -> void:
	for i in range(ticks):
		w.step()


# ── difficulty (2026-08-22) ─────────────────────────────────────────────────
#
# Five levels in the lobby and only two of them behave differently: PASSIVE never
# attacks, EASY is the PlayTest AI unchanged, and NORMAL / HARD / UNFAIR are declared
# placeholders that play as EASY. What is worth testing is exactly that -- that passive
# really is harmless, and that the placeholders really are wired to something rather
# than silently doing nothing.


## A world where player 1 is a bot at `level`.
func _match_at(level: int, players: int = 2, p_seed: int = 3) -> SimWorld:
	var cfg := MatchConfig.debug_generated(p_seed, MapGenerator.Type.FOREST, players)
	cfg.ai_players = [true, false] as Array[bool]
	cfg.ai_levels = [level, SimPlayer.AILevel.EASY] as Array[int]
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	return w


## Every attack order this player's units are currently carrying out.
func _attackers(w: SimWorld, owner: int) -> int:
	var n := 0
	for e in w.entities.values():
		if e is SimUnit and e.alive and e.owner_id == owner \
				and (e as SimUnit).task == SimUnit.Task.ATTACK:
			n += 1
	return n


func test_a_level_is_carried_from_the_config_to_the_player() -> void:
	var w := _match_at(SimPlayer.AILevel.PASSIVE)
	assert_true(w.player_for(1).is_ai, "still a bot")
	assert_eq(w.player_for(1).ai_level, SimPlayer.AILevel.PASSIVE)


func test_an_unnamed_level_defaults_to_easy() -> void:
	# Every debug factory and every config recorded before difficulty existed leaves
	# `ai_levels` empty, and all of them should keep getting the AI they always got.
	var w := _match()
	assert_true(w.player_for(1).is_ai)
	assert_eq(w.player_for(1).ai_level, SimPlayer.AILevel.EASY,
			"a config that names no level still plays the PlayTest AI")


func test_a_passive_bot_still_builds_an_economy() -> void:
	# Passive is a punching bag, not a paused bot. If it stopped playing entirely it
	# would be useless for developing against, which is the whole point of it.
	var w := _match_at(SimPlayer.AILevel.PASSIVE)
	_run(w, 600)
	assert_true(_ai(w).decisions_of(1) > 0, "it is making decisions")
	var built := 0
	for e in w.entities.values():
		if e is SimBuilding and e.owner_id == 1:
			built += 1
	assert_true(built > 1, "it has put something up beyond its town centre")


## Put `owner` in the state the standing-order attack fires in: its attack rule has
## fired once, and it has an army in hand.
##
## FAST-FORWARDED RATHER THAN PLAYED OUT, and that is the only reason these two tests
## are worth having. The first version simply ran 1200 ticks and asserted nobody
## attacked -- and it passed with the gate REMOVED, because the attack condition is not
## reached inside 1200 ticks and the branch under test was never entered. A test that
## cannot fail is worse than no test: it is a claim nobody will re-check. Playing
## honestly to an Easy bot's 10-minute unlock is 6000 ticks (see `RUN_TICKS`).
##
## Sets the flag the ATTACK RULE would have set. Under the old script this reached in
## and completed the script, for the same reason and with the same honesty problem.
func _unleash(w: SimWorld, owner: int) -> void:
	_run(w, 100)          # let it register some progress first
	var ai := _ai(w)
	ai._progress[owner]["attacked"] = true
	# An army, standing next to nothing in particular. `_idle_military` picks up any
	# free non-villager, and player 2's town centre is what `_nearest_enemy` finds.
	var home := Vector2i.ZERO
	for e in w.entities.values():
		if e is SimBuilding and e.owner_id == owner:
			home = (e as SimBuilding).tile()
			break
	for i in range(3):
		w.spawn_unit(&"unit.swordsman", owner, home + Vector2i(i + 2, 2))


func test_an_easy_bot_attacks_once_its_attack_rule_has_fired() -> void:
	# THE CONTROL, and the reason the passive test below means anything: it proves the
	# fixture actually reaches the attacking branch. Without this pair, "passive did not
	# attack" is indistinguishable from "nothing would have attacked".
	var w := _match_at(SimPlayer.AILevel.EASY)
	_unleash(w, 1)
	_run(w, 60)
	assert_true(_attackers(w, 1) > 0,
			"a fired attack rule turns the standing-order attack on")


func test_a_passive_bot_never_attacks_however_it_is_unleashed() -> void:
	# THE TRAP. Skipping the script's `attack` step is not enough on its own -- skipping
	# it COMPLETES the script, and a completed script is what switches the standing
	# order's attack on. A passive bot would have built its economy and then thrown its
	# army at you anyway.
	var w := _match_at(SimPlayer.AILevel.PASSIVE)
	_unleash(w, 1)
	for i in range(60):
		w.step()
		assert_eq(_attackers(w, 1), 0, "passive attacked on tick %d" % (i + 1))


func test_every_level_actually_plays() -> void:
	# This used to say "the placeholder levels are wired to something", because Normal,
	# Hard and Unfair all fell through to Easy and asserting they DIFFERED would have
	# been a lie. As of 12.2b each has its own rule file, so the lie is gone -- and what
	# is worth asserting is still that every one of them plays, since a profile that
	# fails to load falls back rather than failing loudly.
	for level in range(AIProfile.IDS.size()):
		var w := _match_at(level)
		_run(w, 400)
		assert_true(_ai(w).decisions_of(1) > 0,
				"%s acts rather than standing still" % AIProfile.IDS[level])


func test_the_level_survives_the_wire() -> void:
	var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	cfg.ai_players = [true, true] as Array[bool]
	cfg.ai_levels = [SimPlayer.AILevel.PASSIVE, SimPlayer.AILevel.UNFAIR] as Array[int]
	var back := MatchConfig.from_dict(cfg.to_dict())
	assert_eq(back.ai_levels, [SimPlayer.AILevel.PASSIVE, SimPlayer.AILevel.UNFAIR]
			as Array[int])
	var w := SimWorld.new()
	w.setup(back)
	assert_eq(w.player_for(1).ai_level, SimPlayer.AILevel.PASSIVE)
	assert_eq(w.player_for(2).ai_level, SimPlayer.AILevel.UNFAIR)


func test_a_config_with_no_levels_at_all_still_makes_bots() -> void:
	# What a host built before today sends. `ai_levels` is simply absent from the
	# dictionary and every bot has to come out at the default rather than at 0, which
	# is PASSIVE and would silently turn every opponent in the match harmless.
	var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	cfg.ai_players = [true, false] as Array[bool]
	var wire := cfg.to_dict()
	wire.erase("ai_levels")
	var back := MatchConfig.from_dict(wire)
	var w := SimWorld.new()
	w.setup(back)
	assert_true(w.player_for(1).is_ai)
	assert_eq(w.player_for(1).ai_level, SimPlayer.AILevel.EASY,
			"absent must not read as PASSIVE, which is level 0")


# ── it plays ────────────────────────────────────────────────────────────────

func test_only_ai_players_are_driven() -> void:
	var w := _match()
	_run(w, 400)
	var ai := _ai(w)
	assert_true(ai.decisions_of(1) > 0, "player 1 is a bot and has started its script")
	assert_eq(ai.decisions_of(2), 0, "player 2 is human and is left alone")


## A task census plus the AI's own log, for a failure message worth reading.
func _diagnose(w: SimWorld, ai: AISystem) -> String:
	var tasks: Dictionary = {}
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == 1 and e.alive:
			var key := "%s:%d" % [e.def_id, e.task]
			tasks[key] = int(tasks.get(key, 0)) + 1
	var keys := tasks.keys()
	keys.sort()
	var census: Array[String] = []
	for k in keys:
		census.append("%s x%d" % [k, tasks[k]])
	return "tick %d, step %d, stock %s\n            units: %s\n            %s" % [
			w.tick, ai.decisions_of(1), w.player_for(1).stock, ", ".join(census),
			"\n            ".join(ai.log_lines())]


## 1200 TICKS, NOT 600, since every unit speed was halved on 2026-08-23
## (units.json's note carries the owner's instruction). The claim being tested is
## "three villagers are gathering", and that is unchanged; what changed is how
## long it takes them to WALK to a node. At 600 ticks this now catches two
## gathering and the rest still in MOVE, with the economy demonstrably running --
## the failure printed food 200, wood 70, gold 260, stone 200 banked.
##
## Doubled rather than dropping the threshold to 2, deliberately: the threshold is
## the assertion and the window is the calibration, and lowering the assertion to
## fit a slower world would quietly weaken the test that the AI works at all.
func test_it_puts_its_villagers_to_work() -> void:
	var w := _match()
	_run(w, 1200)
	var working := 0
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == 1 and e.alive \
				and (e.task == SimUnit.Task.GATHER or e.task == SimUnit.Task.RETURN):
			working += 1
	assert_true(working >= 3, "%d villagers gathering -- %s"
			% [working, _diagnose(w, _ai(w))])


func test_it_banks_resources_it_did_not_start_with() -> void:
	# Through the whole loop: walk, extract, carry home, deposit. Measured as the total
	# EVER BANKED rather than as the stock at the end -- the stock goes DOWN when the
	# opening works, because an AI that is building is an AI that is spending. Summing
	# the positive deltas is the only way to ask "did the economy run" without the
	# answer being confounded by what it bought.
	var w := _match()
	var previous: Dictionary = {}
	var banked := 0
	for kind in [&"food", &"wood", &"gold", &"stone"]:
		previous[kind] = int(w.player_for(1).stock.get(kind, 0))

	for i in range(RUN_TICKS):
		w.step()
		for kind in previous:
			var now := int(w.player_for(1).stock.get(kind, 0))
			if now > int(previous[kind]):
				banked += now - int(previous[kind])
			previous[kind] = now

	assert_true(banked > 100, "banked %d over 1200 ticks -- %s"
			% [banked, _diagnose(w, _ai(w))])


func test_it_builds_and_advances() -> void:
	var w := _match()
	_run(w)
	var ai := _ai(w)
	var built := _count(w, 1, &"building.house") + _count(w, 1, &"building.mining_camp") \
			+ _count(w, 1, &"building.lumber_camp") + _count(w, 1, &"building.mill")
	assert_true(built >= 2, "raised %d of its opening buildings (step %d)"
			% [built, ai.decisions_of(1)])
	assert_true(w.player_for(1).age > 1 or w.player_for(1).is_advancing(),
			"reached or started age 2 (step %d)" % ai.decisions_of(1))


func test_it_keeps_deciding_rather_than_stalling() -> void:
	# THE FAILURE THIS DESIGN IS MEANT TO MAKE IMPOSSIBLE, so it is worth an assertion.
	# The old script abandoned a step it could not satisfy, and got stuck when it could
	# not; a rule set has nothing to get stuck ON -- a rule that cannot fire is walked
	# past, and the next one is tried in the same interval. A bot that has made only a
	# handful of decisions in two minutes of game time is one whose whole rule list is
	# somehow unreachable, which is the modern shape of "quietly useless".
	var w := _match()
	_run(w)
	var ai := _ai(w)
	var acts := ai.decisions_of(1)
	assert_true(acts >= 6, "took %d decisions in %d ticks:\n            %s"
			% [acts, RUN_TICKS, "\n            ".join(ai.log_lines())])


# ── it finishes a match ─────────────────────────────────────────────────────

func test_an_ai_versus_an_empty_opponent_wins_the_match() -> void:
	# THE ONE THIS FILE IS FOR. The AI is the only player with anything, so 11.1's
	# last-man-standing should hand it the match -- which proves the AI, the win
	# condition and the result path all work together with no human in the loop.
	var cfg := MatchConfig.debug_generated(5, MapGenerator.Type.FOREST, 2)
	cfg.ai_players = [true, false] as Array[bool]
	var w := SimWorld.new()
	w.setup(cfg)
	# Player 2's base is removed before the first tick, so they own nothing at all.
	var trimmed: Array[Dictionary] = []
	for e in cfg.map_data.entities:
		if int(e["player"]) != 2:
			trimmed.append(e)
	cfg.map_data.entities = trimmed
	MapGen.build(w, cfg)

	_run(w, 20)
	assert_true(w.match_over, "an opponent that owns nothing loses at once")
	assert_eq(w.winner_id, 1, "and the AI is the last one standing")


func test_the_ai_attacks_when_it_has_an_army() -> void:
	# The step that was ADDED to the owner's script, and the reason: without an ending
	# a headless match never exercises the win condition. Driven directly rather than
	# waiting ~5 minutes of sim for the barracks, since what is being tested is the
	# attack step's targeting, not the economy that precedes it.
	var w := _match()
	var army: Array[int] = []
	for i in range(3):
		army.append(w.spawn_unit(&"unit.swordsman", 1, Vector2i(40 + i, 40)).id)
	var ai := _ai(w)
	assert_true(ai._issue_attack(w, w.player_for(1)), "the attack was issued")
	w.step()

	var attacking := 0
	for id in army:
		var u: SimUnit = w.get_entity(id)
		if u.task == SimUnit.Task.ATTACK or u.task == SimUnit.Task.MOVE:
			attacking += 1
	assert_eq(attacking, army.size(), "every soldier took the order")


func test_it_targets_a_building_over_a_unit() -> void:
	# Buildings first, because it is the win condition that matters -- and a town centre
	# does not run away.
	var w := _match()
	w.spawn_unit(&"unit.swordsman", 1, Vector2i(48, 48))
	var ai := _ai(w)
	var target := ai._nearest_enemy(w, w.player_for(1), _military(w))
	assert_true(target != 0)
	assert_true(w.get_entity(target) is SimBuilding,
			"picked %s" % w.get_entity(target).def_id)


func _military(w: SimWorld) -> int:
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == 1 and e.def_id == &"unit.swordsman":
			return e.id
	return 0


# ── the rules it is built on ────────────────────────────────────────────────

func test_two_worlds_with_the_same_ai_stay_identical() -> void:
	# Determinism (7.1). The AI is inside the tick, so a non-deterministic AI is a
	# non-deterministic simulation -- and a replay could not reproduce an AI match.
	# 200 ticks is enough: a non-deterministic AI diverges almost immediately, since its
	# very first decision is a search over entity ids. Hashing two worlds every tick is
	# not cheap (each hash folds in both players' whole fog grids), so this buys the
	# signal without paying for a match.
	var a := _match(2, 9)
	var b := _match(2, 9)
	for i in range(200):
		a.step()
		b.step()
		assert_eq(a.state_hash(), b.state_hash(), "diverged on tick %d" % (i + 1))


func test_a_defeated_ai_stops_playing() -> void:
	var w := _match()
	_run(w, 200)
	w.player_for(1).defeated = true
	var ai := _ai(w)
	var step := ai.decisions_of(1)
	_run(w, 300)
	assert_eq(ai.decisions_of(1), step, "it stopped where it was")


# -- the rule files, asserted rather than trusted (12.2b) --------------------

func test_every_level_has_a_profile_with_rules_in_it() -> void:
	# A missing or unparseable file falls back to Easy rather than to a bot that stands
	# still, which is the right behaviour and also the one that would hide a typo in a
	# filename forever. This is what notices.
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		assert_eq(String(profile.id), String(AIProfile.IDS[level]),
				"level %d loaded its OWN file rather than falling back" % level)
		assert_true(profile.rules.size() > 5,
				"%s has a real rule set" % AIProfile.IDS[level])


func test_every_rule_names_a_verb_the_interpreter_knows() -> void:
	# An unknown verb is skipped rather than fatal, which is the safe behaviour and also
	# how a typo would hide. This is what catches the typo.
	var known := ["gather", "build", "train", "advance_age", "attack"]
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		for i in range(profile.rules.size()):
			var verb := String(profile.rules[i].get("do", ""))
			assert_true(known.has(verb),
					"%s rule %d: unknown verb '%s'" % [profile.id, i, verb])


func test_every_def_id_a_rule_names_exists() -> void:
	# A misspelled building is a rule that can never fire. Under the old script that
	# looked like a slow AI; under rules it looks like a bot that simply never builds
	# the thing -- quieter still, so the test matters more than it used to.
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		for i in range(profile.rules.size()):
			var rule: Dictionary = profile.rules[i]
			var where := "%s rule %d" % [profile.id, i]
			if rule.has("def"):
				assert_not_null(GameDataRegistry.building(rule["def"]),
						"%s builds %s" % [where, rule["def"]])
			if rule.has("unit"):
				assert_not_null(GameDataRegistry.unit(rule["unit"]),
						"%s trains %s" % [where, rule["unit"]])
			if rule.has("at"):
				assert_not_null(GameDataRegistry.building(rule["at"]),
						"%s trains at %s" % [where, rule["at"]])
			for key in ["fewer_than", "at_least"]:
				for def_id in (rule.get("when", {}) as Dictionary).get(key, {}):
					assert_true(GameDataRegistry.building(def_id) != null
							or GameDataRegistry.unit(def_id) != null,
							"%s counts %s, which is neither a building nor a unit"
									% [where, def_id])


func test_every_rule_can_stop_being_true() -> void:
	# THE ONE RULE OF THIS DESIGN, and the failure it prevents is severe. Rules are
	# re-evaluated every interval, so a rule whose condition stays true once satisfied
	# fires again and again -- five houses, an emptied treasury, a build queue nobody
	# asked for. Every rule therefore needs at least one condition that its own success
	# turns false.
	#
	# `after_ticks` and `age_min` do NOT count: time only moves forward and an age is
	# never given back, so a rule holding only those is permanently armed once armed.
	# `attack` is exempt -- attacking again IS the intent, and the standing orders take
	# it over afterwards.
	var self_limiting := ["fewer_than", "gathering_fewer_than", "age", "age_max"]
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		for i in range(profile.rules.size()):
			var rule: Dictionary = profile.rules[i]
			if String(rule.get("do", "")) == "attack":
				continue
			var when: Dictionary = rule.get("when", {})
			var bounded := false
			for key in self_limiting:
				if when.has(key):
					bounded = true
					break
			assert_true(bounded,
					"%s rule %d (%s) has no condition its own success turns false"
							% [profile.id, i, rule.get("do", "?")])


func test_the_difficulty_table_is_what_the_files_say() -> void:
	# AI_Player_difficulty.md, asserted rather than described. These five lines are the
	# owner's specification and every one of them is a number in a file somebody can
	# edit, so this is what notices when an edit contradicts the design.
	var passive := GameDataRegistry.ai_profile(SimPlayer.AILevel.PASSIVE)
	assert_false(passive.attacks, "passive never attacks")
	assert_eq(passive.max_age, 2, "passive never ages past 2")

	assert_eq(GameDataRegistry.ai_profile(SimPlayer.AILevel.EASY).max_age, 2)
	assert_eq(GameDataRegistry.ai_profile(SimPlayer.AILevel.NORMAL).max_age, 3)
	assert_eq(GameDataRegistry.ai_profile(SimPlayer.AILevel.HARD).max_age, 4)
	assert_eq(GameDataRegistry.ai_profile(SimPlayer.AILevel.UNFAIR).max_age, 4)

	# Reaction time is the difficulty knob, and it has to be monotonic or the levels do
	# not order. Unfair acts the tick its conditions come true.
	var easy := GameDataRegistry.ai_profile(SimPlayer.AILevel.EASY)
	var normal := GameDataRegistry.ai_profile(SimPlayer.AILevel.NORMAL)
	var hard := GameDataRegistry.ai_profile(SimPlayer.AILevel.HARD)
	var unfair := GameDataRegistry.ai_profile(SimPlayer.AILevel.UNFAIR)
	assert_true(easy.lag_max > normal.lag_max, "easy is slower to notice than normal")
	assert_true(normal.lag_max > hard.lag_max, "normal is slower than hard")
	assert_eq(unfair.lag_max, 0, "unfair has no reaction delay at all")


func test_only_passive_refuses_to_attack() -> void:
	for level in [SimPlayer.AILevel.EASY, SimPlayer.AILevel.NORMAL,
			SimPlayer.AILevel.HARD, SimPlayer.AILevel.UNFAIR]:
		assert_true(GameDataRegistry.ai_profile(level).attacks,
				"level %d is an offensive profile" % level)


func test_the_unfair_bot_is_the_only_one_that_cheats_at_the_start() -> void:
	# 'starts with 8 villagers and 2 swordsmen and 1 scout'. MapGen places five
	# villagers for everybody, so the file carries the DIFFERENCE.
	for level in [SimPlayer.AILevel.PASSIVE, SimPlayer.AILevel.EASY,
			SimPlayer.AILevel.NORMAL, SimPlayer.AILevel.HARD]:
		assert_true(GameDataRegistry.ai_profile(level).start_units.is_empty(),
				"level %d starts with what everybody starts with" % level)
	var unfair := GameDataRegistry.ai_profile(SimPlayer.AILevel.UNFAIR)
	assert_eq(int(unfair.start_units.get(&"unit.villager", 0)), 3,
			"3 extra on top of the standard 5 makes the 8 the table asks for")
	assert_eq(int(unfair.start_units.get(&"unit.swordsman", 0)), 2)
	# NO SCOUT, deliberately: the table's "1 scout" is the one every player already
	# starts with. Declaring it here gave Unfair two, which is the whole reason this
	# file declares the DIFFERENCE rather than the total.
	assert_eq(int(unfair.start_units.get(&"unit.scout_cavalry", 0)), 0)


func test_the_head_start_actually_reaches_the_map() -> void:
	# The file declaring it is not the same as the units existing. This is the seam
	# between AIProfile and MapGen, and nothing else crosses it.
	var w := _match_at(SimPlayer.AILevel.UNFAIR)
	var easy := _match_at(SimPlayer.AILevel.EASY)

	# The TOTALS the difficulty table asks for: 8 villagers, 2 swordsmen, 1 scout.
	assert_eq(_count(w, 1, &"unit.villager"), 8, "5 as standard plus 3 from the profile")
	assert_eq(_count(w, 1, &"unit.swordsman"), 2)
	assert_eq(_count(w, 1, &"unit.scout_cavalry"), 1,
			"ONE, not two -- the standard start already includes a scout")

	# And that every one of those is a DIFFERENCE from what anybody else gets, which is
	# what makes it a handicap rather than a map quirk.
	assert_eq(_count(easy, 1, &"unit.villager"), 5, "everybody else gets five")
	assert_eq(_count(easy, 1, &"unit.swordsman"), 0)
	assert_eq(_count(easy, 1, &"unit.scout_cavalry"), 1,
			"and the scout is standard, so it is not part of the cheat")


func test_a_higher_priority_goal_reserves_its_cost() -> void:
	# SAVING UP, which pure 'build when affordable' cannot do: if a cheap rule fires
	# whenever it can, an expensive one below it never accumulates. The first rule whose
	# conditions hold reserves its cost, and rules below may only spend the remainder.
	var ai := AISystem.new()
	var reserved: Dictionary = {}
	AISystem._reserve(reserved, {&"wood": 400})

	var w := _match()
	var p := w.player_for(1)
	p.stock[&"wood"] = 500

	var cheap := {"do": "build", "def": &"building.house"}
	assert_true(ai._affordable(w, p, cheap, {}),
			"a house is affordable out of 500 wood on its own")
	# building.house costs less than the 100 left after a 400 reservation, or this test
	# is asserting nothing -- so check the premise rather than assume it.
	var house_cost: Dictionary = GameDataRegistry.building(&"building.house").cost
	if int(house_cost.get(&"wood", 0)) > 100:
		assert_false(ai._affordable(w, p, cheap, reserved),
				"and NOT affordable once 400 of it is spoken for")


func test_the_reaction_delay_is_the_same_on_every_host() -> void:
	# `randi()` in the sim is a desync, so the lag is hashed from the decision's own
	# coordinates. Same inputs, same answer, every machine and every run.
	var profile := GameDataRegistry.ai_profile(SimPlayer.AILevel.EASY)
	for tick in [0, 37, 1200, 99999]:
		var a := AISystem._lag(profile, 1, tick, 3)
		var b := AISystem._lag(profile, 1, tick, 3)
		assert_eq(a, b, "same decision, same delay")
		assert_true(a >= profile.lag_min and a <= profile.lag_max,
				"delay %d is inside [%d, %d]" % [a, profile.lag_min, profile.lag_max])
	assert_eq(AISystem._lag(GameDataRegistry.ai_profile(SimPlayer.AILevel.UNFAIR),
			1, 500, 0), 0, "unfair never waits")
