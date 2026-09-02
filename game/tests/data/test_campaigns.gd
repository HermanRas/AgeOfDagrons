## Phase 15.1: the scenario/campaign schema and the loader that walks PLAN.md 3.3's
## root list.
##
## ## WHAT THIS SUITE IS ACTUALLY FOR
##
## Decision 4 of PLAN.md 15 is the thing worth testing here: **a malformed objective list
## must make the scenario refuse to start, not start and evaluate to true on tick 1.**
## `_trophy()`'s note is the precedent -- *"you lose when your trophy dies"* on a map with
## no trophies defeats everybody immediately. So most of what follows asserts a REFUSAL,
## and each refusal is asserted by the problem it reports rather than by a count, because
## "it complained about something" is not the same as "it complained about the right
## thing".
##
## The unimplemented subjects matter most. `area`, `named_unit` and `ticks` cannot be
## evaluated yet, and **`== 0` is a comparison an unimplemented subject PASSES** -- so a
## subject that silently counted zero would announce victory on tick 1 of an unwinnable
## scenario. That is the failure these tests exist for.
##
## ## IT WRITES REAL FIXTURES INTO `user://content/scenarios/`
##
## Two things cannot be tested any other way, and both have bitten this project in other
## forms: that the loader reads the SECOND root at all, and that campaign order comes from
## `campaign.json` rather than from sorting folder names (`scenario_10` sorts before
## `scenario_2`). `after_each` removes them; a leftover fixture would shadow the real
## campaign in the editor, so the cleanup is not politeness.
extends TestCase

const _FIXTURE_ROOT := "user://content/scenarios/"
const _ORDER_FIXTURE := "ZZOrderFixture"

## Deliberately the real campaign's name: the shadowing test needs a folder that exists in
## BOTH roots, and using a made-up name would prove nothing about first-match-wins.
const _SHADOW_FIXTURE := "HowToPlay"


func after_each() -> void:
	for folder in [_ORDER_FIXTURE, _SHADOW_FIXTURE]:
		_rm_rf(_FIXTURE_ROOT.path_join(folder))


# ── the roots, and the gate that keeps the dev override out of a release ────────

func test_the_dev_override_comes_first_and_the_user_root_is_always_present() -> void:
	var c := Campaigns.new()
	var roots := c.roots()

	# True for editor runs, this headless suite and every dev_preview scene; false in an
	# exported build. If this assertion ever fails, the override is not the thing that
	# broke -- the gate is -- and PLAN.md 3.3's safety argument rests entirely on it.
	assert_true(OS.has_feature("editor"), "the headless suite should report the editor feature")

	assert_eq(roots.size(), 2, "editor runs see the override and the user root")
	assert_true(roots[0].ends_with("scenarios"), "the dev override is first: %s" % roots[0])
	assert_eq(roots[1], Campaigns.USER_ROOT, "the user root is the fallback")


func test_the_dev_override_is_the_repo_folder_beside_the_godot_project() -> void:
	# Derived rather than configured, so a fresh clone needs no setup step. The one thing
	# worth pinning is that it resolves the `..` -- a path with a `..` still in it works
	# for DirAccess but is unreadable in a warning, which is where it will be seen.
	var root := Campaigns.new().roots()[0]
	assert_false(root.contains(".."), "the override path is simplified: %s" % root)
	assert_true(DirAccess.dir_exists_absolute(root), "the repo's scenarios/ exists at %s" % root)


# ── the real campaign ───────────────────────────────────────────────────────────

func test_how_to_play_loads_with_its_three_scenarios_in_declared_order() -> void:
	var c := Campaigns.new()
	var found := _by_folder(c.discover())

	assert_true(found.has("HowToPlay"), "the repo's own campaign is discovered")
	var campaign: CampaignDef = found["HowToPlay"]
	assert_eq(campaign.name, "How To Play")
	# THE ORDER, which is what this test is for -- not the LENGTH, which is just how much
	# content the owner has written today (three on 2026-09-01, five on 2026-09-02). The
	# first three are asserted by name because `campaign.json`'s order is a design decision
	# that cannot be derived from the folder names.
	assert_true(campaign.scenarios.size() >= 3)
	assert_eq(campaign.scenarios[0].folder, "scenario_1")
	assert_eq(campaign.scenarios[1].folder, "scenario_2")
	assert_eq(campaign.scenarios[2].folder, "scenario_3")


