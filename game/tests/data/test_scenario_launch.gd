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


func test_a_conquest_mission_really_ends_when_the_opponent_is_gone() -> void:
	# 15.9's FOURTH CASE, and the only test in this file that builds a world rather than
	# inspecting a config. It is worth the cost for one reason: everything else here proves
	# scenario 3 *launches*, and a mission that launches and can never END is the exact
	# failure 15.2's notes warn about twice -- an inert `SCENARIO` member, and
	# `WinConditionSystem` deliberately never ending a match in a mode it does not implement.
	# From the player's chair "it cannot be won" and "nothing happens" are the same thing.
	#
	# `dev_preview/PreviewScenarioWin.tscn` drives all five this way and prints as it goes;
	# this pins the one that is a CONQUEST mission, so the suite fails rather than waiting
	# for somebody to run the preview.
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg, " | ".join(problems))
	if cfg == null:
		return

	# `setup` THEN `MapGen.build`, which is what `SimHost.build` does. Without the second
	# call there is no town centre and no starting villagers, so there would be nothing to
	# destroy and the match would be over for the wrong reason.
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	w.step()
	assert_false(w.match_over, "a mission is not decided on the tick it starts")

	var killed := 0
	for e in w.entities.values():
		if (e is SimUnit or e is SimBuilding) and e.owner_id == 2:
			e.alive = false
			killed += 1
	# THE GUARD THAT MAKES THE REST MEAN ANYTHING. If the saved map handed player 2 nothing,
	# every assertion below would pass on an opponent who was never there -- which is
	# `_world_is_populated`'s whole subject, and the shape `preview_garrison`'s header
	# records paying for: a measurement whose assertions were all true and worthless.
	assert_true(killed > 0, "the saved map must actually give the opponent something to lose")

	for i in range(30):
		w.step()
		if w.match_over:
			break
	assert_true(w.match_over, "conquest must end a last_man_standing mission")
	assert_eq(w.winner_id, 1, "and the human is who won it")
	assert_true(w.player_for(2).defeated)


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


# ── the two objective lessons, which launch as of 15.2 ─────────────────────────

func test_the_scenario_mode_lessons_launch_now_that_the_evaluator_exists() -> void:
	# This used to be `..._refuse_and_name_the_row_they_wait_for`, and the refusal was the
	# honest form of PLAN.md 15's build order: scenario 3 playable at 15.1 + 15.3 + 15.5,
	# with 15.2 unlocking the other two. 15.2 is built, so they start.
	#
	# SCENARIO 4 JOINED THEM ON 2026-09-06 and is the interesting one to have here: it is
	# the first `scenario`-mode mission whose rows are not about the player's own economy,
	# so it is the first that could be refused at load by a vocabulary gap (`owner: gaia`)
	# rather than by a typo. A scenario that will not launch is exactly what
	# `is_playable()` is for, and exactly what nothing else in this suite would notice.
	for folder in ["scenario_1", "scenario_2", "scenario_4"]:
		var s := _shipped(folder)
		assert_not_null(s, folder)
		if s == null:
			continue
		assert_true(s.is_playable(), folder)

		var problems: Array[String] = []
		var cfg := s.build_config(problems)
		assert_not_null(cfg, "%s must launch: %s" % [folder, " | ".join(problems)])
		if cfg == null:
			continue
		assert_eq(problems, [] as Array[String])
		assert_eq(cfg.mode, MatchConfig.Mode.SCENARIO,
				"%s is decided by its objectives, not by conquest" % folder)
		assert_false(cfg.objectives.is_empty(), "%s carries its win rows" % folder)
		assert_eq(cfg.objective_player_id, 1, "the human is the protagonist")


