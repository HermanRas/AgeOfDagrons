## `MatchAudio` -- the snapshot differ that decides WHEN a sound plays
## (PLAN.md 7.5).
##
## WHY THIS IS TESTED AND THE PLAYING IS NOT. Whether a voice actually reaches a
## speaker is not something a headless suite can judge, and asserting it would
## only be asserting that Godot's `AudioStreamPlayer.play()` was called. What CAN
## go wrong here, and silently, is the diffing: a match opening with two hundred
## trained-unit reports, a unit walking into fog being announced as dead, or a
## remembered building faking a completion every time it is re-sighted. All three
## are transitions, all three are decidable from two dictionaries, and all three
## were real hazards in the design rather than hypotheticals -- see the class
## header, which names them.
##
## So this drives `observe()` with hand-built snapshots and asserts on what it
## ASKED to play, via a stub standing in for the AudioManager autoload.
extends TestCase

const MATCH_AUDIO := "res://src/view/match_audio.gd"

const ME := 1
const THEM := 2

## Mirrors `SimBuilding.Phase`.
const FOUNDATION := 0
const UNDER_CONSTRUCTION := 1
const COMPLETE := 2

var audio: MatchAudio
var _spy: _AudioSpy


func before_each() -> void:
	audio = MatchAudio.new()
	_spy = _AudioSpy.new()
	# `MatchAudio.sink` exists for exactly this. The alternative -- renaming the
	# real autoload and reparenting a spy under its name -- works right up until
	# something else in the run resolves the global, and then fails somewhere
	# unrelated.
	audio.sink = _spy


func after_each() -> void:
	audio.sink = null


func _played() -> Array:
	return _spy.calls


## Sound EFFECTS only, with music and ambience filtered out.
##
## The distinction matters for the priming tests. "The first snapshot is silent"
## is a claim about ENTITY events -- a match must not open with a trained-unit
## report per villager -- and it is not a claim about music, which should start
## with the match rather than waiting for the second tick to be sure the first
## one happened.
func _sfx() -> Array:
	var out: Array = []
	for call in _spy.calls:
		if not String(call).begins_with("music:") \
				and not String(call).begins_with("ambient:"):
			out.append(call)
	return out


# ── priming ─────────────────────────────────────────────────────────────────

func test_the_first_snapshot_announces_no_entity_events() -> void:
	# Every entity in the first snapshot is "new". Without priming, joining a
	# match in progress -- or simply starting one with a town centre and three
	# villagers -- would fire a trained-unit report for each.
	audio.observe(_snap([
		_unit(10, ME, &"unit.villager"),
		_unit(11, ME, &"unit.spearman"),
		_building(20, ME, &"building.town_center", COMPLETE),
	]), ME)
	assert_true(_sfx().is_empty(),
			"no entity event fires from the first snapshot, got %s" % [_sfx()])


func test_the_music_starts_with_the_match_rather_than_a_tick_later() -> void:
	# The other half of the above, and the reason it is stated as its own test:
	# priming suppresses ENTITY events, and it must not also suppress the music.
	# Waiting for a second snapshot to be sure the first one happened would open
	# every match with a beat of silence.
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	assert_true(_played().has("music:match.age1"),
			"age 1's track starts immediately, got %s" % [_played()])


func test_the_opening_music_carries_no_age_fanfare() -> void:
	# Starting the music is not the same event as ADVANCING an age, and only the
	# second one is worth a fanfare -- otherwise every match opens by
	# congratulating the player on reaching the age they started in.
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	assert_false(_played().has("ui.age_advance"),
			"no fanfare for the age we began in, got %s" % [_played()])


