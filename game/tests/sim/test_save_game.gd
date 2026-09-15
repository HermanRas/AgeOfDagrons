## Phase 12.4: saving a MATCH and getting the same match back.
##
## ## ⛔ THE ACCEPTANCE TEST IS NOT "IT LOADS". IT IS "IT KEEPS AGREEING"
##
## PLAN.md 12.4 names the bar: *"`state_hash()` agreeing across all peers on the first tick
## after the reload"*, because **a save that loads and desyncs on tick 2 is worse than no
## save.** So every round trip below does the same two things, and the second is the one that
## earns its keep:
##
##   1. restore, and compare `state_hash()` -- proves the state that is HASHED came back;
##   2. **then step both worlds on, tick for tick, and compare again** -- proves the state that
##      is NOT hashed came back too.
##
## Step 2 is what catches the three fields the hash cannot speak for (`_next_id`, the map's
## arrays, and a unit's actual ROUTE as opposed to its progress along one), and it catches them
## the way a player would: the match quietly stops being the same match. A test that only did
## step 1 would pass with `_next_id` dropped entirely.
##
## ## WHY A REAL WORLD AND NOT A FIXTURE
##
## These build a generated map with two bots on it and step it, so what gets saved is a match
## in motion -- villagers part way along a route, a building part way up, cooldowns part way
## down, fog part way explored, and an AI part way through its opening. A hand-made fixture
## would only ever exercise the fields somebody remembered to put in it, which is precisely the
## failure mode a save format has.
extends TestCase

## Long enough for the bots to have built something and moved somebody, short enough to keep
## the suite quick. At 200 the opening is under way and villagers are carrying.
const WARMUP_TICKS := 200

## How far both worlds are run after the reload. A divergence in anything the sim reads shows
## up within a handful of ticks; this is comfortably past that.
const COMPARE_TICKS := 120


func _config() -> MatchConfig:
	# A real generated map, so there are trees, wildlife and two proper bases -- the debug map
	# has one base and would leave the second player with nothing to do. `debug_generated` is
	# the idiom every other sim test builds one with.
	var cfg := MatchConfig.debug_generated(4242, MapGenerator.Type.FOREST, 2)
	# ⚠️ BOTS ON BOTH SIDES, and not for the AI's sake: it is the only way to get a match that
	# CHANGES without a script of commands. Everything interesting in a save -- a half-built
	# barracks, a villager mid-route, a queue with something in it -- is something somebody
	# ordered.
	cfg.ai_players = [true, true] as Array[bool]
	cfg.ai_levels = [SimPlayer.AILevel.EASY, SimPlayer.AILevel.EASY] as Array[int]
	return cfg


## A world built exactly the way `SimHost.build()` builds one.
func _build(cfg: MatchConfig) -> SimWorld:
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	return w


func _stepped(cfg: MatchConfig, ticks: int) -> SimWorld:
	var w := _build(cfg)
	for i in ticks:
		w.step()
	return w


## Save `world`, put it through JSON exactly as a file would, and restore it into a world
## rebuilt from the same config.
##
## ⚠️ **THROUGH `JSON.stringify`/`parse_string` AND NOT THE DICTIONARY**, always. The traps
## this format has to survive are the JSON boundary's -- a `PackedByteArray` becoming the text
## `"[1, 2, 250]"`, and every integer coming back a float -- so a round trip that handed the
## dictionary straight back would test nothing that can actually go wrong.
func _round_trip(world: SimWorld, cfg: MatchConfig) -> Dictionary:
	var text := JSON.stringify(SaveGame.capture(world, cfg))
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "a save must survive JSON as an object")
	var loaded := _build(cfg)
	var problems := SaveGame.apply(loaded, parsed)
	return {"world": loaded, "problems": problems, "text": text}


# ── the round trip ──────────────────────────────────────────────────────────

func test_a_saved_match_comes_back_with_the_same_state_hash() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var out := _round_trip(world, cfg)

	assert_eq(out["problems"], [] as Array[String], "the file must be understood completely")
	var loaded: SimWorld = out["world"]
	assert_eq(loaded.tick, world.tick, "the same tick")
	assert_eq(loaded.state_hash(), world.state_hash(),
			"a restored world must be indistinguishable from the one it was saved from")


## ⛔ THE ONE THAT MATTERS. Two worlds that agree on one tick and then diverge are the failure
## PLAN.md calls worse than no save at all, and nothing above can see it.
func test_a_restored_match_goes_on_agreeing_tick_for_tick() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	for i in COMPARE_TICKS:
		world.step()
		loaded.step()
		# Compared EVERY tick rather than at the end: the tick a divergence appears on is the
		# only clue to what caused it, and a single comparison after 120 ticks reports one at
		# tick 120 no matter when the two actually parted.
		assert_eq(loaded.state_hash(), world.state_hash(),
				"the two worlds parted %d tick(s) after the reload" % (i + 1))