func test_a_scenario_mode_lesson_never_silently_becomes_a_conquest_match() -> void:
	# THE FAILURE THIS PINS IS STILL THE ONE THAT MATTERS, and it changed shape rather
	# than going away. Mapping SCENARIO onto LAST_MAN_STANDING would let killing the
	# passive AI's five villagers win an economy lesson with two villagers and no house --
	# decision 5's named failure, and the scenario would teach the opposite of its name.
	# The refusal used to be what prevented it; the MODE now is.
	var s := _scenario({
		"mode": "scenario",
		"objectives": [{"subject": "unit", "id": "unit.villager", "compare": ">=",
				"value": 10, "output": "win"}],
	})
	assert_true(s.is_playable())
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_ne(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING,
			"conquest must not be allowed to decide an objective scenario")
	assert_eq(cfg.mode, MatchConfig.Mode.SCENARIO)


func test_a_last_man_standing_scenario_carries_no_objectives_and_no_protagonist() -> void:
	# Scenario 3's shape. `ObjectiveSystem` does nothing outside SCENARIO mode, so these
	# two fields being empty is not what makes it safe -- but a config that carried
	# objectives it would never read is a config somebody would later "fix" by reading them.
	var cfg := _config(_scenario({"mode": "last_man_standing"}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING)
	assert_eq(cfg.objectives.size(), 0)
	assert_eq(cfg.objective_player_id, 0, "0 is nobody, which is every non-scenario match")


func test_every_shipped_scenario_carries_where_it_sits_in_its_campaign() -> void:
	# ⚠️ **15.7's WHOLE DEPENDENCY.** `GameScene` records a win against
	# `campaign_folder` + `scenario_index`, so a scenario that reached the match without
	# them would be a mission that plays, wins, and unlocks nothing -- which is exactly the
	# bug the owner reported, in a different disguise. Both are set by the LOADER, because
	# only it has read `campaign.json`'s order list.
	#
	# ASSERTED FOR ALL THREE, and by POSITION, because the index is what the completion
	# count is derived from: an off-by-one unlocks the wrong row or none.
	var campaign: CampaignDef = null
	for c in Campaigns.new().discover():
		if c.folder == "HowToPlay":
			campaign = c
	assert_not_null(campaign)
	if campaign == null:
		return

	for i in range(campaign.scenarios.size()):
		var s := campaign.scenarios[i]
		assert_eq(s.campaign_folder, "HowToPlay", "%s knows its campaign" % s.folder)
		assert_eq(s.index, i, "%s knows it is number %d" % [s.folder, i])

		var problems: Array[String] = []
		var cfg := s.build_config(problems)
		assert_not_null(cfg, "%s: %s" % [s.folder, " | ".join(problems)])
		if cfg == null:
			continue
		assert_eq(cfg.campaign_folder, "HowToPlay")
		assert_eq(cfg.scenario_index, i, "and it reaches the match")


func test_a_conquest_mission_still_carries_its_campaign_row() -> void:
	# Scenario 3 is `last_man_standing` and carries no objectives -- but it IS a campaign
	# mission and winning it must still unlock what follows. `objectives` and
	# `objective_player_id` are deliberately left empty for it; these two are deliberately
	# not, and the distinction is easy to get wrong in one `if`.
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return
	var cfg := _config(s)
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING)
	assert_eq(cfg.objectives.size(), 0, "no objectives")
	assert_eq(cfg.objective_player_id, 0, "and no protagonist")
	assert_eq(cfg.campaign_folder, "HowToPlay", "but it is still a campaign mission")
	assert_eq(cfg.scenario_index, 2)


func test_a_hand_built_scenario_carries_no_campaign_and_records_nothing() -> void:
	# A def built in a test or by a future editor. `""`/-1 is what
	# `CampaignProgress.record_completed` refuses, so a match like this cannot write
	# progress for a campaign it is not part of.
	var cfg := _config(_scenario({"opponents": ["passive"]}))
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.campaign_folder, "")
	assert_eq(cfg.scenario_index, -1, "-1 and not 0, because 0 is a real scenario index")
	assert_false(CampaignProgress.record_completed(cfg.campaign_folder, cfg.scenario_index,
			"user://test_scenario_launch/should_never_exist.json"))


