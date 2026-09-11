## KING OF THE HILL (PLAN.md 11.2, card 11.x-koth): hold the zone, score, and win.
##
## `test_win_condition.gd` owns the UNARMED mode — a KotH match on a map with no hill falls back to
## conquest — and this owns the armed one. The split is `test_trophy.gd`'s, for its reason: the
## fallback is a property of the whole file's dispatch and the rule is a thing in itself.
##
## ## WHAT THIS ROW COULD BE QUIETLY WRONG ABOUT
##
##   - **the zone reaching the world at all.** Two sources resolve into one field
##     (`MapGen._place_koth_zone`), and a branch that silently produced nothing would leave the
##     mode falling back to conquest — a KotH match that plays exactly like a skirmish and never
##     says why.
##   - **who counts.** A garrisoned unit's `pos` is deliberately stale and it is off the map
##     entirely, so a tower full of archers inside the zone would hold the hill with five men
##     nobody can see, target or shoot. Gaia's deer would be a side of their own.
##   - **sides, not players.** Two allies with four units each against one enemy's six hold it
##     between them; a rule comparing players hands the tick to the enemy.
##   - **a tie paying somebody.** Most units holds it, so a stalemate must pay NOBODY — otherwise
##     a 5-v-5 standoff is the fastest route to the target.
##   - **the score surviving the wire and the hash.** It is a RUNNING TOTAL, so one tick of
##     disagreement between two hosts is permanent and silent.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = _world([0, 0])


## A two-player KotH world with a hill in the middle of a 48x48 map.
##
## THE ZONE IS SET DIRECTLY HERE and through `MapGen._place_koth_zone()` in the placement section
## below. The rule and the placer are two things: most of this file is about what the rule does
## with a zone, and putting the placer in every fixture would make each of these tests also a test
## of map generation.
func _world(teams: Array[int]) -> SimWorld:
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = teams
	cfg.map_size = Vector2i(48, 48)
	cfg.mode = MatchConfig.Mode.KING_OF_THE_HILL
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	world.koth_zone = Rect2i(20, 20, 8, 8)
	return world


func _world_of(count: int, teams: Array[int]) -> SimWorld:
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = []
	for i in range(count):
		cfg.player_ids.append(i + 1)
	cfg.teams = teams
	cfg.map_size = Vector2i(48, 48)
	cfg.mode = MatchConfig.Mode.KING_OF_THE_HILL
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	world.koth_zone = Rect2i(20, 20, 8, 8)
	return world


## Everybody owns something well away from the hill, so the world is POPULATED and nobody is
## eliminated by the conquest half while a scoring test runs.
func _keep_everyone_alive(world: SimWorld) -> void:
	var at := 2
	for p in world.players:
		world.spawn_unit(&"unit.villager", p.id, Vector2i(at, 2))
		at += 3


func _on_hill(world: SimWorld, owner: int, count: int, from := Vector2i(21, 21)) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for i in range(count):
		out.append(world.spawn_unit(&"unit.villager", owner, from + Vector2i(i, 0)))
	return out


# ── the scoring rule ────────────────────────────────────────────────────────

func test_holding_the_hill_alone_scores_every_tick() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	for i in range(5):
		w.step()
	assert_eq(w.player_for(1).score, 5, "one point a tick")
	assert_eq(w.player_for(2).score, 0, "and nothing for the player who is not there")
	assert_eq(w.koth_holder, 1)


## **MOST units, not merely presence** — the rule's own sentence, and the half a presence test
## would pass while getting completely wrong.
func test_the_larger_force_holds_a_shared_hill() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 3)
	_on_hill(w, 2, 2, Vector2i(21, 23))
	for i in range(4):
		w.step()
	assert_eq(w.player_for(1).score, 4)
	assert_eq(w.player_for(2).score, 0)
	assert_eq(w.koth_holder, 1)


## ⚠️ **A TIE PAYS NOBODY.** Two sides with equal numbers are CONTESTING the hill, not sharing it —
## and paying both would make a stalemate the fastest way to `KOTH_TARGET_SCORE`, which is the
## version of this rule that gets played by parking two armies on a square and waiting.
func test_a_contested_hill_pays_nobody_and_has_no_holder() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 2)
	_on_hill(w, 2, 2, Vector2i(21, 23))
	for i in range(6):
		w.step()
	assert_eq(w.player_for(1).score, 0)
	assert_eq(w.player_for(2).score, 0)
	assert_eq(w.koth_holder, 0, "nobody holds a contested hill")