## The id counter is not in `state_hash()`, so the test above is the only thing that can catch
## it -- and only once something is SPAWNED. This says so directly, because a silent id
## collision is the worst failure this format has: two entities with one id, and a `removed[]`
## on the wire that deletes the wrong one.
func test_the_entity_id_counter_survives_and_is_never_behind_the_world() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	assert_eq(loaded._next_id, world._next_id, "the counter comes back exactly")
	var highest := 0
	for id in loaded.entities:
		highest = maxi(highest, int(id))
	assert_true(loaded._next_id > highest,
			"the next id (%d) must be past every entity alive (%d)" % [loaded._next_id, highest])


## A file that lost the counter is REPAIRED rather than trusted, and says so. The repair
## cannot restore what the counter was; it can guarantee the next id is not one in use, which
## is the property that stops a collision.
func test_a_save_with_no_id_counter_is_repaired_and_complains() -> void:
	var cfg := _config()
	var world := _stepped(cfg, 20)
	var saved := SaveGame.capture(world, cfg)
	(saved["world"] as Dictionary).erase("next_id")

	var loaded := _build(cfg)
	var problems := SaveGame.apply(loaded, saved)
	assert_false(problems.is_empty(), "a missing id counter must never pass silently")
	var highest := 0
	for id in loaded.entities:
		highest = maxi(highest, int(id))
	assert_true(loaded._next_id > highest, "and the counter must still be safe to spawn from")


# ── the pieces the hash cannot speak for ────────────────────────────────────

## `state_hash()` folds in `map.state_hash()`, which is a number -- and a number cannot be
## restored from. Terrain is cut down, walls claim tiles and rubble releases them, so the live
## grid is not the generated one.
func test_the_live_map_comes_back_and_not_the_generated_one() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	# Something the generator would never have produced, so a restore that quietly kept the
	# freshly generated grid is visible rather than plausible.
	world.map.set_terrain(Vector2i(3, 3), SimMap.Terrain.WATER_DEEP)
	world.map.set_terrain(Vector2i(4, 3), SimMap.Terrain.WATER_DEEP)

	var loaded: SimWorld = _round_trip(world, cfg)["world"]
	assert_eq(loaded.map.terrain, world.map.terrain, "every tile of terrain")
	assert_eq(loaded.map.occupancy, world.map.occupancy, "and who is standing on it")
	assert_eq(loaded.map.blocking, world.map.blocking)
	assert_eq(loaded.map.move_cost, world.map.move_cost)
	assert_eq(loaded.map.state_hash(), world.map.state_hash())


## `state_hash()` hashes `path.size()` and `path_index` -- enough to CATCH a divergence,
## nowhere near enough to resume one. Two units holding different routes of equal length hash
## identically and then walk two different ways.
func test_a_units_whole_route_is_saved_and_not_just_its_progress() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	var checked := 0
	for id in world.entities:
		var a = world.entities[id]
		if not (a is SimUnit) or (a as SimUnit).path.is_empty():
			continue
		var b = loaded.entities.get(id)
		assert_true(b is SimUnit, "entity %d must come back a unit" % id)
		assert_eq((b as SimUnit).path, (a as SimUnit).path,
				"unit %d must come back on the same route, not merely the same distance along one"
						% id)
		checked += 1
	assert_true(checked > 0, "the fixture must contain at least one unit actually walking")


## Cumulative fog (`UNSEEN`/`EXPLORED`/`VISIBLE`) is memory, not a per-tick derivation, so a
## save that dropped it would hand a player back a map they had already scouted.
func test_explored_fog_comes_back() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	for p in world.players:
		var q := loaded.player_for(p.id)
		assert_eq(q.vision, p.vision, "player %d's fog" % p.id)
	# And the fixture has to have explored something, or the assertion above is vacuous.
	var explored := 0
	for v in world.players[0].vision:
		if int(v) != SimPlayer.Fog.UNSEEN:
			explored += 1
	assert_true(explored > 0, "the fixture must have explored some of the map")


