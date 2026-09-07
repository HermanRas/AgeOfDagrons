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


# ── one dragon per player, and no others ───────────────────────────────────────

## A GENERATED map, which is the only kind that carries a nest. `_build` above uses the
## fixed debug map deliberately (see its comment) and there is no nest on it at all, so
## every test in this section needs the other fixture.
func _build_generated(mode: MatchConfig.Mode, players: int = 2) -> MatchConfig:
	var cfg := MatchConfig.debug_generated(7, MapGenerator.Type.FOREST, players)
	cfg.mode = mode
	w.setup(cfg)
	MapGen.build(w, cfg)
	return cfg


func _gaia_nests() -> int:
	var n := 0
	for e in w.entities.values():
		if e is SimBuilding and e.def_id == NEST and e.owner_id == 0 and e.alive:
			n += 1
	return n


func _gaia_guardians() -> int:
	var n := 0
	for e in w.entities.values():
		if not (e is SimUnit) or e.owner_id != 0 or not e.alive:
			continue
		var def := w.unit_def((e as SimUnit).def_id)
		if def != null and def.guards_post:
			n += 1
	return n


func test_the_fixture_really_does_put_a_nest_and_a_mother_on_a_generated_map() -> void:
	# ⚠️ **THE CONTROL, AND WITHOUT IT THE NEXT TEST PROVES NOTHING.** "No nest in trophy
	# mode" passes trivially on a map that never had one, which is exactly the trap the
	# debug-map fixture would have set. This is the same seed and the same player count as
	# the removal test below, in the mode that keeps its nest.
	_build_generated(MatchConfig.Mode.LAST_MAN_STANDING, 2)
	assert_eq(_gaia_nests(), 1, "13.2a puts one nest on a generated map")
	assert_eq(_gaia_guardians(), 1, "and one mother guarding it")


func test_a_trophy_match_has_no_gaia_nest_and_no_mother() -> void:
	# The owner's call, 2026-09-07: *"no second dragon on trophy map type. only 1 per
	# player."* A free 600 hp flyer to whoever kills the mother is a large swing in a mode
	# whose whole subject is protecting a 300 hp one -- and the two hatchlings are the same
	# def and the same picture, so the board would show one player two identical dragons
	# that mean different things. `MapGen._clear_dragon_nest` has the argument.
	_build_generated(MatchConfig.Mode.TROPHY, 2)
	assert_eq(w.trophy_def_id, TROPHY, "the mode is armed")
	assert_eq(_gaia_nests(), 0, "the nest is off the map")
	assert_eq(_gaia_guardians(), 0, "and so is the mother")
	# AND THE COUNT IS THE OWNER'S SENTENCE, stated as one number: every dragon on this map
	# belongs to a player, and each player has exactly one.
	var dragons := 0
	for e in w.entities.values():
		if e is SimUnit and e.alive and (e.def_id == TROPHY or e.def_id == &"unit.dragon"):
			dragons += 1
			assert_true(e.owner_id > 0, "every dragon on the map is somebody's")
	assert_eq(dragons, w.players.size(), "one dragon per player, and no others")


func test_the_mother_goes_with_the_nest_and_not_on_her_own() -> void:
	# ⚠️ **LEAVING HER WOULD BE WORSE THAN LEAVING BOTH.** She is `guards_post`, so
	# `WildlifeSystem` re-homes her on the nearest gaia building -- some unrelated rock --
	# and `NestSystem._nest_for` then answers null, so killing her drops nothing at all. A
	# 600 hp dragon guarding scenery and paying out nothing is a rule a player cannot learn.
	# Ten ticks so `WildlifeSystem` has actually looked at whatever is left.
	_build_generated(MatchConfig.Mode.TROPHY, 2)
	for t in range(10):
		w.step()
	assert_eq(_gaia_guardians(), 0, "no guardian survived the removal")
	assert_false(w.match_over, "and taking her off the map decided nothing")


