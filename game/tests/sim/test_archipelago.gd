## The Archipelago map type (2.4d, PLAN.md 11.6) and the connectivity claim it changes.
##
## THE INTERESTING PROPERTY IS A NEGATIVE ONE. Every other map type has to prove that
## every player can walk to every other; this one has to prove they CANNOT, because a
## map where you can walk to your enemy is not an archipelago -- and it validates
## perfectly, which is exactly why nothing else would catch it. `MapValidator`'s land
## claim therefore CHANGES rather than relaxes, into two claims of the same strength:
## every start can reach a shore, and the water is one body.
##
## The generator half is checked by generating real maps at every player count. The
## validator half is checked against maps BUILT BY HAND, because the two failures it
## exists to catch -- a player with no beach, and two seas that do not join -- are
## exactly the maps the generator is trying not to produce.
extends TestCase

const ARCH := MapGenerator.Type.ARCHIPELAGO


# ── the generator ───────────────────────────────────────────────────────────

func test_it_generates_a_playable_map_at_every_player_count() -> void:
	# Every count, not just two: the ring radius is what the board allows once an island
	# and a sea margin come off, and the island radius is capped by the gap between
	# neighbours. Those two pull opposite ways as the count rises, so the failure would
	# be at one end or the other and never in the middle.
	for players in [2, 3, 4, 8]:
		var data := MapGenerator.generate(players, ARCH, players)
		var problems: Array = data.meta.get("problems", [])
		assert_true(problems.is_empty(),
				"%d players: %s" % [players, "; ".join(PackedStringArray(problems))])
		assert_eq(data.starts.size(), players, "%d players get %d starts" % [players, players])


func test_no_player_can_walk_to_another() -> void:
	# The whole point of the type, and the one thing `MapValidator` cannot assert for
	# itself: it has been told not to require land connectivity here, so if the islands
	# merged it would report a perfectly good map.
	#
	# FROM THE STARTING UNITS, not from `data.starts`. A start's CENTRE is inside its own
	# town centre's footprint, which is blocked ground, so a flood from there returns the
	# empty set -- and this test would then pass for every map ever made, including a
	# single continent. `MapValidator`'s own header says so and it is worth restating
	# where the failure would be silent rather than loud.
	var data := MapGenerator.generate(7, ARCH, 4)
	var blocked := MapValidator._blocked_tiles(data)
	var sources := MapValidator._start_sources(data)
	var keys := sources.keys()
	keys.sort()
	var reachable := MapValidator._flood(data, blocked, sources[keys[0]])
	assert_true(reachable.size() > 100, "the fixture floods something: %d tiles" % reachable.size())
	for i in keys:
		if i == keys[0]:
			continue
		assert_false(reachable.has(sources[i]),
				"player %d is on their own island, not on player 1's" % (int(i) + 1))


func test_every_island_has_a_beach_to_build_a_dock_on() -> void:
	# Without this a player is sealed in for the whole match, which is the same
	# unplayable-and-invisible failure the land check exists to catch. It is not a
	# nicety on this type -- it is the replacement for the check that was removed.
	var data := MapGenerator.generate(11, ARCH, 4)
	var blocked := MapValidator._blocked_tiles(data)
	var sources := MapValidator._start_sources(data)
	assert_eq(sources.size(), 4, "four players to check")
	# From the units again, for the reason above: a flood out of a town centre's
	# footprint reaches nothing, and this would then fail for every map ever made.
	for i in sources:
		assert_true(MapValidator._reaches_shore(data, blocked, sources[i]),
				"player %d can walk to shallow water" % (int(i) + 1))


func test_the_sea_is_one_body_so_a_ship_can_cross() -> void:
	# The archipelago's version of "everybody can reach everybody", over the water
	# domain instead of the land one.
	var data := MapGenerator.generate(13, ARCH, 8)
	var sources := MapValidator._start_sources(data)
	var keys := sources.keys()
	keys.sort()
	assert_eq(MapValidator._sea_components(data, sources, keys).size(), 1,
			"eight islands, one ocean")