func test_an_empty_hill_pays_nobody() -> void:
	_keep_everyone_alive(w)
	for i in range(5):
		w.step()
	assert_eq(w.player_for(1).score, 0)
	assert_eq(w.koth_holder, 0)


func test_a_unit_outside_the_zone_is_not_on_the_hill() -> void:
	_keep_everyone_alive(w)
	# ONE TILE OUTSIDE, on each of the two edges `end` makes easy to get wrong: `koth_zone` is
	# (20,20) 8x8, so tiles 20..27 are in and 19 and 28 are out. An off-by-one on the exclusive
	# `end` is the mistake, and it is invisible in play.
	w.spawn_unit(&"unit.villager", 1, Vector2i(19, 21))
	w.spawn_unit(&"unit.villager", 1, Vector2i(28, 21))
	w.step()
	assert_eq(w.player_for(1).score, 0, "just outside is outside")

	w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_eq(w.player_for(1).score, 1, "and the near corner is inside")
	w.spawn_unit(&"unit.villager", 1, Vector2i(27, 27))
	w.step()
	assert_eq(w.player_for(1).score, 2, "as is the far one")


## ⚠️ **A GARRISONED UNIT IS OFF THE MAP AND HOLDS NO GROUND.** `SimUnit.garrisoned_in` leaves
## `SpatialHash`, is skipped by `SnapshotSystem` entirely, and its `pos` is deliberately frozen
## wherever it stood — so a tower inside the zone stuffed with archers would otherwise hold the
## hill with five men nobody can see, target or shoot. That is the opposite of a contested zone.
func test_garrisoned_units_do_not_hold_the_hill() -> void:
	_keep_everyone_alive(w)
	var men := _on_hill(w, 1, 2)
	w.step()
	assert_eq(w.player_for(1).score, 1)

	for u in men:
		u.garrisoned_in = 999          # a tower id; nothing here reads it back
	w.step()
	assert_eq(w.player_for(1).score, 1, "hiding indoors is not holding the ground")
	assert_eq(w.koth_holder, 0)


## Gaia's wildlife is not a side. Without the `owner_id > 0` clause a herd of deer on the hill
## would key at side 0 and could deny the zone to everybody — the same clause `_trophy_holders`
## carries, for the same reason: gaia is not in the match.
func test_gaia_wildlife_neither_holds_the_hill_nor_denies_it() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 0, 5)
	_on_hill(w, 1, 1, Vector2i(21, 24))
	w.step()
	assert_eq(w.player_for(1).score, 1, "one villager outnumbers any number of deer")
	assert_eq(w.koth_holder, 1)


## Buildings do not hold ground either: this is a rule about who is STANDING there, and a rule
## counting buildings would let a player win by walling the hill and walking away.
func test_a_building_on_the_hill_does_not_hold_it() -> void:
	_keep_everyone_alive(w)
	w.spawn_building(&"building.house", 1, Vector2i(21, 21),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_eq(w.player_for(1).score, 0)
	assert_eq(w.koth_holder, 0)


# ── sides, not players ──────────────────────────────────────────────────────

## ⚠️ **TWO ALLIES HOLD THE HILL BETWEEN THEM.** Four units each against one enemy's six is a
## losing comparison per player and a winning one per side, and the rule that compares players
## hands the tick to the enemy — which is the same defect `_last_man_standing` had before it
## counted sides, arriving through a different rule.
func test_allies_pool_their_strength_on_the_hill() -> void:
	var world := _world_of(3, [1, 1, 0])
	_keep_everyone_alive(world)
	_on_hill(world, 1, 2)
	_on_hill(world, 2, 2, Vector2i(21, 23))
	_on_hill(world, 3, 3, Vector2i(21, 25))
	world.step()

	assert_eq(world.player_for(1).score, 1, "four between the allies beats three")
	assert_eq(world.player_for(2).score, 1, "and BOTH of them score it")
	assert_eq(world.player_for(3).score, 0)
	# THE LOWEST-ID SURVIVOR OF THE LEADING SIDE, `_decide_by_sides`' own convention.
	assert_eq(world.koth_holder, 1)


## 0 is the ABSENCE of a team rather than one everybody shares — `Diplomacy`'s rule, and without
## it every unaligned player in the game would be one enormous side holding every hill together.
func test_two_unaligned_players_are_two_sides() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	_on_hill(w, 2, 1, Vector2i(21, 23))
	w.step()
	assert_eq(w.player_for(1).score, 0, "one each is contested, not shared")
	assert_eq(w.player_for(2).score, 0)


# ── winning ─────────────────────────────────────────────────────────────────

func test_reaching_the_target_ends_the_match() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	# STARTED JUST SHORT rather than stepped a thousand times: the tally is a counter and this
	# test is about what happens when it arrives, not about the counting.
	w.player_for(1).score = WinConditionSystem.KOTH_TARGET_SCORE - 1
	w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)
	assert_eq(w.winner_team, 0, "a free-for-all has no winning team")
	assert_false(w.player_for(1).defeated)