func test_a_conquest_match_KEEPS_its_nest_even_though_the_pass_ran() -> void:
	# ⚠️ **GUARDED ON `w.trophy_def_id`, NOT ON `cfg.mode`.** Placement is all-or-nothing and
	# leaves the field empty when it could not arm the mode, in which case the match is
	# decided by CONQUEST -- and a conquest match has every reason to keep its nest. Reading
	# the mode here would strip 13.2's whole feature off a map that then played as an
	# ordinary skirmish, which nothing on screen would explain.
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.KING_OF_THE_HILL,
			MatchConfig.Mode.SCENARIO]:
		before_each()
		_build_generated(mode, 2)
		assert_eq(w.trophy_def_id, &"")
		assert_eq(_gaia_nests(), 1, "mode %s keeps its nest" % mode)
		assert_eq(_gaia_guardians(), 1, "mode %s keeps its mother" % mode)


# ── you can move it (owner, 2026-09-07) ────────────────────────────────────────

## ⚠️ **THE TROPHY IS A UNIT YOU SHEPHERD, NOT A STATUE YOU WALL IN.** Owner's call: *"it
## can stay small but let me move it around."* `unit.dragon_baby` was `speed: 0` because
## 13.2's hatchling is a prize sitting in a nest, and that zero was **belt and braces** on
## top of the two things that actually keep that one still -- it is gaia's and every move
## command is owner-gated, and its roam radius is 0 so `WildlifeSystem` has nowhere to send
## it. Removing the braces is what makes a trophy movable without touching the claim.
func test_the_owner_can_walk_their_trophy_across_the_map() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(1)
	assert_eq(mine.size(), 1)
	if mine.is_empty():
		return
	var t := mine[0]
	assert_true(t.speed > 0, "a trophy that cannot move cannot be moved")
	var from := t.tile()
	var to := from + Vector2i(6, 6)

	w.queue_command(MoveCommand.new(1, [t.id], to))
	for i in range(200):
		w.step()
		if t.tile() == to:
			break

	assert_ne(t.tile(), from, "it left the tile it started on")
	assert_true(t.alive, "and it is still alive, which the reap once was not")
	assert_false(w.player_for(1).defeated, "and moving it is not losing it")


func test_a_trophy_cannot_be_ordered_by_somebody_else() -> void:
	# Owner-gating is what keeps 13.2's gaia hatchling still now that the def has a speed,
	# so it is worth one assertion that the gate is real and not just conventional. Player 2
	# ordering player 1's dragon must do nothing at all.
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(1)
	if mine.is_empty():
		return
	var t := mine[0]
	var from := t.tile()
	w.queue_command(MoveCommand.new(2, [t.id], from + Vector2i(8, 8)))
	for i in range(20):
		w.step()
	assert_eq(t.tile(), from, "player 2 cannot walk player 1's trophy anywhere")