func test_nothing_on_an_archipelago_bites() -> void:
	# "One island per player, a few sheep, and nothing that bites" (11.6). This needed
	# no code at all -- `PREDATORS` is read with `.get(type, {})`, so an unlisted type
	# gets no predators for free -- which is exactly why it is worth a test: a rule
	# nobody wrote is a rule nobody will notice being broken.
	var data := MapGenerator.generate(3, ARCH, 4)
	for e in data.entities:
		var def := GameDataRegistry.unit(e.get("def_id", &""))
		if def == null:
			continue
		assert_eq(def.aggro_radius, 0,
				"%s is on an archipelago and hunts nobody" % e.get("def_id", &""))


func test_the_content_differs_from_a_land_map_in_the_three_ways_it_should() -> void:
	# Sheep down, deer gone, fish up -- and all three are consequences of the island
	# rather than tastes. Compared against a DESERT map of the same size and count, so
	# what is being measured is the per-type override and not the map's own luck.
	var sea := _counts(MapGenerator.generate(5, ARCH, 4))
	var land := _counts(MapGenerator.generate(5, MapGenerator.Type.DESERT, 4))

	assert_eq(int(sea.get(&"unit.deer", 0)), 0,
			"a herd of seven deer on a one-base island is most of an opening standing still")
	assert_true(int(land.get(&"unit.deer", 0)) > 0, "where a desert has them")
	assert_true(int(sea.get(&"unit.sheep", 0)) < int(land.get(&"unit.sheep", 0)),
			"fewer sheep: %d against %d" % [int(sea.get(&"unit.sheep", 0)),
			int(land.get(&"unit.sheep", 0))])
	assert_true(int(sea.get(&"res.fish", 0)) > int(land.get(&"res.fish", 0)),
			"more fish, because the sea is the point: %d against %d"
					% [int(sea.get(&"res.fish", 0)), int(land.get(&"res.fish", 0))])


func _counts(data: MapData) -> Dictionary:
	var out: Dictionary = {}
	for e in data.entities:
		var id: StringName = e.get("def_id", &"")
		out[id] = int(out.get(id, 0)) + 1
	return out


# ── the type list ───────────────────────────────────────────────────────────

func test_the_new_type_was_appended_so_saved_maps_keep_their_meaning() -> void:
	# `MatchConfig.map_type` is an int on the wire and a saved map records it (2.4c), so
	# inserting a type in the middle would silently turn every recorded Desert into a
	# Forest. Asserting the ORDER is what makes that rule enforceable rather than
	# remembered.
	assert_eq(int(MapGenerator.Type.ISLAND), 1)
	assert_eq(int(MapGenerator.Type.RIVER), 2)
	assert_eq(int(MapGenerator.Type.DESERT), 3)
	assert_eq(int(MapGenerator.Type.FOREST), 4)
	assert_eq(int(MapGenerator.Type.ARCHIPELAGO), 5, "appended, never inserted")


func test_random_can_actually_roll_the_new_type() -> void:
	# THE FAILURE THIS CATCHES IS SILENT. `generate` used to roll from a hand-written
	# `[ISLAND, RIVER, DESERT, FOREST]`, so a fifth type would have been offered in the
	# picker, generated when asked for by name, and NEVER produced by Random -- with
	# nothing anywhere reporting it. Now there is one list and three callers.
	var rolled: Dictionary = {}
	for s in range(40):
		var data := MapGenerator.generate(s, MapGenerator.Type.RANDOM, 2)
		rolled[int(data.meta.get("type", -1))] = true
	for type in MapGenerator.real_types():
		assert_true(rolled.has(int(type)),
				"Random rolled %s at least once in 40 seeds" % MapGenerator.type_name(type))


