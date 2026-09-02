## Phase 15.3: `ScenarioDef.build_config()` -- a scenario as a `MatchConfig`.
##
## PLAN.md 15.3 asks for this to be *"tested by asserting the config rather than by
## starting a match"*, which is what every test here does. Nothing below boots a world.
##
## ## THE TWO THINGS MOST WORTH PINNING
##
## **The positional arrays.** `player_ids`, `ai_players`, `ai_levels` and `teams` are
## position-for-position, and `SkirmishScreen.build_config`'s own comment records why a
## hole is dangerous rather than untidy: `MapGen.build_from` resolves a map's player index
## BY POSITION in `world.players`, so a short array hands somebody else's base to the wrong
## player. A length assertion is cheap and the failure it prevents is not.
##
## **`AIProfile.IDS` against `SimPlayer.AILevel`.** The conversion is `IDS.find(name)`, so
## the two are coupled by ORDER and neither file says so. That is the shape this project
## keeps paying for -- `colours.json`'s load-bearing order, the AI script's timeouts
## secretly calibrated against walking distance -- so the pairing is asserted BY NAME here.
## Reordering either list, or inserting a difficulty in the middle, fails this test instead
## of silently giving every scenario the wrong opponent.
extends TestCase


# ── the coupling nothing else declares ─────────────────────────────────────────

func test_ai_profile_ids_and_the_ai_level_enum_agree_position_for_position() -> void:
	# Asserted by NAME rather than by count, because two lists of five that disagree about
	# the middle three still have the same length. This is the guard `_ai_level_of`'s
	# comment points at -- the comment is not the guard, this is.
	assert_eq(AIProfile.IDS.size(), 5)
	assert_eq(AIProfile.IDS[SimPlayer.AILevel.PASSIVE], "passive")
	assert_eq(AIProfile.IDS[SimPlayer.AILevel.EASY], "easy")
	assert_eq(AIProfile.IDS[SimPlayer.AILevel.NORMAL], "normal")
	assert_eq(AIProfile.IDS[SimPlayer.AILevel.HARD], "hard")
	assert_eq(AIProfile.IDS[SimPlayer.AILevel.UNFAIR], "unfair")


func test_every_declared_ai_level_maps_to_its_own_enum_value() -> void:
	for level in AIProfile.IDS:
		var s := _scenario({"opponents": [level]})
		var problems: Array[String] = []
		var cfg := s.build_config(problems)
		assert_not_null(cfg, "%s should launch: %s" % [level, " | ".join(problems)])
		if cfg == null:
			continue
		assert_eq(cfg.ai_levels[1], AIProfile.IDS.find(level),
				"opponent '%s' must become its own AILevel" % level)


# ── the real scenario 3, which is the one that launches today ──────────────────

func test_the_shipped_scenario_three_builds_a_launchable_config() -> void:
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return

	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg, "scenario 3 needs no objective code: %s" % " | ".join(problems))
	if cfg == null:
		return
	assert_eq(problems, [] as Array[String])

	assert_eq(cfg.player_ids, [1, 2] as Array[int], "the human plus one Passive AI")
	assert_eq(cfg.ai_players, [false, true] as Array[bool])
	assert_eq(cfg.ai_levels[1], int(SimPlayer.AILevel.PASSIVE))
	assert_eq(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING)
	assert_eq(cfg.map_type, MapGenerator.Type.RIVER)
	assert_eq(cfg.seed, s.seed)
	assert_eq(cfg.starting_age, 1)


func test_the_map_travels_as_the_map_and_not_as_the_seed() -> void:
	# PLAN.md 11.7's second trap, and the half that IS fixed: FastNoiseLite's float maths
	# is not identical between an ARM phone and an x86 desktop, so a host and a client
	# regenerating from a shared seed can disagree about where the water is. The seed rides
	# along as provenance and the map is carried as data.
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg)
	if cfg == null:
		return

	assert_not_null(cfg.map_data, "a config with no map would regenerate on each client")
	assert_eq(cfg.map_size, cfg.map_data.size, "the map is the authority on its own size")
	assert_ne(cfg.seed, 0, "the seed survives as provenance")


func test_the_same_scenario_builds_the_same_map_twice() -> void:
	# ⚠️ **THIS NOW HOLDS FOR A STRONGER REASON THAN IT USED TO, and the old reason was the
	# weaker property this file could offer.** It used to say "the same seed and generator
	# must give the same map", and admitted it "does not make the seed portable across a
	# MapGenerator change". Since 2026-09-01 there is no generator on this path at all: the
	# map is READ FROM `map.png`, so it is identical across runs, across machines, across
	# CPU architectures and across every future change to `MapGenerator`. That is the whole
	# point of 2.4c and the reason the owner asked for a saved map.
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return
	var a: Array[String] = []
	var b: Array[String] = []
	var first := s.build_config(a)
	var second := s.build_config(b)
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.map_size, second.map_size)
	assert_eq(first.map_data.to_dict(), second.map_data.to_dict(),
			"the same file must give the same map")
	assert_eq(first.map_data.terrain, second.map_data.terrain, "byte for byte")


