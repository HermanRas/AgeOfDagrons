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
	assert_true(_ai(w).step_of(1) > 0, "it is running its script")
	var built := 0
	for e in w.entities.values():
		if e is SimBuilding and e.owner_id == 1:
			built += 1
	assert_true(built > 1, "it has put something up beyond its town centre")


## Put `owner` at the END of its script with an army in hand, which is the state the
## standing-order attack fires in.
##
## FAST-FORWARDED RATHER THAN PLAYED OUT, and that is the only reason these two tests
## are worth having. The first version simply ran 1200 ticks and asserted nobody
## attacked -- and it passed with the gate REMOVED, because the script does not finish
## inside 1200 ticks and the branch under test was never reached. A test that cannot
## fail is worse than no test: it is a claim nobody will re-check. Running long enough
## to finish honestly was measured at ten minutes of suite time (see `RUN_TICKS`).
func _finish_the_script(w: SimWorld, owner: int) -> void:
	_run(w, 100)          # let it register some progress first
	var ai := _ai(w)
	ai._progress[owner]["step"] = AIPlaytest.SCRIPT.size()
	# An army, standing next to nothing in particular. `_idle_military` picks up any
	# free non-villager, and player 2's town centre is what `_nearest_enemy` finds.
	var home := Vector2i.ZERO
	for e in w.entities.values():
		if e is SimBuilding and e.owner_id == owner:
			home = (e as SimBuilding).tile()
			break
	for i in range(3):
		w.spawn_unit(&"unit.swordsman", owner, home + Vector2i(i + 2, 2))


func test_an_easy_bot_with_a_finished_script_does_attack() -> void:
	# THE CONTROL, and the reason the passive test below means anything: it proves the
	# fixture actually reaches the attacking branch. Without this pair, "passive did not
	# attack" is indistinguishable from "nothing would have attacked".
	var w := _match_at(SimPlayer.AILevel.EASY)
	_finish_the_script(w, 1)
	_run(w, 60)
	assert_true(_attackers(w, 1) > 0,
			"a finished script turns the standing-order attack on")


func test_a_passive_bot_never_attacks_even_once_its_script_is_done() -> void:
	# THE TRAP. Skipping the script's `attack` step is not enough on its own -- skipping
	# it COMPLETES the script, and a completed script is what switches the standing
	# order's attack on. A passive bot would have built its economy and then thrown its
	# army at you anyway.
	var w := _match_at(SimPlayer.AILevel.PASSIVE)
	_finish_the_script(w, 1)
	for i in range(60):
		w.step()
		assert_eq(_attackers(w, 1), 0, "passive attacked on tick %d" % (i + 1))


func test_the_placeholder_levels_are_wired_to_something() -> void:
	# They play as Easy. Asserting they PLAY is the honest test: asserting they are
	# identical to Easy would pin an implementation detail that 12.2b is going to
	# change, and asserting they are different would be a lie today.
	for level in [SimPlayer.AILevel.NORMAL, SimPlayer.AILevel.HARD,
			SimPlayer.AILevel.UNFAIR]:
		var w := _match_at(level)
		_run(w, 400)
		assert_true(_ai(w).step_of(1) > 0,
				"level %d runs the script rather than standing still" % level)


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
	assert_true(ai.step_of(1) > 0, "player 1 is a bot and has started its script")
	assert_eq(ai.step_of(2), 0, "player 2 is human and is left alone")


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
			w.tick, ai.step_of(1), w.player_for(1).stock, ", ".join(census),
			"\n            ".join(ai.log_lines())]


func test_it_puts_its_villagers_to_work() -> void:
	var w := _match()
	_run(w, 600)
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
			% [built, ai.step_of(1)])
	assert_true(w.player_for(1).age > 1 or w.player_for(1).is_advancing(),
			"reached or started age 2 (step %d)" % ai.step_of(1))


func test_it_gets_through_its_script_rather_than_stalling() -> void:
	# The timeouts doing their job. A step that cannot be satisfied on this map must be
	# abandoned, or the run sits on it forever -- which is the single most likely way
	# for this AI to be quietly useless.
	var w := _match()
	_run(w)
	var ai := _ai(w)
	var reached := ai.step_of(1)
	assert_true(reached >= 6, "reached step %d of %d in %d ticks:\n            %s"
			% [reached, AIPlaytest.SCRIPT.size(), RUN_TICKS,
			"\n            ".join(ai.log_lines())])


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
	var step := ai.step_of(1)
	_run(w, 300)
	assert_eq(ai.step_of(1), step, "it stopped where it was")


func test_the_script_is_data_and_every_step_carries_a_timeout() -> void:
	# The two rules 12.2a is built on, asserted against the script rather than trusted:
	# a step with no timeout is a step that can hang a whole match.
	assert_true(AIPlaytest.SCRIPT.size() > 10, "there is a real opening in there")
	for i in range(AIPlaytest.SCRIPT.size()):
		var step: Dictionary = AIPlaytest.SCRIPT[i]
		assert_true(step.has("do"), "step %d names a verb" % i)
		assert_true(int(step.get("timeout", 0)) > 0, "step %d has a timeout" % i)


func test_the_script_only_uses_verbs_the_interpreter_knows() -> void:
	# An unknown verb is skipped rather than fatal, which is the safe behaviour and also
	# how a typo would hide. This is what catches the typo.
	var known := ["gather", "build", "train", "advance_age", "attack"]
	for i in range(AIPlaytest.SCRIPT.size()):
		var verb := String((AIPlaytest.SCRIPT[i] as Dictionary).get("do", ""))
		assert_true(known.has(verb), "step %d: unknown verb %s" % [i, verb])


func test_every_def_id_the_script_names_exists() -> void:
	# A misspelled building is a step that can never complete and always times out --
	# it would look like a slow AI rather than a broken script.
	for i in range(AIPlaytest.SCRIPT.size()):
		var step: Dictionary = AIPlaytest.SCRIPT[i]
		if step.has("def"):
			assert_not_null(GameDataRegistry.building(step["def"]),
					"step %d builds %s" % [i, step["def"]])
		if step.has("unit"):
			assert_not_null(GameDataRegistry.unit(step["unit"]),
					"step %d trains %s" % [i, step["unit"]])
		if step.has("at"):
			assert_not_null(GameDataRegistry.building(step["at"]),
					"step %d trains at %s" % [i, step["at"]])