func test_the_briefing_reaches_the_config_because_the_hud_has_never_heard_of_a_campaign() -> void:
	# 15.6's modal reads `MatchConfig.scenario_message`, not `ScenarioDef.message`: the
	# message field is shared with skirmish by the owner's spec, so it belongs to the match
	# HUD. Provenance like `host_name` -- nothing in the sim reads it.
	var s := _shipped("scenario_1")
	assert_not_null(s)
	if s == null:
		return
	var cfg := _config(s)
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_eq(cfg.scenario_message, s.message)
	assert_false(cfg.scenario_message.is_empty(), "a scenario explains itself before tick 1")


# ── a map that was AUTHORED rather than generated has no seed (16.8) ──────────

## ⛔ **THE SEED REQUIREMENT PREDATES THE MAP BEING A FILE.**
##
## When `_read_map`'s refusal was written the seed WAS the map: `build_config()` generated from it
## at launch, so a scenario without one really did regenerate its ground every run. The owner's
## ruling of 2026-09-01 ended that — *"generating is a one-off authoring step"* — and since then
## the saved `map.png` beside the file has been the map. A thing that can no longer happen was
## still being refused, and it blocked the first scenario the MapMaker ever wrote (16.8), because
## a map authored by hand has no generator seed to record.
##
## ⚠️ **THE ALTERNATIVE WAS WORSE THAN A RELAXED RULE**: the export's only other option is to write
## `"seed": 0` into every authored scenario — a field that reads as provenance, is not, and would
## be believed by the next person to open the file.
func test_a_scenario_with_a_saved_map_and_no_seed_is_playable() -> void:
	var s := _scenario({"map": {}})
	assert_true(s.is_playable(), "%s" % [s.problems])
	var cfg := _config(s)
	assert_not_null(cfg)
	if cfg == null:
		return
	assert_not_null(cfg.map_data, "the saved map is still what travels")
	assert_eq(cfg.seed, 0, "and nothing pretends there was a seed")


## ⚠️ **NOTHING THAT USED TO BE CAUGHT STOPS BEING CAUGHT.** The complaint survives for the case it
## was written about — a scenario with neither a seed nor a map — and the check that answers it is
## the one that can actually see the difference.
func test_a_scenario_with_neither_a_seed_nor_a_map_still_complains() -> void:
	var s := ScenarioDef.from_dict("homeless", {
		"name": "T", "map": {}, "opponents": ["passive"],
	}, "user://test_scenario_launch_nowhere")
	assert_false(s.is_playable())
	assert_true(" | ".join(s.problems).contains("no 'seed'"), "%s" % [s.problems])


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


