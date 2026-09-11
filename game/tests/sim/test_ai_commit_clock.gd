## When a bot commits its army, per game type (card `14b-ai-commit-clock`).
##
## ## THE DEFECT THIS FILE EXISTS FOR
##
## `14a-ai-game-types` sent a King of the Hill bot to the hill and a Trophy bot to its own dragon,
## and eleven tests said so. Then the owner played a King of the Hill match on 2026-09-11 and it
## finished **9,000 to 0** -- the standings panel showed the bot on `0` with `--` for time, meaning
## it never stood in the zone for a single tick. The branch was correct and **was never reached**:
## the army commits only once the attack rule has fired, Easy's attack rule waited 6,000 ticks, and
## a King of the Hill match can be over in 3,000.
##
## So the fix is not in the branch, it is in front of it — and it turned out to be **two** gates,
## which is why this file covers both.
##
## ## ⛔ THE CLOCK WAS ONLY HALF, AND THE MEASUREMENT IS WHAT SAID SO
##
## With the hill clock down at 900, `preview_ai_match --mode koth` still put an Easy bot's soldiers
## on the hill at **t5621 — 9.4 minutes**: barracks t4030, fifth swordsman t5540, attack t5580. The
## clock was never what bound. The rule wanted **five swordsmen** and the economy does not make five
## swordsmen before nine minutes, so `mode_at_least` moves that too — and the same sentence carries
## both: **standing on ground that pays by the tick is not an attack.**
##
## ## ⚠️ THE TWO SHAPES OF WRONG, AND WHY BOTH ARE TESTED
##
## A mode clock that only ever DELAYED would be useless -- the whole point is that a game type may
## commit EARLIER than the profile's opening. A mode clock that applied to every rule would gate a
## bot's GATHERING for the first minute of a Trophy match. Both are one line away from the shipped
## behaviour and neither announces itself, so each has a test that fails on it.
extends TestCase

## The fastest a King of the Hill match can possibly end, from the two numbers that decide it:
## §11.9's ladder pays 3 a tick to a side holding the hill alone, and `KOTH_TARGET_SCORE` is what
## it is being paid towards. **Derived rather than written down as 3,000**, so that moving the
## target moves what the bots are required to beat.
const FASTEST_KOTH_TICKS := WinConditionSystem.KOTH_TARGET_SCORE / 3


## A profile with one attack rule on a 3,000-tick opening and five swordsmen, a hill clock
## well inside it, and a hill army size of "whatever you have".
func _profile(mode_clocks: Dictionary = {"trophy": 0, "king_of_the_hill": 900},
		mode_armies: Dictionary = {"trophy": {}, "king_of_the_hill": {}}) -> AIProfile:
	return AIProfile.from_dict({
		"id": "test",
		"mode_after_ticks": mode_clocks,
		"mode_at_least": mode_armies,
		"rules": [
			{"do": "gather", "kind": "food", "units": 1,
			 "when": {"gathering_fewer_than": {"food": 2}}},
			{"do": "build", "def": "building.house", "near": "self", "units": 1,
			 "when": {"after_ticks": 3000, "fewer_than": {"building.house": 1}}},
			{"do": "attack", "units": "military",
			 "when": {"after_ticks": 3000}},
		],
	})


func _rule(profile: AIProfile, verb: String) -> Dictionary:
	for r in profile.rules:
		if String(r.get("do", "")) == verb:
			return r
	return {}


## A two-player world in `mode`, no map generation -- these are decision tests, and `MapGen` costs
## a second a call (`test_ai_game_types`'s reasoning, and the same helper).
func _world(mode: MatchConfig.Mode, tick: int) -> SimWorld:
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = Vector2i(64, 64)
	cfg.mode = mode
	cfg.ai_players = [true, false] as Array[bool]
	var world := SimWorld.new()
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	world.tick = tick
	return world


func _ai(world: SimWorld) -> AISystem:
	for s in world._systems:
		if s is AISystem:
			return s as AISystem
	return null


## Does this rule's clock let it fire, in this world, right now?
func _clock_allows(world: SimWorld, profile: AIProfile, rule: Dictionary) -> bool:
	var ai := _ai(world)
	var p := world.player_for(1)
	return ai._matches(world, p, profile, rule, ai._census(world, p))


# ── AIProfile: reading the clocks off the file ──────────────────────────────