func test_a_teams_win_names_the_team_as_well_as_a_player() -> void:
	var world := _world_of(3, [2, 2, 0])
	_keep_everyone_alive(world)
	_on_hill(world, 2, 1)
	world.player_for(2).score = WinConditionSystem.KOTH_TARGET_SCORE - 1
	world.player_for(1).score = WinConditionSystem.KOTH_TARGET_SCORE - 1
	world.step()
	assert_true(world.match_over)
	assert_eq(world.winner_team, 2)
	assert_eq(world.winner_id, 1, "the lowest-id survivor of the winning side")


## Conquest still ends a KotH match, which is not a fallback but both rules at once: without it two
## players who annihilated each other would leave a match nobody can score and nobody can end.
func test_wiping_out_the_opposition_wins_without_waiting_out_the_tally() -> void:
	_keep_everyone_alive(w)
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == 2:
			e.alive = false
	for i in range(3):
		w.step()
	assert_true(w.match_over)
	assert_eq(w.winner_id, 1)
	assert_true(w.player_for(2).defeated)
	assert_eq(w.player_for(2).defeat_reason, SimPlayer.Defeat.ELIMINATED)


## ⚠️ **A PLAYER ELIMINATED THIS TICK MUST NOT SCORE.** They can still have units standing on the
## hill — a player whose last BUILDING fell is bankrupt with an army intact — so scoring off the
## zone tally rather than off `standing` would tick a defeated player towards a win.
func test_a_defeated_player_holding_the_hill_scores_nothing() -> void:
	var world := _world_of(3, [0, 0, 0])
	_keep_everyone_alive(world)
	_on_hill(world, 2, 4)
	# PLAYER 2 OWNS ONLY WHAT IS ON THE HILL, and then loses it while the bodies stay there for
	# `_zone_strength` to skip and `_eliminate_the_bankrupt` to act on.
	for e in world.entities.values():
		if e is SimUnit and e.owner_id == 2 and not world.koth_zone.has_point(e.tile()):
			e.alive = false
	world.step()
	assert_false(world.player_for(2).defeated, "still standing: the hill units are alive")

	for e in world.entities.values():
		if e is SimUnit and e.owner_id == 2:
			e.alive = false
	var before := world.player_for(2).score
	world.step()
	assert_true(world.player_for(2).defeated)
	assert_eq(world.player_for(2).score, before, "a defeated player scores nothing more")


func test_a_result_is_not_overwritten_by_the_ticks_after_it() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	w.player_for(1).score = WinConditionSystem.KOTH_TARGET_SCORE - 1
	w.step()
	assert_true(w.match_over)
	var settled := w.player_for(1).score
	for i in range(5):
		w.step()
	assert_eq(w.winner_id, 1)
	assert_eq(w.player_for(1).score, settled, "the tally stops with the match")


func test_a_solo_sandbox_is_never_decided() -> void:
	var world := _world_of(1, [0])
	_keep_everyone_alive(world)
	_on_hill(world, 1, 1)
	for i in range(5):
		world.step()
	assert_false(world.match_over, "one player is not a match, whatever they are standing on")
	assert_eq(world.player_for(1).score, 0)