# ── the refusal that is waiting on 15.2 ────────────────────────────────────────

func test_the_two_scenario_mode_lessons_refuse_and_name_the_row_they_wait_for() -> void:
	# Not a defect: PLAN.md 15 says scenario 3 is playable at 15.1 + 15.3 + 15.5 and that
	# 15.2 is what unlocks scenarios 1 and 2. The refusal is the honest form of that.
	for folder in ["scenario_1", "scenario_2"]:
		var s := _shipped(folder)
		assert_not_null(s, folder)
		if s == null:
			continue
		assert_true(s.is_playable(), "%s is well formed -- it is the evaluator that is missing" % folder)

		var problems: Array[String] = []
		assert_null(s.build_config(problems), "%s cannot launch before 15.2" % folder)
		assert_eq(problems.size(), 1)
		assert_true(problems[0].contains("15.2"), problems[0])


func test_a_scenario_mode_refusal_never_silently_becomes_a_conquest_match() -> void:
	# The failure this guard exists for, stated as a test: mapping SCENARIO onto
	# LAST_MAN_STANDING would let killing the passive AI's five villagers win an economy
	# lesson with two villagers and no house -- decision 5's named failure, and the
	# scenario would teach the opposite of its name.
	var s := _scenario({
		"mode": "scenario",
		"objectives": [{"subject": "unit", "id": "unit.villager", "compare": ">=",
				"value": 10, "output": "win"}],
	})
	assert_true(s.is_playable())
	var problems: Array[String] = []
	assert_null(s.build_config(problems),
			"a scenario-mode lesson must refuse rather than launch as conquest")


# ── an unplayable scenario refuses, and says what the loader already knew ──────

func test_an_unplayable_scenario_refuses_and_forwards_its_own_problems() -> void:
	var s := _scenario({"map": {"type": "swamp", "seed": 1}})
	assert_false(s.is_playable())

	var problems: Array[String] = []
	assert_null(s.build_config(problems))
	assert_true(" | ".join(problems).contains("unknown map type"),
			"the loader's own complaint reaches the caller: %s" % " | ".join(problems))


func test_a_refusal_is_never_silent_even_with_nothing_to_report() -> void:
	# "It will not start and I do not know why" is the one outcome that costs an afternoon.
	# `is_playable()` is derived from `problems`, so an unplayable def with an empty list is
	# unreachable through `from_dict` -- this covers a def built by hand or by a future
	# editor, which is the only way to get there.
	var empty := ScenarioDef.new()
	empty.folder = "handmade"
	assert_eq(empty.problems_or_self().size(), 1, "never zero lines")
	assert_true(empty.problems_or_self()[0].contains("handmade"),
			"and the line names which scenario")

	# When there ARE problems, they are what comes back rather than the generic line.
	var real := _scenario({"map": {"type": "swamp", "seed": 1}})
	assert_eq(real.problems_or_self(), real.problems)


# ── the positional arrays, which are the dangerous part ───────────────────────

func test_every_positional_array_is_the_same_length_as_player_ids() -> void:
	# `MapGen.build_from` resolves a map's player index BY POSITION in `world.players`, so
	# a short array hands somebody else's base to the wrong player.
	# `count` is typed explicitly because a loop variable over an untyped literal array has
	# no set type, so `:=` on anything derived from it is a PARSE error rather than a
	# runtime one -- which is why the whole file failed to compile the first time.
	for count: int in [1, 3, 7]:
		var levels: Array = []
		for i in count:
			levels.append("passive")
		var cfg := _config(_scenario({"opponents": levels}))
		assert_not_null(cfg, "%d opponents should build" % count)
		if cfg == null:
			continue
		var n := count + 1
		assert_eq(cfg.player_ids.size(), n, "%d opponents plus the human" % count)
		assert_eq(cfg.ai_players.size(), n)
		assert_eq(cfg.ai_levels.size(), n)
		assert_eq(cfg.teams.size(), n)


