## TROPHY MODE (PLAN.md 11.2, built 2026-09-07): every player starts with a dragon
## hatchling and is out the moment it dies.
##
## ## WHAT THIS FILE IS REALLY GUARDING, AND IT IS NOT THE RULE
##
## The rule is six lines. What took the work is that it cannot be allowed to fire when the
## trophies are not there -- 11.2 spent two years inert on exactly that sentence: *"'you
## lose when your trophy dies', on a map with no trophies, defeats everybody on tick 1."*
## So the arming guard (`SimWorld.trophy_def_id`, written only after EVERY player has one)
## gets more assertions here than the win condition does.
##
## ## AND ONE COLLISION THAT WOULD HAVE BEEN CATASTROPHIC AND SILENT
##
## A trophy is a `unit.dragon_baby` -- **the same def 13.2 hatches at a dragon nest**, for
## an opposite job: the claim hatchling is gaia's, spawned by a death, tied to its nest and
## replaced on a timer; a trophy is yours from tick 1 and must survive. `NestSystem` used
## to collect every hatchling in the world by def id alone and `_reap_orphans` kills any it
## finds that no nest has recorded -- so **every trophy in the match would have been killed
## on tick 1, defeating everybody**. It is guarded by `owner_id == 0` there and asserted
## from both directions here: a player's trophy is never reaped, and gaia's orphan still
## is.
extends TestCase

const TROPHY := &"unit.dragon_baby"
const NEST := &"building.dragon_nest"

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()


## A world in `mode`, with `players` seats, built through the REAL `MapGen.build` so the
## placement pass under test is the one a match runs. No `map_data`, so this is the fixed
## debug map -- which is deliberately the harder fixture: it has ONE start position, so
## player 1 gets a town centre and everybody after them gets the skirmish squad instead.
## A trophy has to find ground for both shapes.
func _build(mode: MatchConfig.Mode, players: int = 2,
		teams: Array = []) -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.mode = mode
	cfg.map_size = Vector2i(64, 64)
	for i in range(players):
		cfg.player_ids.append(i + 1)
		cfg.ai_players.append(false)
		cfg.ai_levels.append(int(SimPlayer.AILevel.EASY))
		cfg.teams.append(int(teams[i]) if i < teams.size() else 0)
	w.setup(cfg)
	MapGen.build(w, cfg)
	return cfg


func _trophies_of(owner: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for e in w.entities.values():
		if e is SimUnit and e.def_id == TROPHY and e.owner_id == owner and e.alive:
			out.append(e as SimUnit)
	return out


func _reason_of(pid: int) -> int:
	var p := w.player_for(pid)
	return p.defeat_reason if p != null else -1


# ── the flag, which is what 11.2 asked for instead of a hardcoded id ────────────

func test_the_roster_names_exactly_one_trophy_and_it_is_the_hatchling() -> void:
	# 11.2's third requirement was *"an `is_trophy` flag rather than a hardcoded id"*, and
	# `WinConditionSystem.TROPHY_DEF_ID` -- which was `unit.dragon` -- is deleted. Asserted
	# through the accessor rather than by reading units.json, because the accessor is what
	# every caller uses.
	assert_eq(GameDataRegistry.trophy_def_id(), TROPHY)
	var def: UnitDef = GameDataRegistry.unit(TROPHY)
	assert_not_null(def)
	if def != null:
		assert_true(def.is_trophy)


func test_no_other_unit_in_the_roster_claims_to_be_a_trophy() -> void:
	# ⚠️ **"YOUR TROPHY" HAS TO BE ONE ANSWERABLE QUESTION.** With two trophy defs a player
	# holding either would survive, which is not a rule anybody authored and not one the
	# flag can express. `GameDataRegistry.validate()` warns about it and four separate
	# tests assert `load_warnings.is_empty()`, so this is the direct statement of the same
	# fact -- and it is the one that names the culprit if a second is ever added.
	var flagged: Array[StringName] = []
	for id in GameDataRegistry.unit_ids():
		var def: UnitDef = GameDataRegistry.unit(id)
		if def != null and def.is_trophy:
			flagged.append(id)
	assert_eq(flagged.size(), 1, "exactly one trophy def, found: %s" % str(flagged))


# ── placement: every player, or nobody ─────────────────────────────────────────

func test_trophy_mode_gives_every_player_exactly_one() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	assert_eq(w.trophy_def_id, TROPHY, "and the rule is armed")
	for p in w.players:
		assert_eq(_trophies_of(p.id).size(), 1, "player %d has one trophy" % p.id)


func test_it_works_on_the_debug_map_for_a_player_with_no_town_centre() -> void:
	# THE REASON `_trophy_anchor` IS A LADDER. The debug map has one start position, so
	# player 2 has no building at all -- 11.2's own note says *"the debug map cannot do
	# this for a second player"* about giving everyone a trophy. It can: the anchor falls
	# back to any building, then to anything standing. Without that, placement fails, and
	# because placement is all-or-nothing NOBODY would get a trophy and the mode would be
	# silently inert on the fixture most of the suite runs on.
	_build(MatchConfig.Mode.TROPHY, 2)
	var second := _trophies_of(2)
	assert_eq(second.size(), 1, "player 2 has one even with no base")
	if second.is_empty():
		return
	var own_buildings := 0
	for e in w.entities.values():
		if e is SimBuilding and e.owner_id == 2:
			own_buildings += 1
	assert_eq(own_buildings, 0, "and that really was a player with no building")


func test_no_other_mode_places_a_trophy_or_arms_the_rule() -> void:
	# A trophy in a Last Man Standing match would be a free 300 hp unit at everybody's
	# base, and `is_trophy` would be read by nothing -- so it must not be placed at all.
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.KING_OF_THE_HILL,
			MatchConfig.Mode.SCENARIO]:
		before_each()
		_build(mode, 2)
		assert_eq(w.trophy_def_id, &"", "%s does not arm the trophy rule" % mode)
		for p in w.players:
			assert_eq(_trophies_of(p.id).size(), 0,
					"no trophy for player %d in mode %s" % [p.id, mode])