func test_the_real_campaign_has_no_problems_at_all() -> void:
	# The one assertion that would catch a typo anywhere in the four shipped JSON files,
	# and the reason it prints the problems rather than a count: a failure here should
	# tell you what to fix without a second run.
	var c := Campaigns.new()
	var found := _by_folder(c.discover())
	var campaign: CampaignDef = found.get("HowToPlay")
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.all_problems(), [] as Array[String],
			"HowToPlay should load clean: %s" % ", ".join(campaign.all_problems()))
	assert_true(campaign.is_playable())
	assert_eq(campaign.playable_scenarios().size(), campaign.scenarios.size(),
			"EVERY shipped scenario is playable, not merely some of them -- which is the"
			+ " assertion a hardcoded count was quietly weakening as content was added")


func test_the_campaign_art_resolves_to_paths_and_is_never_loaded_here() -> void:
	# Paths and not textures: these PNGs are outside res://, have no .import sidecar, and
	# load() cannot open them at all. 15.5 goes through Image.load() when a campaign is
	# OPENED, because the background is 1920x1080 and costs a real decode.
	var campaign: CampaignDef = _by_folder(Campaigns.new().discover()).get("HowToPlay")
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_true(campaign.icon_path.ends_with(CampaignDef.ICON_FILE))
	assert_true(campaign.background_path.ends_with(CampaignDef.BACKGROUND_FILE))
	assert_true(FileAccess.file_exists(campaign.background_path))
	for s in campaign.scenarios:
		assert_true(s.icon_path.ends_with(ScenarioDef.ICON_FILE), "%s has an icon" % s.folder)


func test_scenario_one_is_two_win_rows_that_are_anded() -> void:
	var s := _shipped("scenario_1")
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.mode, ScenarioDef.Mode.SCENARIO)
	assert_eq(s.map_type, MapGenerator.Type.RIVER)
	assert_eq(s.opponents, [&"passive"] as Array[StringName])
	assert_eq(s.starting_age, 1)

	var wins := s.win_objectives()
	assert_eq(wins.size(), 2, "a house AND fourteen villagers is one objective in two halves")
	assert_eq(wins[0].subject, ObjectiveDef.Subject.BUILDING)
	assert_eq(wins[0].id, &"building.house")
	assert_eq(wins[0].value, 1)
	assert_eq(wins[1].subject, ObjectiveDef.Subject.UNIT)
	assert_eq(wins[1].id, &"unit.villager")
	assert_eq(wins[1].value, 14,
			"the owner's target -- 15 first, corrected to 14 the same day once the scout in"
			+ " the population cap was accounted for")
	assert_eq(wins[1].compare, ObjectiveDef.Compare.AT_LEAST)