func test_a_profile_reads_a_clock_for_each_game_type() -> void:
	var profile := _profile({
		"last_man_standing": 10, "trophy": 20, "king_of_the_hill": 30, "scenario": 40,
	})
	# Keyed by the ENUM, not by the spelling: the sim asks with `w.mode`, which is an int.
	assert_eq(int(profile.mode_after_ticks[int(MatchConfig.Mode.LAST_MAN_STANDING)]), 10)
	assert_eq(int(profile.mode_after_ticks[int(MatchConfig.Mode.TROPHY)]), 20)
	assert_eq(int(profile.mode_after_ticks[int(MatchConfig.Mode.KING_OF_THE_HILL)]), 30)
	assert_eq(int(profile.mode_after_ticks[int(MatchConfig.Mode.SCENARIO)]), 40)


## A game type nobody wrote a line for is the common case -- Hard and Unfair declare none at all --
## and it has to mean "unchanged" rather than "immediately".
func test_a_game_type_with_no_entry_keeps_the_rules_own_clock() -> void:
	var profile := _profile()
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.LAST_MAN_STANDING), 3000), 3000)
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.SCENARIO), 3000), 3000)


## ⚠️ **IT REPLACES THE OPENING, IT DOES NOT ADD TO IT.** An implementation taking the LATER of the
## two passes every other test in this file and fixes nothing at all: every mode clock worth
## writing is shorter than the opening it is correcting, which is the entire reason it exists.
func test_a_mode_clock_may_be_earlier_than_the_opening() -> void:
	var profile := _profile()
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.KING_OF_THE_HILL), 3000), 900)
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.TROPHY), 3000), 0,
			"and zero is a real answer, not a missing one")


func test_a_misspelled_game_type_is_ignored_rather_than_believed() -> void:
	# It warns as well. What must NOT happen is the typo landing under some other mode's key or
	# arriving as 0 -- "kingofthehill: 900" silently becoming "commit at once" in every match.
	var profile := _profile({"kingofthehill": 900, "trophy": 0})
	assert_eq(profile.mode_after_ticks.size(), 1, "only the one it could understand")
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.KING_OF_THE_HILL), 3000), 3000,
			"the typo left the conquest clock in place rather than replacing it with rubbish")


func test_a_negative_clock_is_clamped_rather_than_read_as_before_the_match() -> void:
	var profile := _profile({"trophy": -500})
	assert_eq(profile.attack_clock(int(MatchConfig.Mode.TROPHY), 3000), 0)


# ── AISystem: the clock in the rule loop ────────────────────────────────────

## The defect itself, in one assertion.
func test_a_koth_bot_may_commit_before_its_conquest_clock() -> void:
	var profile := _profile()
	var attack := _rule(profile, "attack")
	assert_true(_clock_allows(_world(MatchConfig.Mode.KING_OF_THE_HILL, 1000), profile, attack),
			"tick 1000 is past the hill's 900 and nowhere near the opening's 3000")
	assert_false(_clock_allows(_world(MatchConfig.Mode.KING_OF_THE_HILL, 800), profile, attack),
			"and the hill clock is still a clock -- 800 is too early")


## The regression guard on the thing the difficulty table actually promises a player: how long they
## get before a bot comes at them in a normal match.
func test_last_man_standing_still_waits_the_whole_opening() -> void:
	var profile := _profile()
	var attack := _rule(profile, "attack")
	assert_false(_clock_allows(_world(MatchConfig.Mode.LAST_MAN_STANDING, 2999), profile, attack))
	assert_true(_clock_allows(_world(MatchConfig.Mode.LAST_MAN_STANDING, 3000), profile, attack))


## ⛔ **THE TRAP: A PROFILE-WIDE CLOCK APPLIED TO EVERY RULE STOPS THE BOT PLAYING.** The gather
## rule below carries no clock of its own, so the only way it can fail is a mode clock leaking onto
## a verb it was never about -- and a Trophy bot that gathers nothing for the first minute is a
## worse bug than the one being fixed, arriving disguised as "the AI is slow".
func test_a_mode_clock_does_not_gate_anything_but_an_attack() -> void:
	var profile := _profile({"trophy": 900, "king_of_the_hill": 900})
	var w := _world(MatchConfig.Mode.TROPHY, 0)
	assert_true(_clock_allows(w, profile, _rule(profile, "gather")),
			"a villager goes to the berries on tick 0, in every mode")