func test_an_empty_world_decides_nothing() -> void:
	for i in range(5):
		w.step()
	assert_false(w.match_over, "a world that was never stood up is not a draw")


# ── where the hill comes from (MapGen._place_koth_zone) ─────────────────────

func _built(mode: MatchConfig.Mode, data: MapData) -> SimWorld:
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.mode = mode
	cfg.map_data = data
	cfg.map_size = data.size
	world.setup(cfg)
	MapGen.build(world, cfg)
	return world


func _blank_map(size := Vector2i(64, 64)) -> MapData:
	return MapData.create(size, SimMap.Terrain.GRASS)


## ⚠️ **THE AUTHORED BRANCH — AND IT IS THE ONE THAT COULD SILENTLY NOT EXIST.** 16.5 lets an
## author drag a region out and name it; if `_place_koth_zone` did not read it, the hill would be
## generated at the centre instead and the authored one ignored. That is 16.3's *work lost behind a
## successful save* wearing a win condition, and it would look completely normal on screen.
func test_an_authored_region_is_the_hill() -> void:
	var data := _blank_map()
	data.add_area(MapData.KOTH_AREA, Rect2i(4, 5, 6, 7))
	var world := _built(MatchConfig.Mode.KING_OF_THE_HILL, data)
	assert_eq(world.koth_zone, Rect2i(4, 5, 6, 7))


## A region is the UNION of the entries sharing its name (16.5), and the zone is one rect — so the
## hill is their bounding box. A placer taking only the first or the last would silently halve a
## two-part hill an author drew deliberately.
func test_a_multi_rectangle_region_becomes_its_bounding_box() -> void:
	var data := _blank_map()
	data.add_area(MapData.KOTH_AREA, Rect2i(10, 10, 4, 4))
	data.add_area(MapData.KOTH_AREA, Rect2i(20, 18, 4, 4))
	var world := _built(MatchConfig.Mode.KING_OF_THE_HILL, data)
	assert_eq(world.koth_zone, Rect2i(10, 10, 14, 12))


## The other half of the owner's *"both"* ruling: a map that named no hill still gets one, or every
## skirmish — which is every generated map — would play KotH as conquest.
func test_a_map_with_no_region_gets_a_generated_hill_at_the_centre() -> void:
	var world := _built(MatchConfig.Mode.KING_OF_THE_HILL, _blank_map())
	var r := WinConditionSystem.KOTH_ZONE_RADIUS_TILES
	assert_eq(world.koth_zone.size, Vector2i(2 * r + 1, 2 * r + 1),
			"a square of the half-extent, not a disc")
	assert_true(world.koth_zone.has_point(Vector2i(32, 32)), "and it is in the middle")


## A region named anything else is an author's own business and must not arm the mode — the whole
## point of `MapData.KOTH_AREA` being one declared spelling rather than a guess at intent.
func test_a_region_by_another_name_is_not_the_hill() -> void:
	var data := _blank_map()
	data.add_area(&"north_pass", Rect2i(4, 5, 6, 7))
	var world := _built(MatchConfig.Mode.KING_OF_THE_HILL, data)
	assert_false(world.koth_zone.has_point(Vector2i(4, 5)),
			"the author's own region is not the hill")
	assert_true(world.koth_zone.size.x > 0, "and the generated one was placed instead")


## ⚠️ **A HILL ON A CONQUEST MAP IS GROUND NOTHING READS**, and computing one anyway would put a
## ring on the minimap of a match with no hill in it.
func test_no_other_mode_gets_a_hill() -> void:
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.TROPHY,
			MatchConfig.Mode.SCENARIO]:
		var data := _blank_map()
		data.add_area(MapData.KOTH_AREA, Rect2i(4, 5, 6, 7))
		assert_eq(_built(mode, data).koth_zone, Rect2i(),
				"%s must not arm a hill" % MatchConfig.Mode.keys()[mode])