func test_a_unit_appearing_after_priming_is_announced_once() -> void:
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	audio.observe(_snap([
		_unit(10, ME, &"unit.villager"),
		_unit(11, ME, &"unit.spearman"),
	]), ME)
	assert_true(_played().has("trained.infantry"),
			"the new spearman is reported, got %s" % [_played()])

	# ...and not again on the next snapshot, where it is no longer new.
	_spy.calls.clear()
	audio.observe(_snap([
		_unit(10, ME, &"unit.villager"),
		_unit(11, ME, &"unit.spearman"),
	]), ME)
	assert_false(_played().has("trained.infantry"),
			"a unit is reported once, not every tick")


func test_an_enemy_unit_appearing_is_not_announced() -> void:
	# It is not our news, and an enemy walking in and out of vision would
	# otherwise report itself repeatedly -- see the header on why a vanished
	# entity is forgotten rather than remembered.
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	audio.observe(_snap([
		_unit(10, ME, &"unit.villager"),
		_unit(99, THEM, &"unit.spearman"),
	]), ME)
	assert_false(_played().has("trained.infantry"),
			"an enemy unit is not announced, got %s" % [_played()])


# ── death ───────────────────────────────────────────────────────────────────

func test_a_unit_that_dies_makes_its_death_sound() -> void:
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	var dead := _unit(10, ME, &"unit.villager")
	dead["alive"] = false
	audio.observe(_snap([dead]), ME)
	assert_true(_played().has("die.female"),
			"the villager's death sound plays, got %s" % [_played()])


func test_a_unit_that_walks_into_the_fog_does_not_die() -> void:
	# THE AMBIGUITY THAT MATTERS. Absence from `updated` means "cannot see it",
	# which covers both death and a walk into unexplored ground; the snapshot
	# cannot tell them apart, so a death is only ever read from an entry that is
	# PRESENT and says so.
	audio.observe(_snap([
		_unit(10, ME, &"unit.villager"),
		_unit(99, THEM, &"unit.spearman"),
	]), ME)
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	assert_false(_played().has("die.male"),
			"a vanished unit is not treated as dead, got %s" % [_played()])


func test_a_building_coming_down_adds_the_collapse() -> void:
	audio.observe(_snap([_building(20, ME, &"building.house", COMPLETE)]), ME)
	var wreck := _building(20, ME, &"building.house", COMPLETE)
	wreck["alive"] = false
	audio.observe(_snap([wreck]), ME)
	assert_true(_played().has("building.destroyed"),
			"a destroyed building collapses audibly, got %s" % [_played()])


# ── completion ──────────────────────────────────────────────────────────────

func test_a_building_finishing_plays_its_completion_sound() -> void:
	audio.observe(_snap([
		_building(20, ME, &"building.house", UNDER_CONSTRUCTION)]), ME)
	audio.observe(_snap([
		_building(20, ME, &"building.house", COMPLETE)]), ME)
	assert_true(_played().has("complete.house"),
			"the house reports finished, got %s" % [_played()])


func test_a_building_already_complete_does_not_report_every_tick() -> void:
	audio.observe(_snap([_building(20, ME, &"building.house", COMPLETE)]), ME)
	audio.observe(_snap([_building(20, ME, &"building.house", COMPLETE)]), ME)
	assert_false(_played().has("complete.house"),
			"a standing building is silent, got %s" % [_played()])


func test_a_remembered_building_cannot_fake_a_completion() -> void:
	# `SnapshotSystem._remembered` strips live fields. A remembered entry carries
	# `phase` but the entity may have been seen mid-build before -- what must not
	# happen is a re-sighting reading as a transition because the previous value
	# was lost. Every read defaults to the previous value for exactly this.
	audio.observe(_snap([
		_building(20, THEM, &"building.house", COMPLETE)]), ME)
	var remembered := {
		"id": 20, "def_id": &"building.house", "owner_id": THEM,
		"pos": Vector2i(64, 64), "phase": COMPLETE, "remembered": true,
	}
	audio.observe(_snap([remembered]), ME)
	assert_false(_played().has("complete.house"),
			"a remembered building does not re-announce, got %s" % [_played()])