func test_every_real_type_names_itself_and_a_tree_pool() -> void:
	for type in MapGenerator.real_types():
		assert_ne(MapGenerator.type_name(type), "Random",
				"%d is a real type with a real name" % int(type))
		assert_false(String(MapGenerator.pool_name(type)).is_empty())
	assert_eq(MapGenerator.pool_names().size(), MapGenerator.real_types().size(),
			"one pool name per type, from one list")


# ── the validator, on maps built to fail ────────────────────────────────────

## A hand-built sea map: `size` square, all grass, one unit per start, and whatever
## water the caller paints afterwards. Deliberately missing resources -- `MIN_NEARBY`
## will complain about those too, and these tests assert the presence of the problem
## they are about rather than the absence of every other.
func _sea_map(size: int, starts: Array[Vector2i]) -> MapData:
	var data := MapData.create(Vector2i(size, size))
	data.meta["type"] = int(ARCH)
	for i in range(starts.size()):
		data.starts.append(starts[i])
		data.add_entity(&"unit.villager", i + 1, starts[i])
	return data


func _has_problem(problems: Array[String], fragment: String) -> bool:
	for p in problems:
		if p.contains(fragment):
			return true
	return false


func test_a_start_with_no_shore_is_refused() -> void:
	# A player who cannot build a dock is sealed in for the whole match. On a land map
	# this is nobody's business; on this one it is the whole business.
	var data := _sea_map(40, [Vector2i(6, 6), Vector2i(33, 33)] as Array[Vector2i])
	var problems := MapValidator.problems(data)
	assert_true(_has_problem(problems, "cannot build a dock"),
			"an all-grass archipelago is refused: %s" % "; ".join(PackedStringArray(problems)))


func test_two_seas_that_do_not_join_are_refused() -> void:
	# Each player has a beach and neither can sail to the other, which is a map that
	# passes every check the land types have and is still unplayable. This is the case
	# the water flood exists for.
	var data := _sea_map(40, [Vector2i(6, 6), Vector2i(33, 33)] as Array[Vector2i])
	for t in [Vector2i(6, 8), Vector2i(7, 8), Vector2i(33, 31), Vector2i(32, 31)]:
		data.set_terrain(t, SimMap.Terrain.WATER_SHALLOW)
	var problems := MapValidator.problems(data)
	assert_true(_has_problem(problems, "separate bodies"),
			"two puddles are not an ocean: %s" % "; ".join(PackedStringArray(problems)))


func test_one_sea_touching_both_starts_is_accepted() -> void:
	# The fixture that proves the two above fail for the reason claimed rather than
	# because a hand-built map is refused whatever is on it.
	var data := _sea_map(40, [Vector2i(6, 6), Vector2i(33, 33)] as Array[Vector2i])
	for i in range(40):
		data.set_terrain(Vector2i(i, 20), SimMap.Terrain.WATER_SHALLOW)
	var problems := MapValidator.problems(data)
	assert_false(_has_problem(problems, "separate bodies"), "one channel, one sea")
	assert_false(_has_problem(problems, "cannot build a dock"), "and both can reach it")


func test_a_land_map_still_has_to_be_walkable_end_to_end() -> void:
	# The other half of "changes rather than relaxes": the strict claim is untouched for
	# every type that is not this one, and a map with NO type declared takes the strict
	# one too -- so a hand-built map or a fixture is never let through on the weaker rule
	# by accident.
	var data := _sea_map(40, [Vector2i(6, 6), Vector2i(33, 33)] as Array[Vector2i])
	data.meta.erase("type")
	for i in range(40):
		data.set_terrain(Vector2i(i, 20), SimMap.Terrain.WATER_DEEP)
	var problems := MapValidator.problems(data)
	assert_true(_has_problem(problems, "cannot reach"),
			"an untyped map is still judged by land: %s" % "; ".join(PackedStringArray(problems)))