func test_gaias_claim_hatchling_still_does_not_move_now_that_the_def_has_a_speed() -> void:
	# ⚠️ **THE REGRESSION THE SPEED COULD HAVE CAUSED, asserted from the trophy side too.**
	# 13.2's whole tension is that *what the claimant owns during the window is a promise and
	# what they have to defend is a place* -- a hatchling that wanders off its nest is a
	# claim nobody has to hold. It is gaia's, so no move command can name it, and its
	# `roam_radius` is 0, so `WildlifeSystem` has nowhere to send it.
	_build(MatchConfig.Mode.LAST_MAN_STANDING, 2)
	var nest := w.spawn_building(NEST, 0, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	if nest == null:
		return
	var baby := w.spawn_unit(TROPHY, 0, nest.tile())
	if baby == null:
		return
	nest.claim_baby_id = baby.id
	nest.claim_owner = 1
	nest.claim_ticks_left = NestSystem.GROW_TICKS
	var from := baby.tile()

	# Both roads at once: an order from a player, and thirty ticks of the wildlife system
	# having every chance to pick a destination.
	w.queue_command(MoveCommand.new(1, [baby.id], from + Vector2i(9, 9)))
	for i in range(30):
		w.step()

	assert_true(baby.alive, "it is still the nest's hatchling")
	assert_eq(baby.tile(), from, "gaia's hatchling stays on its nest")


## ⚠️ **A TROPHY CANNOT BE HIDDEN IN A TOWER, AND THIS MODE IS WHY THAT RULE EXISTS.**
##
## This test asserted the OPPOSITE for about an hour, and the history is the point. Making
## the trophy movable put "walk the dragon into the castle" on the table: 15 slots of stone,
## untargetable until the stone falls, which would have made a mode about defending a place
## into a mode about parking. It was reported as a play question the same afternoon and the
## owner answered it -- *"dragon cannot garison"* -- which is PLAN.md 4.8c, and 4.8c is what
## made the state this test was written around unreachable. **The failing test is what
## reported the rule had landed**, and it is rewritten rather than deleted so the
## interaction is still recorded where somebody hunting it would look.
func test_a_trophy_cannot_be_hidden_inside_a_tower() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(1)
	if mine.is_empty():
		return
	var t := mine[0]
	var tower := w.spawn_building(&"building.guard_tower", 1, t.tile() + Vector2i(3, 0),
			SimBuilding.Phase.COMPLETE, true)
	assert_not_null(tower)
	if tower == null:
		return
	assert_true(tower.garrison_cap > 0, "the fixture really is a carrier")

	assert_false(GarrisonCommand.new(1, [t.id], tower.id).validate(w),
			"the order is refused outright")
	w.queue_command(GarrisonCommand.new(1, [t.id], tower.id))
	for i in range(60):
		w.step()

	assert_eq(t.garrisoned_in, 0, "and it never got inside")
	assert_true(tower.garrison.is_empty())
	assert_true(t.alive, "it is still standing in the open, where it can be defended")
	assert_false(w.player_for(1).defeated, "and refusing the order is not losing")


## ⚠️ **AND THE CENSUS STILL MUST NOT BE SPATIAL, which 4.8c did not make safe -- it only
## made one route to it unreachable.** `_trophy_holders` walks `w.entities` and filters on
## `alive`. If it counted what the SPATIAL INDEX can see instead, any trophy off the map but
## alive would defeat its owner, and being garrisoned is not the only way a unit leaves that
## index. `spatial.remove` is what garrisoning itself calls, so this is the same state by the
## shortest honest road, without forging garrison bookkeeping no rule would have written.
func test_a_trophy_that_is_alive_but_off_the_spatial_index_still_counts() -> void:
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(1)
	if mine.is_empty():
		return
	var t := mine[0]
	w.spatial.remove(t.id)
	for i in range(5):
		w.step()

	assert_true(t.alive)
	assert_false(w.player_for(1).defeated,
			"alive and owned is held, wherever the entity can be seen from")
	assert_false(w.match_over)


# ── the trophy does not grow up, and must not ──────────────────────────────────

func test_a_trophy_never_grows_up_even_after_the_full_claim_window() -> void:
	# ⚠️ **OWNER-OBSERVED 2026-09-07 -- *"my dragon never grew up"* -- AND IT MUST NOT.**
	# Growing means `NestSystem` replacing the hatchling with a `unit.dragon`, and that def
	# does NOT carry `is_trophy`: the owner would be holding no trophy on the next tick and
	# would be defeated on the spot, in a mode they were winning, by their own dragon
	# succeeding. So "it never grew" is not a missing feature, it is the feature.
	#
	# TWO SEPARATE THINGS GUARANTEE IT and this asserts the outcome rather than either: the
	# hatchling is player-owned so `NestSystem` does not collect it at all, and it is
	# recorded on no nest so no claim can mature into it. Run past the FULL window, because
	# a growth that happens at `GROW_TICKS` is invisible to the ten-tick tests above.
	_build(MatchConfig.Mode.TROPHY, 2)
	var mine := _trophies_of(2)
	assert_eq(mine.size(), 1)
	if mine.is_empty():
		return
	var id := mine[0].id

	for t in range(NestSystem.GROW_TICKS + 20):
		w.step()
		if w.match_over:
			break

	assert_false(w.match_over, "six minutes of holding a trophy decides nothing")
	var still := w.get_entity(id) as SimUnit
	assert_not_null(still, "the same entity is still there -- growing REPLACES it")
	if still != null:
		assert_eq(still.def_id, TROPHY, "still a hatchling")
		assert_true(still.alive)
	assert_false(w.player_for(2).defeated, "and its owner is still in the match")


func test_the_grown_dragon_is_not_a_trophy_which_is_why_growing_would_lose() -> void:
	# The mechanism behind the test above, stated as a fact about the roster rather than as
	# 3600 ticks. If somebody ever flags `unit.dragon` as a trophy to "fix" the hatchling not
	# growing, `test_no_other_unit_in_the_roster_claims_to_be_a_trophy` fails and this says
	# why that was the wrong fix.
	var grown: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_not_null(grown)
	if grown != null:
		assert_false(grown.is_trophy,
				"a grown dragon is not a trophy, so growing one would end its owner's match")


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