func test_an_enemy_building_finishing_is_not_our_news() -> void:
	audio.observe(_snap([
		_building(20, THEM, &"building.house", UNDER_CONSTRUCTION)]), ME)
	audio.observe(_snap([
		_building(20, THEM, &"building.house", COMPLETE)]), ME)
	assert_false(_played().has("complete.house"),
			"an enemy's building is silent, got %s" % [_played()])


# ── work and fighting ───────────────────────────────────────────────────────

func test_a_unit_swinging_plays_its_weapon() -> void:
	audio.observe(_snap([_unit(10, ME, &"unit.spearman")]), ME)
	var swinging := _unit(10, ME, &"unit.spearman")
	swinging["anim"] = &"attack"
	audio.observe(_snap([swinging]), ME)
	assert_true(_played().has("attack.spear"),
			"the spearman's weapon is heard, got %s" % [_played()])


func test_a_swing_names_the_unit_that_swung() -> void:
	# The source id is what lets AudioManager pace each unit at its own cadence
	# rather than pacing the SOUND globally -- without it, ten swordsmen share one
	# 2-second slot and nine of them swing silently. Easy to drop in a refactor
	# and impossible to hear the absence of, so it is asserted.
	audio.observe(_snap([_unit(10, ME, &"unit.spearman")]), ME)
	var swinging := _unit(10, ME, &"unit.spearman")
	swinging["anim"] = &"attack"
	audio.observe(_snap([swinging]), ME)
	var at := _played().find("attack.spear")
	assert_true(at != -1, "the spear was heard, got %s" % [_played()])
	assert_eq(_spy.sources[at], 10, "and it was attributed to entity 10")


func test_a_unit_with_no_weapon_is_silent_when_it_attacks() -> void:
	# The monk has no `attack` in audio_map.json because he carries nothing.
	# `entity_sfx` returns &"" and `play_sfx` treats that as a no-op -- the
	# alternative, falling back to a sword, would arm him in the mix only.
	audio.observe(_snap([_unit(10, ME, &"unit.monk")]), ME)
	var swinging := _unit(10, ME, &"unit.monk")
	swinging["anim"] = &"attack"
	audio.observe(_snap([swinging]), ME)
	for call in _played():
		assert_false(String(call).begins_with("attack."),
				"the monk swings silently, got %s" % [_played()])


func test_work_takes_its_sound_from_what_is_being_worked() -> void:
	# The distinction the spatial lookup exists for: `work_hunt` is one animation
	# covering a berry bush, a carcass and a fishing spot, and they are three
	# different noises. A villager beside a bush forages; beside a carcass, butchers.
	var bush := _node(30, &"res.berry_bush", Vector2i(4, 4))
	var worker := _unit(10, ME, &"unit.villager", Vector2i(4, 4))
	audio.observe(_snap([bush, worker]), ME)
	worker = _unit(10, ME, &"unit.villager", Vector2i(4, 4))
	worker["anim"] = &"work_hunt"
	audio.observe(_snap([bush, worker]), ME)
	assert_true(_played().has("villager.forage"),
			"beside a bush she forages, got %s" % [_played()])


func test_the_same_animation_beside_a_carcass_is_a_different_sound() -> void:
	var carcass := _node(31, &"res.deer_carcass", Vector2i(9, 9))
	var worker := _unit(10, ME, &"unit.villager", Vector2i(9, 9))
	audio.observe(_snap([carcass, worker]), ME)
	worker = _unit(10, ME, &"unit.villager", Vector2i(9, 9))
	worker["anim"] = &"work_hunt"
	audio.observe(_snap([carcass, worker]), ME)
	assert_true(_played().has("villager.hunt"),
			"beside a carcass she butchers, got %s" % [_played()])