func test_scenario_ones_villager_target_needs_exactly_the_one_house_it_asks_for() -> void:
	# ⚠️ **THIS TEST HAS NOW ASSERTED ALL THREE OF: one house, two houses, and one house
	# again — and the third time it is derived rather than assumed.** Worth the whole story,
	# because the failure repeated itself:
	#
	# It first claimed **15 villagers needs exactly one house**, from "town centre 10 +
	# house 5 = 15", and PASSED, because the arithmetic left out a unit. The saved map
	# grants five villagers AND one `unit.scout_cavalry`, so the opening
	# population is 6/10 and fifteen villagers plus that scout is SIXTEEN. The owner played
	# to a dead stop at 15/15 with fourteen villagers and a scout. It was then rewritten to
	# assert TWO houses, and the owner corrected the content instead: *"i did not account
	# for the scout in the pop cap, resuting in the player needing a second house"* — target
	# 14. Which makes one house exactly right again, for a reason that is now checked.
	#
	# **The lesson is the derivation, not the number.** This reads the STARTING ENTITIES OFF
	# THE MAP and computes the houses needed, so moving the target or removing the scout
	# fails here rather than quietly turning the briefing text into a lie — which is exactly
	# what happened twice.
	var s := _shipped("scenario_1")
	assert_not_null(s)
	if s == null:
		return
	var tc: BuildingDef = GameDataRegistry.building(&"building.town_center")
	var house: BuildingDef = GameDataRegistry.building(&"building.house")
	assert_not_null(tc)
	assert_not_null(house)
	if tc == null or house == null:
		return

	var target := 0
	for o in s.win_objectives():
		if o.id == &"unit.villager":
			target = o.value
	assert_true(target > 0, "scenario 1 has a villager target")

	# What the map actually hands player 1, by def id, and what it costs in population.
	var problems: Array[String] = []
	var data := s.map_data(problems)
	assert_not_null(data, " | ".join(problems))
	if data == null:
		return
	var start_villagers := 0
	var other_pop := 0
	for e in data.entities:
		if int(e.get("player", 0)) != 1:
			continue
		var def_id := StringName(str(e.get("def_id", "")))
		var ud: UnitDef = GameDataRegistry.unit(def_id)
		if ud == null:
			continue                      # a building; its pop is provided, not consumed
		if def_id == &"unit.villager":
			start_villagers += 1
		else:
			other_pop += ud.pop_cost

	assert_true(target > start_villagers,
			"a target within the %d villagers the map already grants is won on tick 0"
			% start_villagers)
	assert_true(other_pop > 0,
			"the map grants a non-villager starting unit -- the scout, which is the whole"
			+ " reason the target is 14 and not 15")

	# ceil((target + other_pop - tc_pop) / house_pop), spelled out rather than with a float
	# division: the sim carries no floats and neither should the arithmetic about it.
	var short_by := target + other_pop - tc.provides_pop
	var houses := (short_by + house.provides_pop - 1) / house.provides_pop
	assert_eq(houses, 1,
			"%d villagers plus %d population of other starting units against a %d town"
			% [target, other_pop, tc.provides_pop]
			+ " centre needs %d house(s) of %d -- the objective asks for ONE, and the"
			% [houses, house.provides_pop]
			+ " briefing tells the player that one is exactly enough")
	# AND THE HOUSE IS NOT SPARE ROOM: one fewer would not do it. This is the half that
	# makes the two win rows depend on each other instead of merely sitting side by side.
	assert_true(target + other_pop > tc.provides_pop,
			"the target must not fit inside the town centre's own %d population, or the"
			% tc.provides_pop + " build row is decoration")


func test_scenario_ones_villager_target_is_above_what_the_map_gives_you() -> void:
	# A target of 5 would be a scenario won on tick 0, because MapGen starts every player
	# with 5 villagers -- it would teach nothing while every assertion about it passed.
	# Derived from the objective rather than written as a literal, so a balance change to
	# the starting villagers fails this instead of silently making the lesson trivial.
	var s := _shipped("scenario_1")
	assert_not_null(s)
	if s == null:
		return
	for o in s.win_objectives():
		if o.id == &"unit.villager":
			assert_true(o.value > 5, "the target must exceed the 5 villagers MapGen grants")


func test_scenario_two_counts_an_age_and_names_no_id() -> void:
	var s := _shipped("scenario_2")
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.mode, ScenarioDef.Mode.SCENARIO)
	var wins := s.win_objectives()
	# ⚠️ **ONE ROW, AND IT WAS BRIEFLY TWO** (owner, 2026-09-02: *"500 food is not a wining
	# objective or tracked items, its purely user guidance"*). A `resource` row asking for
	# 500 food shipped for a few hours and was withdrawn; the number stays in the briefing,
	# because 500 food is exactly what advancing costs and the counter climbing to it is
	# the visible half of a goal that otherwise shows nothing for minutes.
	assert_eq(wins.size(), 1, "the age is the only tracked objective")
	assert_eq(wins[0].subject, ObjectiveDef.Subject.AGE)
	assert_true(wins[0].id.is_empty(), "an age counts no entities, so it names no id")
	assert_eq(wins[0].value, 2, "ages are indexed from 1, so >= 2 is 'has advanced once'")