## All or nothing, `_place_trophies`' rule: a board with no room leaves the mode unarmed and the
## match is decided by conquest, rather than scoring a zone that does not fit on it.
func test_a_map_too_small_for_a_hill_leaves_the_mode_unarmed() -> void:
	var tiny := MapData.create(Vector2i(8, 8), SimMap.Terrain.GRASS)
	assert_eq(_built(MatchConfig.Mode.KING_OF_THE_HILL, tiny).koth_zone, Rect2i())


## ⚠️ **A REUSED WORLD MUST NOT KEEP THE LAST MATCH'S HILL.** `preview_ai_match` steps four rungs
## through one world, so a KotH match followed by a skirmish would otherwise leave the skirmish
## armed and scoring a zone nobody is playing for.
func test_setting_a_world_up_again_forgets_the_hill() -> void:
	assert_true(w.koth_zone.size.x > 0)
	var plain := MatchConfig.new()
	plain.player_ids = [1, 2]
	plain.map_size = Vector2i(48, 48)
	w.setup(plain)
	assert_eq(w.koth_zone, Rect2i())
	assert_eq(w.koth_holder, 0)


# ── the wire and the hash ───────────────────────────────────────────────────

func test_the_hill_and_the_tally_ride_the_snapshot() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	for i in range(3):
		w.step()

	var snap := SnapshotSystem.build(w, 1)
	assert_eq(int(snap["koth_x"]), w.koth_zone.position.x)
	assert_eq(int(snap["koth_y"]), w.koth_zone.position.y)
	assert_eq(int(snap["koth_w"]), w.koth_zone.size.x)
	assert_eq(int(snap["koth_h"]), w.koth_zone.size.y)
	assert_eq(int(snap["koth_holder"]), 1)
	var state: Dictionary = snap["player_state"]
	assert_eq(int((state[1] as Dictionary)["score"]), 3)
	assert_eq(int((state[2] as Dictionary)["score"]), 0)


## ⚠️ **THE CLIENT READS THE HILL OFF THE WIRE AND NEVER COUNTS IT.** Half the units in a contested
## zone are in fog for every player but their owner, so a client tallying it would draw a different
## ring from the server's verdict. This is the reader that makes that possible.
func test_the_view_takes_the_hill_from_the_snapshot() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	w.step()

	var view := GameView.new()
	view.apply_snapshot(SnapshotSystem.build(w, 1))
	assert_eq(view.koth_zone(), w.koth_zone)
	assert_eq(view.koth_holder(), 1)

	# A BARE SNAPSHOT KEEPS WHAT IT HAD, the claim block's rule: a test or a preview handing over
	# `{"updated": [...]}` must not silently take the ring off the minimap.
	view.apply_snapshot({"updated": []})
	assert_eq(view.koth_zone(), w.koth_zone)

	# `test_game_view`'s teardown, copied rather than shortened: a `GameView` owns five child nodes
	# that are not in a tree here, so a bare `view.free()` leaks all five and the suite reports it
	# as ObjectDB instances at exit -- somebody else's problem to diagnose.
	view.pool.free()
	view.terrain.free()
	view.fog.free()
	view.spent.free()
	view.blasts.free()
	view.free()


## The tally is a RUNNING TOTAL, so one tick of disagreement between two hosts is permanent and
## silent — they would agree about every entity in the world for the rest of the match and hand it
## to the same player several seconds apart.
func test_the_score_is_folded_into_the_state_hash() -> void:
	_keep_everyone_alive(w)
	_on_hill(w, 1, 1)
	w.step()
	var before := w.state_hash()
	w.player_for(1).score += 1
	assert_ne(w.state_hash(), before, "a score two hosts disagree about must change the hash")


## Two identical worlds stepped the same way reach the same tally, which is the property the hash
## is checking for and the one a `Dictionary` iteration order could quietly break.
func test_the_same_match_run_twice_scores_identically() -> void:
	var a := _world([0, 0])
	var b := _world([0, 0])
	for world in [a, b]:
		_keep_everyone_alive(world)
		_on_hill(world, 1, 2)
		_on_hill(world, 2, 1, Vector2i(21, 24))
		for i in range(8):
			world.step()
	assert_eq(a.player_for(1).score, b.player_for(1).score)
	assert_eq(a.state_hash(), b.state_hash())