## The other half of the same rule, and the sharper one: a non-attack rule that DOES have a clock
## keeps its own. Only aggression is what a game type gets to re-time.
func test_a_mode_clock_does_not_move_another_rules_clock() -> void:
	var profile := _profile()
	var w := _world(MatchConfig.Mode.KING_OF_THE_HILL, 1000)
	assert_false(_clock_allows(w, profile, _rule(profile, "build")),
			"the house rule waits its own 3000 even though the hill clock is 900")


# ── the shipped profiles, asserted rather than trusted ──────────────────────

## The attack rule's own `after_ticks` for a level, or 0 where it has none (Hard and Unfair gate on
## an economy instead). Passive has no attack rule at all and is skipped by every caller.
func _shipped_opening(profile: AIProfile) -> int:
	var attack := _rule(profile, "attack")
	return int((attack.get("when", {}) as Dictionary).get("after_ticks", 0))


## ⛳ **THE TEST THAT TIES THE FIX TO THE PLAYTEST.** A bot whose commit clock is longer than the
## match cannot lose the hill -- it can only fail to turn up, which is what 9,000 to 0 looked like.
## This fails on the shipped data as it stood that morning: Easy at 6,000 against a 3,000-tick match.
func test_every_bot_can_reach_the_hill_before_the_hill_can_be_won() -> void:
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		if _rule(profile, "attack").is_empty():
			continue          # Passive never trains a soldier, so it has nothing to send
		var clock := profile.attack_clock(int(MatchConfig.Mode.KING_OF_THE_HILL),
				_shipped_opening(profile))
		assert_true(clock < FASTEST_KOTH_TICKS,
				"%s commits at %d, and a hill can be won in %d"
						% [profile.id, clock, FASTEST_KOTH_TICKS])


## ⚠️ **NOBODY WAITS TO DEFEND.** Trophy is the one mode where the army's job starts at tick 0: the
## thing it guards can be killed from the first minute, and a handicap expressed as "leaves its
## dragon alone for five minutes" is not a difficulty, it is a different loss condition.
func test_no_bot_waits_before_guarding_its_own_trophy() -> void:
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		if _rule(profile, "attack").is_empty():
			continue
		assert_eq(profile.attack_clock(int(MatchConfig.Mode.TROPHY), _shipped_opening(profile)), 0,
				"%s waits to guard its dragon" % profile.id)


## The owner's ruling of 2026-09-11 -- *"bots are too slow over all can we half the attack time for
## the bots in general"* -- pinned where a later tune has to look at it. `AI_Player_difficulty.md`
## is the table these two numbers belong to; Hard and Unfair have no clock to halve.
func test_the_two_clocked_levels_open_at_five_minutes_and_three_and_a_half() -> void:
	assert_eq(_shipped_opening(GameDataRegistry.ai_profile(SimPlayer.AILevel.EASY)),
			5 * 60 * SimClock.TICK_HZ)
	assert_eq(_shipped_opening(GameDataRegistry.ai_profile(SimPlayer.AILevel.NORMAL)),
			210 * SimClock.TICK_HZ)
	for level in [SimPlayer.AILevel.HARD, SimPlayer.AILevel.UNFAIR]:
		assert_eq(_shipped_opening(GameDataRegistry.ai_profile(level)), 0,
				"%s gates on an economy, not a clock" % AIProfile.IDS[level])


# ── the army size, the other gate in front of the same decision ─────────────

## The same shape as `_profile`, plus the thing that actually held the bot back: an attack rule that
## wants five swordsmen in hand, and a train rule that wants a barracks.
func _army_profile(mode_armies: Dictionary = {"trophy": {}, "king_of_the_hill": {}}) -> AIProfile:
	return AIProfile.from_dict({
		"id": "test",
		"mode_at_least": mode_armies,
		"rules": [
			{"do": "train", "at": "building.barracks", "unit": "unit.swordsman", "count": 5,
			 "when": {"at_least": {"building.barracks": 1}}},
			{"do": "attack", "units": "military",
			 "when": {"at_least": {"unit.swordsman": 5}}},
		],
	})


func test_a_profile_reads_an_army_size_for_a_game_type() -> void:
	var profile := _army_profile({"king_of_the_hill": {"unit.swordsman": 2}})
	var want: Dictionary = profile.mode_at_least[int(MatchConfig.Mode.KING_OF_THE_HILL)]
	# ⚠️ **StringName KEYS, OR IT COUNTS NOTHING.** `_census` keys `owned` by the entity's own
	# `def_id`, and this file's own header records that `&"unit.villager" == "unit.villager"` is
	# false for a dictionary lookup. A String key here is a condition that is always unmet.
	assert_true(want.has(&"unit.swordsman"), "the def id survived as a StringName")
	assert_eq(int(want[&"unit.swordsman"]), 2)