func test_building_work_takes_the_buildings_own_material() -> void:
	# A stone keep and a timber palisade do not sound alike, which is why `build`
	# is per building rather than one construction noise.
	var site := _building(21, ME, &"building.castle", UNDER_CONSTRUCTION, Vector2i(6, 6))
	var worker := _unit(10, ME, &"unit.villager", Vector2i(6, 6))
	audio.observe(_snap([site, worker]), ME)
	worker = _unit(10, ME, &"unit.villager", Vector2i(6, 6))
	worker["anim"] = &"work_build"
	audio.observe(_snap([site, worker]), ME)
	assert_true(_played().has("villager.build_stone"),
			"a castle is built in stone, got %s" % [_played()])


func test_work_with_nothing_in_reach_is_silent() -> void:
	# A villager gathering from a node at the edge of vision. Guessing from the
	# anim would be possible and would be a second, disagreeing mapping.
	var worker := _unit(10, ME, &"unit.villager", Vector2i(40, 40))
	audio.observe(_snap([worker]), ME)
	worker = _unit(10, ME, &"unit.villager", Vector2i(40, 40))
	worker["anim"] = &"work_chop"
	audio.observe(_snap([worker]), ME)
	for call in _played():
		assert_false(String(call).begins_with("villager."),
				"no target in reach means silence, got %s" % [_played()])


# ── gates, ages, results ────────────────────────────────────────────────────

func test_a_gate_opening_and_shutting_are_different_sounds() -> void:
	var gate := _building(22, ME, &"building.wall_stone_gate", COMPLETE)
	gate["gate_locked"] = true
	audio.observe(_snap([gate]), ME)

	var opened := _building(22, ME, &"building.wall_stone_gate", COMPLETE)
	opened["gate_locked"] = false
	audio.observe(_snap([opened]), ME)
	assert_true(_played().has("gate.open"), "opening is heard, got %s" % [_played()])

	_spy.calls.clear()
	var shut := _building(22, ME, &"building.wall_stone_gate", COMPLETE)
	shut["gate_locked"] = true
	audio.observe(_snap([shut]), ME)
	assert_true(_played().has("gate.close"), "shutting is heard, got %s" % [_played()])


func test_advancing_an_age_announces_it_and_changes_the_music() -> void:
	var first := _snap([_unit(10, ME, &"unit.villager")])
	first["player_state"] = {ME: {"age": 1}}
	audio.observe(first, ME)

	_spy.calls.clear()
	var second := _snap([_unit(10, ME, &"unit.villager")])
	second["player_state"] = {ME: {"age": 2}}
	audio.observe(second, ME)
	assert_true(_played().has("ui.age_advance"),
			"the age lands audibly, got %s" % [_played()])
	assert_true(_played().has("music:match.age2"),
			"the music follows the age, got %s" % [_played()])


func test_the_result_is_announced_once() -> void:
	var live := _snap([_unit(10, ME, &"unit.villager")])
	live["player_state"] = {ME: {"age": 1}}
	audio.observe(live, ME)

	_spy.calls.clear()
	var won := _snap([_unit(10, ME, &"unit.villager")])
	won["player_state"] = {ME: {"age": 1}}
	won["match_over"] = true
	won["winner_id"] = ME
	audio.observe(won, ME)
	assert_true(_played().has("ui.victory"), "victory is heard, got %s" % [_played()])

	_spy.calls.clear()
	audio.observe(won, ME)
	assert_false(_played().has("ui.victory"),
			"the result is announced once, not every tick after it")


func test_losing_is_a_different_announcement() -> void:
	var live := _snap([_unit(10, ME, &"unit.villager")])
	live["player_state"] = {ME: {"age": 1}}
	audio.observe(live, ME)

	var lost := _snap([_unit(10, ME, &"unit.villager")])
	lost["player_state"] = {ME: {"age": 1, "defeated": true}}
	audio.observe(lost, ME)
	assert_true(_played().has("ui.defeat"), "defeat is heard, got %s" % [_played()])
	assert_false(_played().has("ui.victory"), "and victory is not")


# ── the off switch ──────────────────────────────────────────────────────────