func test_scenario_twos_briefing_still_names_the_food_the_advance_costs() -> void:
	# The 500 in the message is not decoration and not an objective: it is the AGE COST,
	# so a balance change to `ages.json` would make the briefing tell the player to watch
	# for the wrong number. That is a lie a test can catch and a playtest probably would
	# not -- the player would simply wait at 500 and find the button still refused.
	var s := _shipped("scenario_2")
	assert_not_null(s)
	if s == null:
		return
	var target_age := 0
	for o in s.win_objectives():
		if o.subject == ObjectiveDef.Subject.AGE:
			target_age = o.value
	assert_true(target_age > 1, "there is an age to advance to")

	var next: AgeDef = GameDataRegistry.age(target_age)
	assert_not_null(next, "age %d is in ages.json" % target_age)
	if next == null:
		return
	var food := int(next.cost.get(&"food", 0))
	assert_true(food > 0, "advancing costs food")
	assert_true(s.message.contains(str(food)),
			"the briefing tells the player to watch for %d food, which is what age %d costs"
			% [food, target_age])


func test_scenario_three_wins_by_conquest_and_declares_nothing() -> void:
	# The whole point of scenario 3: it needs no objective code, so it is playable at
	# 15.1 + 15.3 + 15.5 and proves the launch path on its own.
	var s := _shipped("scenario_3")
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.mode, ScenarioDef.Mode.LAST_MAN_STANDING)
	assert_eq(s.objectives.size(), 0)
	assert_true(s.is_playable())


func test_every_shipped_scenario_pins_a_seed_and_a_message() -> void:
	for folder in ["scenario_1", "scenario_2", "scenario_3"]:
		var s := _shipped(folder)
		assert_not_null(s, folder)
		if s == null:
			continue
		assert_ne(s.seed, 0, "%s pins a seed" % folder)
		assert_false(s.message.is_empty(), "%s explains itself on load" % folder)
		assert_false(s.description.is_empty(), "%s has a description for the screen" % folder)


# ── the three subjects that must be REFUSED, not defaulted ──────────────────────

func test_area_named_unit_and_ticks_are_refused_and_say_what_they_are_waiting_for() -> void:
	# The most important test in this file. `== 0` is a comparison an unimplemented
	# subject PASSES, so a subject that silently counted zero would announce victory on
	# tick 1 of a scenario nobody could win.
	for subject in ["area", "named_unit", "ticks"]:
		var problems: Array[String] = []
		var o := ObjectiveDef.from_dict(
				{"subject": subject, "compare": "==", "value": 0, "output": "win"}, problems)
		assert_null(o, "'%s' must not parse into an evaluable objective" % subject)
		assert_eq(problems.size(), 1, "'%s' reports exactly one reason" % subject)
		assert_true(problems[0].contains("not evaluable yet"),
				"'%s' says it is unbuilt rather than unknown: %s" % [subject, problems[0]])


func test_an_unknown_subject_reads_as_a_typo_and_not_as_unbuilt() -> void:
	# The distinction is the point: "not built yet" and "you misspelled it" want
	# different reactions from whoever reads the log.
	var problems: Array[String] = []
	assert_null(ObjectiveDef.from_dict(
			{"subject": "bulding", "value": 1}, problems))
	assert_true(problems[0].contains("unknown subject"), problems[0])
	assert_false(problems[0].contains("not evaluable yet"), problems[0])


# ── the rest of the objective vocabulary ────────────────────────────────────────

func test_an_objective_refuses_every_malformed_field_and_names_it() -> void:
	var cases := {
		"unknown compare": {"subject": "unit", "compare": ">", "value": 1},
		"unknown output": {"subject": "unit", "compare": ">=", "value": 1, "output": "yes"},
		"unknown owner": {"subject": "unit", "owner": "them", "compare": ">=", "value": 1},
		"objective has no 'value'": {"subject": "unit", "compare": ">="},
		"negative value": {"subject": "unit", "compare": ">=", "value": -3},
		"counts no entities": {"subject": "age", "id": "unit.villager", "compare": ">=",
				"value": 2},
		"is not a player": {"subject": "unit", "owner": 0, "compare": ">=", "value": 1},
	}
	for expected in cases:
		var problems: Array[String] = []
		var o := ObjectiveDef.from_dict(cases[expected], problems)
		assert_null(o, "should refuse: %s" % expected)
		assert_eq(problems.size(), 1, "one reason for %s" % expected)
		assert_true(problems[0].contains(expected),
				"expected a problem naming '%s', got '%s'" % [expected, problems[0]])