## ⚠️ **AN EMPTY DICTIONARY IS A VALUE, NOT AN ABSENCE**, and the whole feature is that distinction:
## "this mode asks for nothing" and "this mode says nothing" have to be different answers.
func test_an_empty_army_size_is_a_real_value_and_not_a_missing_one() -> void:
	var profile := _army_profile()
	var rule_wants := {&"unit.swordsman": 5}
	assert_true(profile.attack_at_least(int(MatchConfig.Mode.KING_OF_THE_HILL),
			rule_wants).is_empty(), "the hill asks for whatever you have")
	assert_eq(profile.attack_at_least(int(MatchConfig.Mode.LAST_MAN_STANDING), rule_wants),
			rule_wants, "and a mode that said nothing keeps the rule's own five")


## The measured defect, in one assertion: a bot with no army at all may commit to the hill.
func test_a_koth_bot_commits_with_whatever_army_it_has() -> void:
	var profile := _army_profile()
	var w := _world(MatchConfig.Mode.KING_OF_THE_HILL, 0)
	assert_true(_clock_allows(w, profile, _rule(profile, "attack")),
			"five swordsmen is a number about attacking a base, not about standing on a hill")


## ⛔ **AND CONQUEST STILL WANTS THE WHOLE ARMY**, which is the half that keeps the difficulty
## meaning something. Without this, "go with whatever you have" would be a bot feeding you its
## starting scout in every ordinary skirmish — `_keep_busy`'s own note calls that *"giving away a
## unit before the first house is up"*.
func test_a_conquest_bot_still_waits_for_the_whole_army() -> void:
	var profile := _army_profile()
	var w := _world(MatchConfig.Mode.LAST_MAN_STANDING, 0)
	var attack := _rule(profile, "attack")
	assert_false(_clock_allows(w, profile, attack), "one scout is not five swordsmen")
	for i in range(5):
		w.spawn_unit(&"unit.swordsman", 1, Vector2i(4 + i, 4))
	assert_true(_clock_allows(w, profile, attack), "and with five of them it goes")


## The army override's version of the clock's trap: it must not reach a rule that is not an attack.
## A train rule freed of "I need a barracks" would order swordsmen out of open ground forever.
func test_a_mode_army_size_does_not_reach_another_rule() -> void:
	var profile := _army_profile()
	var w := _world(MatchConfig.Mode.KING_OF_THE_HILL, 0)
	assert_false(_clock_allows(w, profile, _rule(profile, "train")),
			"there is no barracks, and the hill does not excuse one")


## ⛳ **THE SHIPPED DATA, AND THE OTHER HALF OF THE 9.4-MINUTE FINDING.** Every bot that fights must
## be willing to hold ground with whatever it owns, in both modes where the army holds ground. This
## fails on the data as it stood before the measurement: Easy wanted 5 swordsmen, Hard wanted 8.
func test_no_bot_waits_for_an_army_before_holding_ground() -> void:
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		var attack := _rule(profile, "attack")
		if attack.is_empty():
			continue          # Passive never trains a soldier, so it has nothing to send
		var rule_wants: Dictionary = (attack.get("when", {}) as Dictionary).get("at_least", {})
		for mode in [MatchConfig.Mode.TROPHY, MatchConfig.Mode.KING_OF_THE_HILL]:
			assert_true(profile.attack_at_least(int(mode), rule_wants).is_empty(),
					"%s waits for %s before holding ground in %s"
							% [profile.id, rule_wants, MatchConfig.mode_name(mode)])


## And the guard on the other side of it: conquest is untouched, so a level that fights still has to
## say what it fights with. A blanket "go with anything" would pass the test above and gut the ladder.
func test_conquest_still_names_an_army_for_every_level_that_fights() -> void:
	for level in range(AIProfile.IDS.size()):
		var profile := GameDataRegistry.ai_profile(level)
		var attack := _rule(profile, "attack")
		if attack.is_empty():
			continue
		var rule_wants: Dictionary = (attack.get("when", {}) as Dictionary).get("at_least", {})
		assert_false(profile.attack_at_least(int(MatchConfig.Mode.LAST_MAN_STANDING),
				rule_wants).is_empty(), "%s would attack with nothing" % profile.id)