func test_disabling_it_makes_it_do_nothing() -> void:
	# The AI-vs-AI preview and the suite step thousands of ticks with nobody
	# listening; a match's worth of sound is pure cost there.
	audio.enabled = false
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	var dead := _unit(10, ME, &"unit.villager")
	dead["alive"] = false
	audio.observe(_snap([dead]), ME)
	assert_true(_played().is_empty(), "disabled means silent, got %s" % [_played()])


func test_resetting_forgets_the_previous_match() -> void:
	# A MatchAudio outliving its match would compare the new world's entity 10
	# against the old one's -- which is a different unit with the same id.
	audio.observe(_snap([_unit(10, ME, &"unit.villager")]), ME)
	audio.reset()
	_spy.calls.clear()
	audio.observe(_snap([_unit(10, ME, &"unit.spearman")]), ME)
	assert_true(_sfx().is_empty(),
			"after a reset the next snapshot primes again, got %s" % [_sfx()])


# ── King of the Hill: control changing hands (11.x-koth-control-sound) ──────
#
# ⚠️ **THE HAZARD HERE IS NOT "DOES IT PLAY", IT IS "DOES IT SHUT UP".** The owner's ask
# carried its own warning -- *"short subtile sound, it will play often"* -- and the rule it
# sits on is worse than that warning knew: a tie has no UNIQUE leader, so `koth_holder` drops
# to 0 whenever a fight on the hill is even and returns the moment one side is a single unit
# ahead. A real 5-v-5 is `1 -> 0 -> 1 -> 0` several times a second. So the load-bearing
# tests below are the SILENT ones.
#
# 📝 **UNAFFECTED BY THE SAME DAY'S LADDER FIX**, and worth saying so: under PLAN.md §11.9 a
# contested hill pays both sides rather than nobody, but `koth_holder` still names the unique
# leader, so the cadence these tests are about did not move an inch.

const _HILL := Rect2i(40, 40, 13, 13)


func _koth_snap(holder: int, zone: Rect2i = _HILL) -> Dictionary:
	var s := _snap([])
	s["koth_x"] = zone.position.x
	s["koth_y"] = zone.position.y
	s["koth_w"] = zone.size.x
	s["koth_h"] = zone.size.y
	s["koth_holder"] = holder
	return s


## Feed one holder for long enough that the dwell believes it.
##
## DERIVED FROM THE CONSTANT, never a literal 12: the dwell is a tuning number and the
## thing these tests are about is the ORDERING (a flicker must not survive it, a real
## capture must), which stays true whatever it is retuned to.
func _hold(holder: int, ticks: int = MatchAudio._KOTH_DWELL_TICKS) -> void:
	for _i in range(ticks):
		audio.observe(_koth_snap(holder), ME)


func test_a_match_with_no_hill_never_mentions_one() -> void:
	# The five koth fields ride EVERY snapshot, so a conquest match reaches this code
	# on every tick with a holder of 0. An empty rect is the arming convention -- the
	# same one the minimap reads -- and without it every non-KotH match in the game
	# would be running this differ for nothing.
	for _i in range(MatchAudio._KOTH_DWELL_TICKS * 3):
		audio.observe(_koth_snap(1, Rect2i()), ME)
	assert_true(_sfx().is_empty(), "no zone, no sound, got %s" % [_sfx()])


func test_the_first_holder_seen_is_recorded_rather_than_announced() -> void:
	# Joining a match in progress, or simply the first snapshot after the mode arms:
	# whoever happens to be standing on the hill has not just taken it. Same swallow as
	# `_primed` does for entity events, and the reason `_koth_announced` starts at -1
	# rather than 0 -- 0 is a real state the wire sends.
	_hold(3)
	assert_true(_sfx().is_empty(), "got %s" % [_sfx()])


func test_taking_an_empty_hill_sounds_once() -> void:
	_hold(0)
	_hold(1)
	assert_eq(_sfx(), ["ui.koth_control"])