func test_an_owner_may_be_a_name_or_a_player_number_and_the_type_survives() -> void:
	# An INT ("player 3") and a NAME ("enemy") are both legal and mean different things,
	# so the type is load-bearing -- the same distinction AIProfile._rule_from makes.
	var problems: Array[String] = []
	var named := ObjectiveDef.from_dict(
			{"subject": "unit", "owner": "enemy", "compare": "==", "value": 0}, problems)
	assert_not_null(named)
	assert_eq(named.owner, ObjectiveDef.Owner.ENEMY)

	var indexed := ObjectiveDef.from_dict(
			{"subject": "unit", "owner": 3, "compare": ">=", "value": 1}, problems)
	assert_not_null(indexed)
	assert_eq(indexed.owner, ObjectiveDef.Owner.INDEX)
	assert_eq(indexed.owner_index, 3)
	assert_eq(problems, [] as Array[String])


func test_an_id_less_row_means_any_of_that_subject() -> void:
	# PLAN.md 11.8's own example of "leave the enemy nothing" carries no id, so absent
	# has to be legal rather than a missing field.
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict(
			{"subject": "unit", "owner": "enemy", "compare": "==", "value": 0}, problems)
	assert_not_null(o)
	assert_true(o.id.is_empty())
	assert_eq(problems, [] as Array[String])


func test_a_value_arriving_as_a_json_float_becomes_an_int() -> void:
	# JSON has no ints; every number arrives as a float, and an unrounded float in a
	# victory rule is a rule two CPUs can disagree about (market.json's rule).
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict(
			{"subject": "unit", "compare": ">=", "value": 10.0}, problems)
	assert_not_null(o)
	assert_eq(typeof(o.value), TYPE_INT)
	assert_eq(o.value, 10)


func test_describe_is_never_empty_even_with_no_authored_text() -> void:
	# A row with no label is a line the player reads as a bug.
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({"subject": "age", "compare": ">=", "value": 2}, problems)
	assert_not_null(o)
	assert_false(o.describe().is_empty())
	assert_true(o.describe().contains("2"))


func test_the_wire_form_round_trips_every_field() -> void:
	# 15.2 puts these on the wire inside MatchConfig and folds them into state_hash(), so
	# a field that does not survive to_dict is a field two clients can disagree about.
	# Asserted field by field rather than by comparing dictionaries, because a dictionary
	# comparison passes when BOTH sides are missing the same key.
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "building", "id": "building.house", "owner": 4,
		"compare": "<=", "value": 7, "output": "alert", "text": "Careful",
	}, problems)
	assert_not_null(o)
	assert_eq(problems, [] as Array[String])

	var back := ObjectiveDef.from_wire(o.to_dict())
	assert_eq(back.subject, o.subject)
	assert_eq(back.id, o.id)
	assert_eq(back.owner, o.owner)
	assert_eq(back.owner_index, o.owner_index)
	assert_eq(back.compare, o.compare)
	assert_eq(back.value, o.value)
	assert_eq(back.output, o.output)
	assert_eq(back.text, o.text)


func test_the_wire_form_survives_json_the_way_a_packet_would() -> void:
	# to_dict() is not enough on its own: the wire is JSON, so every int comes back as a
	# float and every StringName as a String. This is the trip that actually happens.
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "unit", "id": "unit.villager", "compare": ">=", "value": 10,
	}, problems)
	assert_not_null(o)

	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(o.to_dict())), OK)
	var back := ObjectiveDef.from_wire(json.data)
	assert_eq(back.subject, ObjectiveDef.Subject.UNIT)
	assert_eq(back.id, &"unit.villager", "a StringName has to be rebuilt from a String")
	assert_eq(back.value, 10)
	assert_eq(typeof(back.value), TYPE_INT)


# ── mode and objectives contradicting each other, in both directions ────────────

func test_scenario_mode_with_no_win_objective_refuses_to_start() -> void:
	var s := ScenarioDef.from_dict("s", {
		"mode": "scenario", "map": {"type": "river", "seed": 1}, "opponents": ["passive"],
		"objectives": [{"subject": "unit", "compare": ">=", "value": 1, "output": "alert"}],
	}, "")
	assert_false(s.is_playable(), "an unwinnable scenario must refuse rather than run")
	assert_true(_joined(s.problems).contains("can never be won"), _joined(s.problems))