func test_setup_disarms_a_reused_world() -> void:
	# `preview_ai_match` steps four rungs through ONE world and every dev_preview reuses
	# configs. A trophy match followed by a skirmish would otherwise leave the rule armed
	# with nothing to watch, and the first player to own no hatchling would be defeated.
	_build(MatchConfig.Mode.TROPHY, 2)
	assert_eq(w.trophy_def_id, TROPHY)
	_build(MatchConfig.Mode.LAST_MAN_STANDING, 2)
	assert_eq(w.trophy_def_id, &"", "setup() cleared it")


# ── the rule ───────────────────────────────────────────────────────────────────

func test_losing_your_trophy_puts_you_out_and_the_other_side_wins() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(2)
	assert_eq(mine.size(), 1)
	if mine.is_empty():
		return

	mine[0].take_damage(mine[0].hp, 0, 1)
	w.step()

	assert_true(w.player_for(2).defeated, "player 2 is out")
	assert_eq(_reason_of(2), SimPlayer.Defeat.TROPHY_LOST,
			"and the reason says what happened, not 'eliminated'")
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)


func test_a_player_who_still_holds_their_trophy_is_untouched() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	for t in range(5):
		w.step()
	for p in w.players:
		assert_false(p.defeated, "player %d still holds theirs" % p.id)
	assert_false(w.match_over, "and nothing has been decided")


func test_the_loser_may_still_own_an_army_which_is_the_whole_point() -> void:
	# ⚠️ **THIS IS WHY `TROPHY_LOST` IS A REASON OF ITS OWN.** A player whose hatchling
	# dies can still own a town centre and a field of soldiers, so `ELIMINATED` would be a
	# true statement about the outcome and a false one about how it happened -- the forfeit
	# defect BUGS.md recorded, and the reason `_defeat_phrase` was split out at all.
	_build(MatchConfig.Mode.TROPHY, 2)
	for i in range(4):
		w.spawn_unit(&"unit.militia", 2, Vector2i(30 + i, 40))
	var mine := _trophies_of(2)
	if mine.is_empty():
		return
	mine[0].take_damage(mine[0].hp, 0, 1)
	w.step()

	assert_eq(_reason_of(2), SimPlayer.Defeat.TROPHY_LOST)
	var army := 0
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == 2 and e.alive and e.def_id == &"unit.militia":
			army += 1
	assert_true(army > 0, "defeated with %d soldiers still standing" % army)