func test_a_hill_nobody_is_fighting_over_stays_quiet() -> void:
	# The sound is a CHANGE of control, so a player who holds the hill for the rest of
	# the match hears it once. Without the announced-holder test this would fire on every
	# snapshot for as long as they held it -- which at 10 Hz is the loudest possible
	# reading of "it will play often".
	_hold(0)
	_hold(1)
	_hold(1)
	_hold(1)
	assert_eq(_sfx(), ["ui.koth_control"], "held, not re-taken")


func test_a_contested_hill_flickering_every_tick_announces_nothing() -> void:
	# ⚠️ **THE CARD'S CENTRAL CASE, AND THE ONE AN INTERVAL ALONE DOES NOT FIX.** A
	# throttle would turn this into a metronome -- a sound every few seconds, saying
	# nothing, during the exact moment the player is busiest. A value has to SURVIVE to
	# count, so a hill changing hands faster than the dwell settles on neither.
	_hold(0)
	_spy.calls.clear()
	for i in range(MatchAudio._KOTH_DWELL_TICKS * 8):
		audio.observe(_koth_snap(1 if i % 2 == 0 else 0), ME)
	assert_true(_sfx().is_empty(),
			"a 5-v-5 standoff is silent, got %s" % [_sfx()])


func test_a_holder_that_changes_one_tick_short_of_the_dwell_is_not_believed() -> void:
	# The dwell's own boundary, and the test that fails if somebody deletes it: without
	# the counter this is a capture, with it it is noise.
	_hold(0)
	_hold(1, MatchAudio._KOTH_DWELL_TICKS - 1)
	_hold(0)
	assert_true(_sfx().is_empty(), "one tick short is not a capture, got %s" % [_sfx()])


func test_losing_the_hill_to_a_contested_fight_is_silent() -> void:
	# ⛔ **THE OWNER'S RULING, 2026-09-11: taken and stolen sound, lost does not.** It is
	# the transition that fires most and means least -- a tie has no unique leader, so this
	# is what every even fight on the hill looks like, and both sides are still scoring
	# through it.
	_hold(0)
	_hold(1)
	_spy.calls.clear()
	_hold(0)
	assert_true(_sfx().is_empty(), "going contested is not news, got %s" % [_sfx()])


func test_stealing_a_hill_from_the_side_holding_it_sounds() -> void:
	_hold(0)
	_hold(1)
	_spy.calls.clear()
	_hold(2)
	assert_eq(_sfx(), ["ui.koth_control"])


func test_retaking_your_own_hill_after_a_long_fight_sounds_again() -> void:
	# The consequence of `lost` still MOVING the announced holder even though it makes no
	# noise. Holding the old winner through a sustained contest instead would make
	# retaking your own hill silent -- a capture the player is never told about.
	_hold(0)
	_hold(1)
	_spy.calls.clear()
	_hold(0)          # a long, genuinely contested spell -- silent
	_hold(1)          # and then P1 takes it back
	assert_eq(_sfx(), ["ui.koth_control"])


func test_the_differ_reads_the_keys_the_real_snapshot_system_writes() -> void:
	# ⚠️ **EVERY OTHER TEST IN THIS SECTION HANDS `observe()` A DICTIONARY THIS FILE WROTE**,
	# so all ten would go on passing if `SnapshotSystem` renamed `koth_holder` tomorrow and
	# the feature stopped working completely. This is the one that fails instead.
	#
	# `test_koth` pins the other half -- that the five fields reach the wire at all -- and
	# **neither test can see what the other covers**: that one builds a snapshot and never
	# plays a sound, this one plays a sound and never checks a rect. A rename breaks this
	# one; a dropped field breaks that one.
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = Vector2i(48, 48)
	cfg.mode = MatchConfig.Mode.KING_OF_THE_HILL
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	world.koth_zone = Rect2i(20, 20, 8, 8)

	# An empty hill first, so the recorded-not-announced swallow is spent on it, and then
	# player 1 taking it. Set directly rather than by marching units on: what is under test
	# here is the wire vocabulary, and `test_koth` is where the rule that writes it lives.
	for _i in range(MatchAudio._KOTH_DWELL_TICKS):
		audio.observe(SnapshotSystem.build(world, ME), ME)
	world.koth_holder = 1
	for _i in range(MatchAudio._KOTH_DWELL_TICKS):
		audio.observe(SnapshotSystem.build(world, ME), ME)

	assert_eq(_sfx(), ["ui.koth_control"],
			"announced off a snapshot the real SnapshotSystem built, not one written here")