func test_the_objective_list_survives_the_wire_field_by_field() -> void:
	# ⚠️ **AN OBJECTIVE THAT DOES NOT SURVIVE THE WIRE IS A RULE TWO CLIENTS CAN DISAGREE
	# ABOUT**, and they would disagree about whether the match has been WON -- the one
	# question the match was asked. Asserted field by field rather than by comparing
	# dictionaries, because a dictionary comparison passes when BOTH sides lost the same key.
	#
	# SCENARIO 1, because it is the one whose rows carry an `id`. JSON has no StringName, so
	# `unit.villager` comes back a String and `&"unit.villager" == "unit.villager"` is
	# FALSE; `from_wire` converts at the boundary and this is what would catch it if it
	# stopped, since the row would silently count a def nobody owns. Scenario 2's single
	# `age` row names no id and would assert nothing about that.
	var s := _shipped("scenario_1")
	assert_not_null(s)
	if s == null:
		return
	var cfg := _config(s)
	assert_not_null(cfg)
	if cfg == null:
		return

	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(cfg.to_dict())), OK)
	var back := MatchConfig.from_dict(json.data)

	assert_eq(back.mode, MatchConfig.Mode.SCENARIO)
	assert_eq(back.objective_player_id, cfg.objective_player_id)
	assert_eq(back.scenario_message, cfg.scenario_message)
	assert_eq(back.campaign_folder, cfg.campaign_folder)
	assert_eq(back.scenario_index, cfg.scenario_index)
	assert_eq(back.objectives.size(), cfg.objectives.size())
	for i in range(cfg.objectives.size()):
		var sent: ObjectiveDef = cfg.objectives[i]
		var got: ObjectiveDef = back.objectives[i]
		assert_eq(got.subject, sent.subject, "row %d subject" % i)
		# A StringName through JSON comes back a String, and `&"food" == "food"` is FALSE
		# -- `from_wire` converts at the boundary, and this is what would catch it if it
		# stopped: the row would silently count a resource nobody holds.
		assert_eq(got.id, sent.id, "row %d id" % i)
		assert_eq(typeof(got.id), TYPE_STRING_NAME, "row %d id stays a StringName" % i)
		assert_eq(got.owner, sent.owner, "row %d owner" % i)
		assert_eq(got.owner_index, sent.owner_index, "row %d owner_index" % i)
		assert_eq(got.compare, sent.compare, "row %d compare" % i)
		assert_eq(got.value, sent.value, "row %d value" % i)
		assert_eq(got.output, sent.output, "row %d output" % i)
		assert_eq(got.text, sent.text, "row %d text" % i)
		# 16.5's field. Empty on every shipped row today, which is exactly the case a
		# dictionary comparison would pass on while both sides had lost the key.
		assert_eq(got.area, sent.area, "row %d area" % i)
		assert_eq(typeof(got.area), TYPE_STRING_NAME, "row %d area stays a StringName" % i)


# ── areas: the one check that needs the scenario AND its map (PLAN.md 16.5) ────

## ⛔ **A MISSPELLED REGION IS AN UNWINNABLE SCENARIO WHOSE ONLY SYMPTOM IS THAT NOTHING
## HAPPENS**, and this is the refusal that says so. `ObjectiveDef` parses on the front door's
## thread and has never seen a map, so `build_config()` is the first moment both halves exist —
## the objectives are parsed and `map_data()` has just come back off disk.
##
## Decision 4 of PLAN.md 15 is the rule: *a malformed objective list must make the scenario
## refuse to start, not start and evaluate to true on tick 1.*
func test_an_objective_naming_a_region_the_map_has_not_got_refuses_to_launch() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "area", "area": "north_pass", "compare": ">=", "value": 1,
			"output": "win"},
	]})
	assert_true(s.is_playable(), "the row itself parses: %s" % [s.problems])

	var problems: Array[String] = []
	assert_null(s.build_config(problems), "a region that does not exist must not launch")
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("north_pass"), problems[0])
	# ⚠️ **AND IT SAYS WHAT THE MAP DOES HAVE, because the fault is almost always a spelling and
	# the fix is almost always in the other file.** A bare "unknown area" leaves an author
	# opening the map in MapMaker to find out what they called it.
	assert_true(problems[0].contains("no regions at all"),
			"the empty case is worded apart: %s" % problems[0])


func test_the_refusal_names_the_regions_the_map_really_declares() -> void:
	var dir := _map_with_regions([&"ford", &"the hill"])
	var s := ScenarioDef.from_dict("scenario_r", {
		"name": "R", "mode": "scenario", "map": {"type": "river", "seed": 1},
		"opponents": ["passive"],
		"objectives": [{"subject": "area", "area": "fjord", "compare": ">=", "value": 1,
			"output": "win"}],
	}, dir)
	var problems: Array[String] = []
	assert_null(s.build_config(problems))
	assert_true(problems[0].contains("ford"), problems[0])
	assert_true(problems[0].contains("the hill"), problems[0])