## The bots' rule state. Without it a reloaded bot starts its build order again from the top,
## in a town it already built -- which is not the match anybody saved, and is the owner's own
## sentence (*"pick it back up ... or vs AI later"*) not being met.
func test_each_bots_rule_state_comes_back() -> void:
	var cfg := _config()
	var world := _stepped(cfg, WARMUP_TICKS)
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	var before := SaveGame._ai_system(world)
	var after := SaveGame._ai_system(loaded)
	assert_true(before != null and after != null, "both worlds run an AI system")
	for p in world.players:
		assert_eq(after.decisions_of(p.id), before.decisions_of(p.id),
				"player %d's decision count" % p.id)
		assert_eq(after.last_rule_of(p.id), before.last_rule_of(p.id),
				"player %d's last rule" % p.id)
	# ⚠️ AND THE KEYS MUST BE INTS. JSON has string keys only, so a table keyed by player id
	# comes back keyed by "2" and every lookup misses -- silently, leaving each bot with a
	# fresh mind in an old town. `decisions_of` above would report 0 and so would a bot.
	var fired := 0
	for p in world.players:
		fired += before.decisions_of(p.id)
	assert_true(fired > 0, "the fixture's bots must have actually decided something")


# ── the JSON boundary ───────────────────────────────────────────────────────

## `MapData._terrain_from`'s trap, one format further on: `JSON.stringify` renders a
## `PackedByteArray` as the TEXT `"[1, 2, 250]"`, and assigning that back to a typed property
## is a runtime error that abandons the rest of the parse. This format sends base64 instead, so
## what is pinned here is that the encoding survives a real `stringify`/`parse_string`.
func test_packed_arrays_survive_a_real_json_round_trip() -> void:
	var cfg := _config()
	var world := _stepped(cfg, 30)
	var out := _round_trip(world, cfg)
	var loaded: SimWorld = out["world"]

	assert_eq(out["problems"], [] as Array[String])
	assert_eq(loaded.map.terrain.size(), world.map.terrain.size(), "terrain is not a String")
	assert_eq(loaded.map.terrain, world.map.terrain)
	assert_eq(loaded.map.occupancy, world.map.occupancy, "32-bit occupancy too")


## JSON numbers come back as floats, so anything read without `int()` becomes a float in an
## int field. The round trip above would catch most of it; this says the rule out loud on the
## one field where a float would be silently survivable for a long time.
func test_stock_comes_back_as_integers_under_stringname_keys() -> void:
	var cfg := _config()
	var world := _stepped(cfg, 30)
	world.players[0].stock[&"wood"] = 1234
	var loaded: SimWorld = _round_trip(world, cfg)["world"]

	var p := loaded.player_for(world.players[0].id)
	# `&"wood" == "wood"` is FALSE, so a lookup against a String key finds nothing at all.
	assert_true(p.stock.has(&"wood"), "the key must be a StringName on the way back")
	assert_eq(typeof(p.stock[&"wood"]), TYPE_INT, "and the amount an int, not a float")
	assert_eq(int(p.stock[&"wood"]), 1234)


# ── refusals ────────────────────────────────────────────────────────────────

## A save file is a file a player can edit, so nothing here throws -- `PackDef.from_dict`'s
## precedent. What it does is refuse, and say which.
func test_a_file_from_a_newer_build_is_refused_rather_than_half_read() -> void:
	var cfg := _config()
	var world := _stepped(cfg, 10)
	var saved := SaveGame.capture(world, cfg)
	saved["format_version"] = SaveGame.FORMAT_VERSION + 1

	var loaded := _build(cfg)
	var before := loaded.state_hash()
	var problems := SaveGame.apply(loaded, saved)
	assert_false(problems.is_empty(), "a newer format must be refused")
	assert_eq(loaded.state_hash(), before,
			"and refused BEFORE anything was written, so the world is untouched")


func test_a_file_that_does_not_say_its_format_is_refused() -> void:
	var loaded := _build(_config())
	assert_false(SaveGame.apply(loaded, {}).is_empty())


## ⚠️ A SAVE DROPPED ONTO A DIFFERENT MATCH. The world is rebuilt from the CONFIG, so a file
## whose map is another size describes a different match entirely -- and resizing the grid to
## fit it would leave the config's start positions, areas and koth zone pointing somewhere
## else. Refused, with both sizes named.
func test_a_save_whose_map_is_a_different_size_is_refused() -> void:
	var cfg := _config()
	var world := _stepped(cfg, 10)
	var saved := SaveGame.capture(world, cfg)
	(saved["map"] as Dictionary)["w"] = 999

	var loaded := _build(cfg)
	var problems := SaveGame.apply(loaded, saved)
	assert_false(problems.is_empty(), "a map of the wrong size must be refused")
	assert_true(str(problems[0]).contains("999"), "and the complaint must name what it saw")