func test_last_man_standing_carrying_objectives_refuses_to_start() -> void:
	# The other direction, and it is a refusal for the same reason: silently ignoring an
	# authored win condition loses the author's intent without telling anybody.
	var s := ScenarioDef.from_dict("s", {
		"mode": "last_man_standing", "map": {"type": "river", "seed": 1},
		"opponents": ["passive"],
		"objectives": [{"subject": "unit", "compare": ">=", "value": 1, "output": "win"}],
	}, "")
	assert_false(s.is_playable())
	assert_true(_joined(s.problems).contains("would never be read"), _joined(s.problems))


func test_a_scenario_refuses_a_broken_map_block_in_four_ways() -> void:
	var cases := {
		"needs 2.4c's saved map format": {"map": {"file": "maps/river.map"}},
		"has no 'seed'": {"map": {"type": "river"}},
		"unknown map type": {"map": {"type": "swamp", "seed": 1}},
		"must be an object": {"map": "river"},
	}
	for expected in cases:
		var d: Dictionary = {"mode": "last_man_standing", "opponents": ["passive"]}
		d.merge(cases[expected], true)
		var s := ScenarioDef.from_dict("s", d, "")
		assert_false(s.is_playable(), "should refuse: %s" % expected)
		assert_true(_joined(s.problems).contains(expected),
				"expected '%s', got '%s'" % [expected, _joined(s.problems)])


func test_a_scenario_refuses_a_missing_or_unknown_opponent() -> void:
	var none := ScenarioDef.from_dict("s", {
		"mode": "last_man_standing", "map": {"type": "river", "seed": 1}, "opponents": [],
	}, "")
	assert_false(none.is_playable())
	assert_true(_joined(none.problems).contains("at least two players"), _joined(none.problems))

	var wrong := ScenarioDef.from_dict("s", {
		"mode": "last_man_standing", "map": {"type": "river", "seed": 1},
		"opponents": ["impossible"],
	}, "")
	assert_false(wrong.is_playable())
	assert_true(_joined(wrong.problems).contains("unknown opponent"), _joined(wrong.problems))


func test_an_opponent_may_be_a_bare_name_or_an_object() -> void:
	# The object form is what 16.8 will write once an opponent carries more than a
	# difficulty; accepting both now costs three lines and avoids a schema change then.
	var s := ScenarioDef.from_dict("s", {
		"mode": "last_man_standing", "map": {"type": "river", "seed": 1},
		"opponents": [{"ai": "passive"}],
	}, "")
	assert_true(s.is_playable(), _joined(s.problems))
	assert_eq(s.opponents, [&"passive"] as Array[StringName])


func test_every_ai_level_the_profiles_declare_is_accepted() -> void:
	# Pinned against AIProfile.IDS rather than against a copied list, so adding a
	# difficulty cannot leave scenarios unable to name it.
	for level in AIProfile.IDS:
		var s := ScenarioDef.from_dict("s", {
			"mode": "last_man_standing", "map": {"type": "river", "seed": 1},
			"opponents": [level],
		}, "")
		assert_true(s.is_playable(), "%s should be a legal opponent: %s" % [level, _joined(s.problems)])


func test_one_broken_scenario_does_not_hide_the_rest_of_the_campaign() -> void:
	# A campaign whose second scenario is malformed must still offer the first. The
	# alternative -- refusing the campaign -- would make one typo cost the tutorial.
	var good := ScenarioDef.from_dict("scenario_1", {
		"mode": "last_man_standing", "map": {"type": "river", "seed": 1},
		"opponents": ["passive"],
	}, "")
	var bad := ScenarioDef.from_dict("scenario_2", {"mode": "nonsense"}, "")

	var c := CampaignDef.new()
	c.folder = "F"
	c.scenarios = [good, bad]
	assert_true(c.is_playable())
	assert_eq(c.playable_scenarios().size(), 1)
	assert_eq(c.scenarios.size(), 2, "the broken one is still listed, so 15.5 can grey it")
	assert_true(_joined(c.all_problems()).contains("scenario_2"), _joined(c.all_problems()))


# ── progress and the off-by-one it is easy to get wrong ─────────────────────────