func test_a_region_the_map_does_declare_launches_and_reaches_the_config() -> void:
	var dir := _map_with_regions([&"ford"])
	var s := ScenarioDef.from_dict("scenario_r", {
		"name": "R", "mode": "scenario", "map": {"type": "river", "seed": 1},
		"opponents": ["passive"],
		"objectives": [{"subject": "area", "area": "ford", "compare": ">=", "value": 1,
			"output": "win"}],
	}, dir)
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg, "%s" % [problems])
	if cfg == null:
		return
	assert_eq(cfg.objectives[0].area, &"ford")
	# THE MAP TRAVELS WITH ITS REGIONS, which is what `MapGen.build_from()` turns into
	# `SimWorld.areas` on every client -- so a joining peer resolves the same name to the same
	# rectangles rather than building a world the host's objective cannot be evaluated against.
	assert_true(cfg.map_data.has_area(&"ford"))


## ⛔ **THE REAL ROW, FROM THE REAL PLAYTEST** (board `16.x-unknown-def-id`). Owner,
## 2026-09-20: `{"subject": "unit", "id": "SirRoland", "compare": "==", "value": 0, "output":
## "lose"}`, meaning `named_unit` / `"Sir Roland"`. It parsed, it launched, and `_sum` counted
## a def the game has never had as **0** — so the mission was lost on tick 1.
##
## The sim answers -1 for it now, which makes the row inert rather than fatal. This is the
## half that refuses it outright, at the only moment there is somebody to tell.
func test_an_objective_naming_a_def_id_the_game_has_not_got_refuses_to_launch() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "unit", "id": "SirRoland", "compare": "==", "value": 0,
			"output": "lose"},
		{"subject": "unit", "compare": ">=", "value": 1, "output": "win"},
	]})
	assert_true(s.is_playable(), "the row itself parses: %s" % [s.problems])

	var problems: Array[String] = []
	assert_null(s.build_config(problems), "a def id that does not exist must not launch")
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true(problems[0].contains("SirRoland"), problems[0])


## ⚠️ **AND IT NAMES THE MISTAKE'S SHAPE, which is the sentence that would have ended the
## playtest in one read.** Every def id in the game is `kind.name`, so an id with no dot is not
## a near miss — it is a hero's name in the wrong field. `ObjectiveDef._read_clock` is the
## precedent: refuse by naming the spelling that was meant, not by saying no.
##
## ⚠️ The win row is not padding: a `scenario` with no win row is refused by an EARLIER check
## for being unwinnable, and the first draft of this test tripped that instead -- reporting
## "no win objective" and asserting nothing about def ids at all.
func test_the_refusal_suggests_named_unit_when_the_id_has_no_dot_in_it() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "unit", "id": "SirRoland", "compare": "==", "value": 0,
			"output": "lose"},
		{"subject": "unit", "compare": ">=", "value": 1, "output": "win"},
	]})
	var problems: Array[String] = []
	assert_null(s.build_config(problems))
	assert_true(problems[0].contains("named_unit"),
			"it points at the subject they meant: %s" % problems[0])


## ...and does NOT, for an id that IS shaped like a def id. `unit.vilager` is a typo, not a
## hero; telling that author about `named_unit` would send them the wrong way entirely.
func test_a_misspelled_def_id_is_refused_without_the_named_unit_hint() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "unit", "id": "unit.vilager", "compare": ">=", "value": 1,
			"output": "win"},
	]})
	var problems: Array[String] = []
	assert_null(s.build_config(problems))
	assert_true(problems[0].contains("unit.vilager"), problems[0])
	assert_false(problems[0].contains("named_unit"),
			"a dotted id is a spelling mistake, not a wrong subject: %s" % problems[0])


func test_a_def_id_the_game_does_have_launches_and_reaches_the_config() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "building", "id": "building.town_center", "compare": ">=", "value": 1,
			"output": "win"},
	]})
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	assert_not_null(cfg, "%s" % [problems])
	if cfg != null:
		assert_eq(cfg.objectives[0].id, &"building.town_center")