func test_owning_nothing_at_all_is_still_ELIMINATED_and_not_a_lost_trophy() -> void:
	# `_eliminate_the_bankrupt` runs FIRST and `defeat()` keeps the first reason, so the
	# ordering of the two rules is the whole of this distinction. A player wiped out
	# entirely lost the ordinary way and should be told so.
	_build(MatchConfig.Mode.TROPHY, 2)
	for e in w.entities.values():
		if (e is SimUnit or e is SimBuilding) and e.owner_id == 2:
			e.alive = false
	w.step()
	assert_true(w.player_for(2).defeated)
	assert_eq(_reason_of(2), SimPlayer.Defeat.ELIMINATED,
			"wiped out is an elimination, even in trophy mode")


func test_a_trophys_CORPSE_does_not_keep_you_in() -> void:
	# A corpse lingers for `SimUnit.CORPSE_TOTAL_TICKS` and every census in
	# `WinConditionSystem` filters on `alive` for this reason. Counting the body would give
	# a beaten player ten more seconds that nothing on screen could explain.
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(2)
	if mine.is_empty():
		return
	mine[0].take_damage(mine[0].hp, 0, 1)
	assert_not_null(w.get_entity(mine[0].id), "the body is still in the world")
	w.step()
	assert_true(w.player_for(2).defeated)


# ── the guard that kept this mode inert for two years ──────────────────────────

func test_trophy_mode_with_NO_trophies_placed_decides_nothing() -> void:
	# ⚠️ **11.2's NAMED FAILURE, asserted directly.** *"'You lose when your trophy dies',
	# on a map with no trophies, defeats everybody on tick 1."* The world is in TROPHY mode
	# and nobody owns a hatchling, which is what a roster with no `is_trophy` unit or
	# ground too tight to seat one produces -- and nobody may be put out for losing a
	# trophy they were never given.
	#
	# WHAT ANSWERS INSTEAD IS CONQUEST, which is why both players are given something to
	# own: an unarmed trophy match falls back to last-man-standing rather than deciding
	# nothing at all, so what this asserts is *no defeat*, not *no rule running*. Two
	# players each holding a militia is two sides standing, and conquest correctly waits.
	# `test_win_condition.test_an_unarmed_trophy_match_falls_back_to_conquest` is the other
	# half, where one of them owns nothing and conquest does decide.
	var cfg := MatchConfig.new()
	cfg.mode = MatchConfig.Mode.TROPHY
	cfg.map_size = Vector2i(48, 48)
	cfg.player_ids = [1, 2]
	cfg.ai_players = [false, false]
	cfg.ai_levels = [0, 0]
	cfg.teams = [0, 0]
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)
	# Something to own, so `_eliminate_the_bankrupt` is not what decides this.
	w.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.militia", 2, Vector2i(30, 30))
	assert_eq(w.trophy_def_id, &"", "nothing armed the rule")

	for t in range(5):
		w.step()

	for p in w.players:
		assert_false(p.defeated, "player %d must not lose a trophy they were never given"
				% p.id)
	assert_false(w.match_over)


func test_the_arming_record_is_the_placement_and_not_the_roster_flag() -> void:
	# The roster flag is set -- `unit.dragon_baby` declares `is_trophy` -- and the world is
	# in trophy mode, and the rule is STILL inert, because nothing placed anything. That
	# separation is the whole design: `GameDataRegistry.trophy_def_id()` answers "which
	# unit", `SimWorld.trophy_def_id` answers "is there a trophy match here to decide".
	assert_ne(GameDataRegistry.trophy_def_id(), &"", "the roster does declare one")
	var cfg := MatchConfig.new()
	cfg.mode = MatchConfig.Mode.TROPHY
	cfg.map_size = Vector2i(32, 32)
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	w.setup(cfg)
	assert_eq(w.trophy_def_id, &"",
			"the flag on the def does not arm a match on its own")


# ── teams: the mode decides SIDES, like every other mode ───────────────────────

func test_an_ally_still_holding_a_trophy_keeps_the_side_alive() -> void:
	# `_decide_by_sides` is shared with conquest precisely so the two cannot drift about
	# this. Killing one member of a pair must not end a 2v2 -- the same failure teams
	# introduced into last-man-standing on 2026-08-31, which ran forever.
	_build(MatchConfig.Mode.TROPHY, 4, [1, 1, 2, 2])
	var first := _trophies_of(1)
	if first.is_empty():
		return
	first[0].take_damage(first[0].hp, 0, 3)
	w.step()

	assert_true(w.player_for(1).defeated, "player 1 lost their trophy")
	assert_false(w.match_over, "but their team-mate still has one")