func test_resetting_forgets_which_hill_was_held() -> void:
	# A MatchAudio outliving its match would read the new match's first hill as a THEFT
	# from whoever held the last one's, and announce it to everybody.
	_hold(0)
	_hold(1)
	audio.reset()
	_spy.calls.clear()
	_hold(2)
	assert_true(_sfx().is_empty(),
			"after a reset the first holder primes again, got %s" % [_sfx()])


# ── fixtures ────────────────────────────────────────────────────────────────

func _snap(updated: Array) -> Dictionary:
	return {
		"tick": 1,
		"updated": updated,
		"removed": [],
		"player_state": {ME: {"age": 1}},
		"match_over": false,
		"winner_id": 0,
	}


func _unit(id: int, owner: int, def_id: StringName,
		tile := Vector2i(2, 2)) -> Dictionary:
	return {
		"id": id, "def_id": def_id, "owner_id": owner,
		"pos": tile * SimWorld.SUBTILE, "hp": 50, "max_hp": 50, "alive": true,
		"task": 0, "anim": &"idle", "facing": 0, "corpse_ticks_left": 0,
	}


func _building(id: int, owner: int, def_id: StringName, phase: int,
		tile := Vector2i(8, 8)) -> Dictionary:
	return {
		"id": id, "def_id": def_id, "owner_id": owner,
		"pos": tile * SimWorld.SUBTILE, "hp": 100, "max_hp": 100, "alive": true,
		"phase": phase, "facing": 0, "gate_locked": false,
		"rubble_ticks_left": 0, "build_fraction": 1.0,
		"queue_len": 0, "queue_fraction": 0.0, "queue": [],
	}


func _node(id: int, def_id: StringName, tile: Vector2i) -> Dictionary:
	return {
		"id": id, "def_id": def_id, "owner_id": 0,
		"pos": tile * SimWorld.SUBTILE, "hp": 1, "max_hp": 1, "alive": true,
		"kind": &"food", "amount": 300, "remaining": 1.0, "size_class": 0,
	}


## Records what was asked for instead of playing it. Music is prefixed so a track
## and a sound effect of the same name could never be confused in an assertion.
##
## A RefCounted, not a Node: it is never in the tree, so there is nothing to free
## and nothing to leak if a test fails part way through.
class _AudioSpy:
	extends RefCounted

	var calls: Array = []
	## Parallel to `calls`, for the positional ones: which entity was named as the
	## source. Only meaningful for `play_sfx_at`.
	var sources: Array = []

	func play_sfx(sound_id: StringName) -> bool:
		if sound_id != &"":
			calls.append(String(sound_id))
			# -1, so `sources` stays INDEX-ALIGNED with `calls`. Appending only in
			# play_sfx_at let the two drift apart and an assertion indexed off the
			# end -- a flat sound has no source, which is not the same as there
			# being no entry for it.
			sources.append(-1)
		return true

	func play_sfx_at(sound_id: StringName, _pos: Vector2,
			_listener := Vector2.INF, source_id: int = 0) -> bool:
		if sound_id != &"":
			calls.append(String(sound_id))
			sources.append(source_id)
		return true

	func play_music(music_id: StringName) -> bool:
		calls.append("music:" + String(music_id))
		sources.append(-1)
		return true

	func play_ambient(sound_id: StringName) -> bool:
		calls.append("ambient:" + String(sound_id))
		sources.append(-1)
		return true