## ⚠️ **AN EMPTY `id` IS LEGAL AND MUST STILL LAUNCH.** It means "any of that subject", which
## is how PLAN.md 11.8's *leave the enemy nothing* is written -- and it is in shipped campaign
## files, so a refusal that caught it would break the front door for existing content.
func test_an_objective_with_no_def_id_at_all_still_launches() -> void:
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "unit", "owner": "enemy", "compare": "==", "value": 0, "output": "win"},
	]})
	var problems: Array[String] = []
	assert_not_null(s.build_config(problems), "%s" % [problems])


## ⛔ **EVERY SHIPPED SCENARIO STILL LAUNCHES.** The refusal above is new, and a refusal is the
## one kind of check that can break content that was working -- so the campaigns on disk are
## walked rather than assumed. This is the test that would have caught it had `SirRoland`'s own
## scenario still been in the tree.
func test_no_shipped_scenario_names_a_def_id_that_does_not_exist() -> void:
	var campaigns := Campaigns.new().discover()
	assert_false(campaigns.is_empty(), "there is shipped content to check")
	for campaign in campaigns:
		for scenario in campaign.scenarios:
			var bad := scenario._unknown_def_ids()
			assert_true(bad.is_empty(),
					"%s/%s: %s" % [campaign.folder, scenario.folder, " | ".join(bad)])


## ⛔ **A REFUSAL HAS TO FIT THE BANNER IT IS SHOWN IN, and this is the seam where that gets
## forgotten.** The sentence is written here in `ScenarioDef`; it is drawn by `NoticeToast` on
## another screen, by code that has never read this file. The owner photographed the result on
## 2026-09-21: the def-id refusal printed straight through the gold moulding and over the
## scenario list behind it, because `show_message` draws one line and does not resize.
##
## `ScenarioScreen._say` routes anything past `_SHORT_NOTICE_CHARS` to the paragraph banner, so
## what this pins is the PAIR: the message must be long enough to take that route, and short
## enough to fit when it gets there. A refusal reworded down to 55 characters would silently go
## back to the one-line banner; one grown past the paragraph budget would clip instead of
## overflowing, which looks tidier and is just as unreadable.
func test_a_refusal_is_sized_for_the_banner_that_has_to_draw_it() -> void:
	# ~5 lines of 16 px in the paragraph banner's ~460 px dark field. Stated here rather than
	# in `NoticeToast` because it is a fact about MESSAGES, and this is the file that writes
	# the longest one.
	const PARAGRAPH_BUDGET := 275
	var s := _scenario({"mode": "scenario", "objectives": [
		{"subject": "unit", "id": "SirRoland", "compare": "==", "value": 0,
			"output": "lose"},
		{"subject": "unit", "compare": ">=", "value": 1, "output": "win"},
	]})
	var problems: Array[String] = []
	assert_null(s.build_config(problems))
	assert_false(problems.is_empty())

	var why: String = problems[0]
	assert_true(why.length() > ScenarioScreen._SHORT_NOTICE_CHARS,
			"a refusal is a paragraph and must take the paragraph banner (%d chars): %s"
			% [why.length(), why])
	assert_true(why.length() <= PARAGRAPH_BUDGET,
			"and must still fit inside it (%d chars): %s" % [why.length(), why])


## A saved map under `user://` carrying `names` as one-tile regions. Written fresh per call
## because the region list is what varies; `_ensure_test_map()`'s cached map has none.
func _map_with_regions(names: Array[StringName]) -> String:
	var dir := "user://test_scenario_maps/scenario_r_%d" % names.size()
	var data := MapData.create(Vector2i(16, 16), SimMap.Terrain.GRASS)
	for i in names.size():
		data.add_area(names[i], Rect2i(i, i, 2, 2))
	var problems := MapFile.save(data, dir, {"name": "regions", "players": 2})
	if not problems.is_empty():
		fail("could not write the region map: %s" % " | ".join(problems))
	return dir


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