func test_progress_is_a_completion_count_so_zero_unlocks_the_first_scenario() -> void:
	# An off-by-one here either locks the tutorial's first page or unlocks the lot.
	var c := CampaignDef.new()
	c.scenarios = [ScenarioDef.new(), ScenarioDef.new(), ScenarioDef.new()]

	assert_eq(c.unlocked_count(0), 1, "no completions unlocks scenario 1 only")
	assert_eq(c.unlocked_count(1), 2)
	assert_eq(c.unlocked_count(2), 3)
	assert_true(c.is_unlocked(0, 0))
	assert_false(c.is_unlocked(1, 0), "scenario 2 is locked until scenario 1 is beaten")
	assert_true(c.is_unlocked(1, 1))


func test_progress_is_clamped_because_it_comes_from_a_file_a_player_can_edit() -> void:
	var c := CampaignDef.new()
	c.scenarios = [ScenarioDef.new(), ScenarioDef.new()]
	assert_eq(c.unlocked_count(99), 2, "past the end unlocks everything and indexes nothing")
	assert_eq(c.unlocked_count(-5), 0, "a truncated write must not unlock a negative slice")
	assert_false(c.is_unlocked(5, 99))
	assert_false(c.is_unlocked(-1, 99))


# ── the second root, and the ordering trap, against real files ──────────────────

func test_the_user_root_is_read_and_declared_order_beats_alphabetical() -> void:
	# scenario_10 sorts BEFORE scenario_2, so a loader that sorted folder names would put
	# the tenth scenario second. This is that trap, made to happen.
	_write_campaign(_ORDER_FIXTURE, ["scenario_2", "scenario_10"])

	var c := Campaigns.new()
	var found := _by_folder(c.discover())
	assert_true(found.has(_ORDER_FIXTURE), "a campaign under user:// is discovered")
	var campaign: CampaignDef = found[_ORDER_FIXTURE]
	assert_eq(campaign.root, Campaigns.USER_ROOT)
	assert_eq(campaign.scenarios.size(), 2)
	assert_eq(campaign.scenarios[0].folder, "scenario_2", "declared order, not sorted")
	assert_eq(campaign.scenarios[1].folder, "scenario_10")


func test_a_folder_the_order_list_forgets_is_noted_rather_than_played_last() -> void:
	# ⚠️ **THIS WAS A `problem` AND IS NOW A `note`, WHICH IS THE DIFFERENCE BETWEEN A
	# WORK IN PROGRESS AND A BROKEN CAMPAIGN.** `is_playable()` is `problems.is_empty()`,
	# so while an unnamed folder was a problem, starting to write a new mission made every
	# FINISHED mission in the campaign unlaunchable -- which is what happened the moment
	# the owner created a `scenario_4/` on 2026-09-02.
	#
	# It is still said, because it is the only warning a designer gets that a scenario they
	# have written will never be played, and it is still not appended to the play order --
	# playing it last is wrong whether it is unfinished or a typo. And the typo reading is
	# not going unguarded: an order entry naming a folder that does NOT exist is a separate
	# check and is still fatal (the test below).
	var c := Campaigns.new()
	_write_campaign(_ORDER_FIXTURE, ["scenario_2"], ["scenario_2", "scenario_10"])

	var campaign: CampaignDef = _by_folder(c.discover()).get(_ORDER_FIXTURE)
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_eq(campaign.scenarios.size(), 1, "only what the order names is loaded")
	assert_true(_joined(campaign.notes).contains("scenario_10"), _joined(campaign.notes))
	assert_true(_joined(campaign.notes).contains("will never be played"),
			_joined(campaign.notes))
	assert_eq(campaign.problems, [] as Array[String],
			"an unfinished mission is not a broken campaign")
	assert_true(campaign.is_playable(), "and the finished ones still start")

	# The loader keeps the two apart in its own log for the same reason: `warnings` has to
	# be able to stay empty for shipped content (`test_campaign_screen`).
	assert_true(_joined(c.notes).contains("scenario_10"), _joined(c.notes))
	assert_false(_joined(c.warnings).contains("scenario_10"), _joined(c.warnings))