func test_a_side_with_no_trophies_left_loses_to_the_other_side() -> void:
	_build(MatchConfig.Mode.TROPHY, 4, [1, 1, 2, 2])
	for pid in [1, 2]:
		for t in _trophies_of(pid):
			t.take_damage(t.hp, 0, 3)
	w.step()

	assert_true(w.match_over)
	assert_eq(w.winner_team, 2, "team 2 took it")
	assert_eq(w.winner_id, 3, "and winner_id is the lowest-id survivor of that side")


# ── the 13.2 collision, from both directions ───────────────────────────────────

func test_a_players_trophy_is_never_reaped_as_an_orphan_hatchling() -> void:
	# ⚠️ **THE TEST THIS WHOLE FEATURE HANGS ON.** `NestSystem` collects hatchlings and
	# `_reap_orphans` kills every one no nest has recorded. A trophy is recorded on no
	# nest, so before the `owner_id == 0` filter this killed every trophy in the game on
	# tick 1 -- and since losing your trophy is defeat, that eliminated the entire lobby.
	# Note there is no nest on this map at all: the reap does not need one to fire.
	_build(MatchConfig.Mode.TROPHY, 2)
	for t in range(10):
		w.step()
	for p in w.players:
		assert_eq(_trophies_of(p.id).size(), 1,
				"player %d's trophy survived ten ticks" % p.id)
		assert_false(p.defeated)


func test_a_trophy_standing_at_a_nest_is_still_not_the_nests_business() -> void:
	# The nearer miss: a trophy inside the footprint of a real dragon nest, which is where
	# `_nest_for` and `_reap_orphans` both look. Ownership is the only thing telling them
	# apart, and it has to be enough.
	_build(MatchConfig.Mode.TROPHY, 2)
	var nest := w.spawn_building(NEST, 0, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	assert_not_null(nest, "a nest was stood up")
	if nest == null:
		return
	# STOOD ON THE NEST ITSELF, which is the exact tile `_start_claims` spawns a real
	# hatchling on. Spawned there rather than moved there, because writing `pos` by hand
	# would be this file guessing at a sub-tile conversion it has no business knowing.
	var at_nest := w.spawn_unit(TROPHY, 1, nest.tile())
	assert_not_null(at_nest)
	if at_nest == null:
		return
	for t in range(10):
		w.step()

	assert_true(at_nest.alive, "a player's hatchling on a nest is not that nest's")
	assert_eq(nest.claim_baby_id, 0, "and the nest never adopted it")
	assert_false(w.player_for(1).defeated)


func test_gaias_orphaned_hatchling_IS_still_reaped() -> void:
	# THE OTHER DIRECTION, and the reason the filter is `owner_id == 0` rather than the
	# reap being deleted. `_reap_orphans` exists so a hatchling whose nest vanished by
	# some route other than falling does not sit there forever growing into nothing -- and
	# narrowing it to gaia must not turn it off.
	_build(MatchConfig.Mode.LAST_MAN_STANDING, 2)
	var orphan := w.spawn_unit(TROPHY, 0, Vector2i(25, 25))
	assert_not_null(orphan)
	if orphan == null:
		return
	for t in range(3):
		w.step()
	assert_false(orphan.alive, "gaia's unclaimed hatchling is still swept up")


func test_gaias_hatchling_satisfies_nobodys_trophy() -> void:
	# `_trophy_holders` filters `owner_id > 0`. Harmless today because gaia is never in
	# `standing`, and written anyway: the day something puts gaia in a side, this would be
	# a rule keeping the wildlife in the match.
	_build(MatchConfig.Mode.TROPHY, 2)
	w.spawn_unit(TROPHY, 0, Vector2i(25, 25))
	var mine := _trophies_of(2)
	if mine.is_empty():
		return
	mine[0].take_damage(mine[0].hp, 0, 1)
	w.step()
	assert_true(w.player_for(2).defeated,
			"gaia's hatchling is not player 2's trophy")