func test_player_ids_are_compacted_from_one_with_no_gaps() -> void:
	# `Net` hands out the lowest free id to a joining peer, so a gap is not cosmetic.
	var cfg := _config(_scenario({"opponents": ["passive", "easy"]}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.player_ids, [1, 2, 3] as Array[int])
	assert_false(cfg.ai_players[0], "player 1 is the human")
	assert_true(cfg.ai_players[1])
	assert_true(cfg.ai_players[2])


func test_a_tutorial_is_a_free_for_all_and_zero_is_not_a_shared_team() -> void:
	# 0 is the ABSENCE of a team, not a team everybody shares -- `Diplomacy.allied` guards
	# it and `test_teams` asserts it by name. Two players both reading 0 are not allies,
	# which is what makes "the human against one bot" the right shape.
	var cfg := _config(_scenario({"opponents": ["passive"]}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.teams, [0, 0] as Array[int])
	# The table `SimWorld.setup` builds from those rows, asserted against the real
	# predicate rather than against the intent.
	assert_false(Diplomacy.allied(1, 2, {1: 0, 2: 0}), "0 against 0 must not be an alliance")


func test_colours_are_left_to_join_order_rather_than_copying_the_palette() -> void:
	# `colours.json`'s ORDER IS LOAD-BEARING -- saves and replays index into it -- so a
	# second copy of it here would be a second thing to keep in step. Empty is what
	# `MatchConfig.colours` documents as "derive from join order".
	var cfg := _config(_scenario({"opponents": ["passive"]}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.colours, [] as Array[int])


func test_a_scenario_carries_no_host_name() -> void:
	# A scenario is a solo match on loopback and there is no name field near it, so "nobody
	# typed one" is the truth. `LanBeacon.default_host_name()` is the lobby's fallback and
	# belongs there.
	var cfg := _config(_scenario({"opponents": ["passive"]}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.host_name, "")


func test_the_starting_age_reaches_the_config() -> void:
	# Scenario 2 is about advancing an age, so it cannot start in the age it asks you to
	# reach -- and `starting_age` is one number for everybody, so the opponent starts there
	# too.
	var cfg := _config(_scenario({"opponents": ["passive"], "starting_age": 3}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.starting_age, 3)


func test_the_config_survives_the_wire_the_way_a_hosted_match_would() -> void:
	# A scenario is hosted on loopback and every client builds its own world from these
	# bytes (PLAN.md 1.1 rule 4), so the config has to round-trip. Worth asserting here
	# rather than trusting `test_match_config_wire`: this is the first producer of a config
	# whose map was generated from a pinned seed.
	var cfg := _config(_scenario({"opponents": ["passive"]}))
	assert_not_null(cfg)
	if cfg == null:
		return

	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(cfg.to_dict())), OK)
	var back := MatchConfig.from_dict(json.data)
	assert_eq(back.player_ids, cfg.player_ids)
	assert_eq(back.ai_players, cfg.ai_players)
	assert_eq(back.ai_levels, cfg.ai_levels)
	assert_eq(back.teams, cfg.teams)
	assert_eq(back.mode, cfg.mode)
	assert_eq(back.seed, cfg.seed)
	assert_eq(back.map_type, cfg.map_type)
	assert_eq(back.starting_age, cfg.starting_age)
	assert_eq(back.map_size, cfg.map_size, "the map has to arrive, not be regenerated")


# ── helpers ────────────────────────────────────────────────────────────────────

## Where the synthetic scenarios below keep their saved map.
##
## `user://` AND NOT A SHIPPED FOLDER, deliberately: these tests are about
## `build_config`'s arithmetic — player ids, level mapping, array lengths — and borrowing
## `scenario_3`'s real map would tie every one of them to authored content that the owner
## is free to re-roll.
const _TEST_MAP_DIR := "user://test_scenario_maps/scenario_t"


## A minimal legal scenario, with `overrides` merged over it.
##
## ⚠️ **IT NEEDS A REAL SAVED MAP ON DISK NOW.** `build_config` stopped generating on
## 2026-09-01 (owner's ruling, PLAN.md 11.3): the saved `map.png` is the map and a scenario
## without one refuses to launch, on purpose, so that an unpinned scenario cannot ship
## looking exactly like a pinned one. A `dir_path` of `""` used to be harmless here and now
## means "no map", which would refuse every config these tests build.
func _scenario(overrides: Dictionary) -> ScenarioDef:
	var d: Dictionary = {
		"name": "T",
		"mode": "last_man_standing",
		"map": {"type": "river", "seed": 4242},
		"opponents": ["passive"],
	}
	d.merge(overrides, true)
	return ScenarioDef.from_dict("scenario_t", d, _ensure_test_map())


## A tiny map at `_TEST_MAP_DIR`, written once and reused.
##
## SMALL AND HAND-BUILT rather than generated: nothing here reads the terrain, and a 96×96
## `MapGenerator.generate` per test would put a real map's cost on eleven tests that only
## want a config to come back non-null.
func _ensure_test_map() -> String:
	if MapFile.exists_in(_TEST_MAP_DIR):
		return _TEST_MAP_DIR
	var data := MapData.create(Vector2i(16, 16), SimMap.Terrain.GRASS)
	var problems := MapFile.save(data, _TEST_MAP_DIR, {"name": "test", "players": 2})
	if not problems.is_empty():
		fail("could not write the test map: %s" % " | ".join(problems))
	return _TEST_MAP_DIR


func _config(s: ScenarioDef) -> MatchConfig:
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	if cfg == null and not problems.is_empty():
		fail("build_config refused: %s" % " | ".join(problems))
	return cfg


func _shipped(folder: String) -> ScenarioDef:
	for c in Campaigns.new().discover():
		if c.folder != "HowToPlay":
			continue
		for s in c.scenarios:
			if s.folder == folder:
				return s
	return null