func test_an_order_entry_with_no_folder_is_still_fatal() -> void:
	# The other half of the pair above, and the half that has to stay a `problem`: an order
	# list naming a scenario that is not on disk is a typo or a botched install, and the
	# campaign genuinely cannot be played in the order it declares.
	# ORDER names scenario_99, DISK holds only scenario_2 -- which is the opposite way round
	# from the test above, and the argument order is easy to get backwards: `_write_campaign`
	# takes (folder, order, on_disk).
	_write_campaign(_ORDER_FIXTURE, ["scenario_2", "scenario_99"], ["scenario_2"])

	var campaign: CampaignDef = _by_folder(Campaigns.new().discover()).get(_ORDER_FIXTURE)
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_true(_joined(campaign.problems).contains("scenario_99"), _joined(campaign.problems))
	assert_false(campaign.is_playable(), "a campaign that cannot follow its own order")


func test_the_dev_override_shadows_an_installed_campaign_of_the_same_name() -> void:
	# First match wins, PLAN.md 3.3 -- and the warning matters as much as the behaviour:
	# a developer with both copies is otherwise editing a file the game is not reading,
	# which is game/assets/atlases/'s staleness trap wearing different clothes.
	_write_campaign(_SHADOW_FIXTURE, ["scenario_1"])

	var c := Campaigns.new()
	var found := _by_folder(c.discover())
	var campaign: CampaignDef = found.get(_SHADOW_FIXTURE)
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_ne(campaign.root, Campaigns.USER_ROOT, "the repo copy wins, not the installed one")
	assert_true(campaign.scenarios.size() >= 3,
			"the real HowToPlay, not the one-scenario fixture")
	assert_true(_joined(c.warnings).contains("shadowed"), _joined(c.warnings))


func test_malformed_json_under_the_user_root_is_one_warning_and_not_a_crash() -> void:
	# A campaign is downloadable, shareable content, so these bytes are as untrusted as a
	# network packet -- which is why the loader uses JSON.new().parse() rather than
	# JSON.parse_string(), whose static form pushes an engine error per failure.
	var dir := _FIXTURE_ROOT.path_join(_ORDER_FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_text(dir.path_join(CampaignDef.JSON_FILE), "{ this is not json")

	var c := Campaigns.new()
	var found := _by_folder(c.discover())
	assert_false(found.has(_ORDER_FIXTURE), "an unparseable campaign is skipped")
	assert_true(_joined(c.warnings).contains(_ORDER_FIXTURE), _joined(c.warnings))
	# The real campaign still loads: one bad shared campaign must not cost the others.
	assert_true(found.has("HowToPlay"))


func test_a_campaign_with_no_scenario_list_says_why_the_order_cannot_be_guessed() -> void:
	var dir := _FIXTURE_ROOT.path_join(_ORDER_FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_text(dir.path_join(CampaignDef.JSON_FILE), '{"name": "No Order"}')

	var campaign: CampaignDef = _by_folder(Campaigns.new().discover()).get(_ORDER_FIXTURE)
	assert_not_null(campaign)
	if campaign == null:
		return
	assert_false(campaign.is_playable())
	assert_true(_joined(campaign.problems).contains("play order"), _joined(campaign.problems))


# ── helpers ────────────────────────────────────────────────────────────────────

func _shipped(folder: String) -> ScenarioDef:
	var campaign: CampaignDef = _by_folder(Campaigns.new().discover()).get("HowToPlay")
	if campaign == null:
		return null
	for s in campaign.scenarios:
		if s.folder == folder:
			return s
	return null


func _by_folder(list: Array[CampaignDef]) -> Dictionary:
	var out: Dictionary = {}
	for c in list:
		out[c.folder] = c
	return out


func _joined(a: Array[String]) -> String:
	return " | ".join(a)


## Writes a fixture campaign whose `scenarios` list is `order` and whose folders on disk
## are `on_disk` (defaulting to the same), so the "forgotten folder" case can differ.
func _write_campaign(folder: String, order: Array, on_disk: Array = []) -> void:
	var dir := _FIXTURE_ROOT.path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_text(dir.path_join(CampaignDef.JSON_FILE),
			JSON.stringify({"name": folder, "scenarios": order}))

	for scenario in (on_disk if not on_disk.is_empty() else order):
		var sub: String = dir.path_join(str(scenario))
		DirAccess.make_dir_recursive_absolute(sub)
		_write_text(sub.path_join(ScenarioDef.JSON_FILE), JSON.stringify({
			"name": str(scenario),
			"mode": "last_man_standing",
			"map": {"type": "river", "seed": 1},
			"opponents": ["passive"],
		}))


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _rm_rf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_rm_rf(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
