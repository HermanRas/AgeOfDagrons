## The procedural map generator (PLAN.md 2.4b), ported from `game_map_gen/` with the
## eight fixes 11.2 records. Most of these tests exist because the prototype got the
## thing they check wrong.
extends TestCase


func _generate(p_seed: int = 1, type: int = MapGenerator.Type.FOREST,
		players: int = 2) -> MapData:
	return MapGenerator.generate(p_seed, type, players)


func _entities_of(data: MapData, def_id: StringName) -> Array:
	var out: Array = []
	for e in data.entities:
		if StringName(e["def_id"]) == def_id:
			out.append(e)
	return out


# ── size is by area, not by side (fix 1) ────────────────────────────────────

func test_map_size_grows_with_area_not_with_side() -> void:
	# THE MOST CONSEQUENTIAL NUMBER HERE. The prototype grew the SIDE linearly, so 8
	# players got 8x the side and 64x the area of 2 -- and fog of war is one byte per
	# tile per player, so a 300x300 map puts ~90 KB of vision in every snapshot.
	var two := MapGenerator.side_for(2)
	var eight := MapGenerator.side_for(8)
	assert_eq(two, 96, "2 players: 64 * sqrt(2) rounded up to a multiple of 16")
	assert_eq(eight, 192, "8 players")

	# Area per player is what should stay roughly constant, not side per player.
	var area_two := float(two * two) / 2.0
	var area_eight := float(eight * eight) / 8.0
	assert_true(absf(area_eight / area_two - 1.0) < 0.35,
			"area per player: %d vs %d tiles" % [int(area_two), int(area_eight)])
	assert_true(eight < two * 4, "linear-in-side growth would have made this 384")


func test_player_count_is_clamped_to_what_the_generator_supports() -> void:
	assert_eq(MapGenerator.side_for(1), MapGenerator.side_for(2), "1 is clamped up to 2")
	assert_eq(MapGenerator.side_for(99), MapGenerator.side_for(8), "and 99 down to 8")


# ── every start is playable (fix 3, fix 4) ──────────────────────────────────

func test_every_player_gets_a_town_centre_villagers_and_a_scout() -> void:
	var data := _generate()
	assert_eq(data.starts.size(), 2)
	assert_eq(_entities_of(data, &"building.town_center").size(), 2)
	assert_eq(_entities_of(data, &"unit.villager").size(), 2 * MapGen.STARTING_VILLAGERS)
	assert_eq(_entities_of(data, &"unit.scout_cavalry").size(), 2,
			"unit.scout_cavalry -- there is no `unit.scout` in units.json")


func test_the_town_centre_claims_its_real_footprint_from_the_data() -> void:
	# The prototype reserved 5x5 for a building that is 10x10 in buildings.json.
	var footprint: Vector2i = (GameDataRegistry.building(&"building.town_center") as BuildingDef).footprint
	assert_eq(footprint, Vector2i(10, 10), "the fixture only means anything at the real size")

	var data := _generate()
	for tc in _entities_of(data, &"building.town_center"):
		var tiles := MapData.footprint_rect_of(tc)
		assert_eq(tiles.size(), footprint.x * footprint.y)


func test_no_starting_unit_stands_inside_its_own_town_centre() -> void:
	# The prototype ringed units at radius 4, which is INSIDE a 10x10 footprint whose
	# walls reach radius 5 -- so every villager spawned inside its own town centre.
	var data := _generate()
	var walls: Dictionary = {}
	for tc in _entities_of(data, &"building.town_center"):
		for t in MapData.footprint_rect_of(tc):
			walls[t] = true

	var units := 0
	for e in data.entities:
		if GameDataRegistry.unit(e["def_id"]) == null:
			continue
		units += 1
		assert_false(walls.has(e["tile"] as Vector2i),
				"%s at %s is inside a town centre" % [e["def_id"], e["tile"]])
	assert_true(units > 0, "there were units to check")


func test_no_two_entities_claim_the_same_tile() -> void:
	# The prototype's veins had no guard and could be drawn straight over a base.
	for type in [MapGenerator.Type.ISLAND, MapGenerator.Type.RIVER,
			MapGenerator.Type.DESERT, MapGenerator.Type.FOREST]:
		var data := _generate(7, type)
		var seen: Dictionary = {}
		for e in data.entities:
			for t in MapData.footprint_rect_of(e):
				assert_false(seen.has(t), "%s overlaps %s at %s on a %s map"
						% [e["def_id"], seen.get(t, "?"), t, MapGenerator.type_name(type)])
				seen[t] = e["def_id"]


func test_every_start_is_far_enough_inside_the_map_for_its_clearing() -> void:
	for players in [2, 4, 8]:
		var data := _generate(3, MapGenerator.Type.ISLAND, players)
		for s in data.starts:
			var margin := 5 + MapGenerator.START_CLEARANCE
			assert_true(s.x >= margin and s.y >= margin
					and s.x < data.size.x - margin and s.y < data.size.y - margin,
					"start %s is within %d of the edge of a %d map" % [s, margin, data.size.x])


# ── determinism (7.1) ───────────────────────────────────────────────────────

func test_the_same_seed_produces_the_same_map() -> void:
	for type in [MapGenerator.Type.ISLAND, MapGenerator.Type.RIVER,
			MapGenerator.Type.DESERT, MapGenerator.Type.FOREST]:
		var a := _generate(12345, type)
		var b := _generate(12345, type)
		assert_eq(a.terrain, b.terrain, "%s terrain" % MapGenerator.type_name(type))
		assert_eq(a.starts, b.starts, "%s starts" % MapGenerator.type_name(type))
		assert_eq(a.entities.size(), b.entities.size(), "%s entity count" % MapGenerator.type_name(type))
		for i in range(a.entities.size()):
			assert_eq(a.entities[i], b.entities[i], "%s entity %d" % [MapGenerator.type_name(type), i])


func test_a_different_seed_produces_a_different_map() -> void:
	# Both halves matter: a generator that ignored its seed would pass the test above.
	var a := _generate(1)
	var b := _generate(2)
	assert_ne(a.terrain, b.terrain)


func test_random_resolves_to_a_real_type_and_is_still_deterministic() -> void:
	var a := _generate(99, MapGenerator.Type.RANDOM)
	var b := _generate(99, MapGenerator.Type.RANDOM)
	assert_eq(a.terrain, b.terrain)
	assert_ne(int(a.meta["type"]), int(MapGenerator.Type.RANDOM),
			"RANDOM is resolved at generation, not carried through")


# ── the four types are actually different ───────────────────────────────────

func _terrain_share(data: MapData, kind: int) -> float:
	var n := 0
	for i in range(data.terrain.size()):
		if data.terrain[i] == kind:
			n += 1
	return float(n) / float(data.terrain.size())


func test_an_island_is_surrounded_by_water() -> void:
	var data := _generate(4, MapGenerator.Type.ISLAND)
	var edge_water := 0
	var edge := 0
	for x in range(data.size.x):
		for y in [0, data.size.y - 1]:
			edge += 1
			if not data.is_ground_passable(Vector2i(x, y)):
				edge_water += 1
	assert_true(float(edge_water) / float(edge) > 0.9,
			"%d of %d top/bottom edge tiles are water" % [edge_water, edge])
	assert_true(_terrain_share(data, SimMap.Terrain.GRASS) > 0.15, "and there is an island on it")


func test_a_desert_is_mostly_sand_and_a_forest_is_mostly_wood() -> void:
	var desert := _generate(5, MapGenerator.Type.DESERT)
	assert_true(_terrain_share(desert, SimMap.Terrain.SAND) > 0.7,
			"sand share %f" % _terrain_share(desert, SimMap.Terrain.SAND))

	var forest := _generate(5, MapGenerator.Type.FOREST)
	var trees := _entities_of(forest, &"res.tree").size()
	var desert_trees := _entities_of(desert, &"res.tree").size()
	assert_true(trees > desert_trees * 3,
			"a forest map has %d trees, a desert %d" % [trees, desert_trees])


func test_a_river_map_splits_its_players_across_the_water() -> void:
	# The prototype's river was three disjoint segments with 20-tile gaps, so it read
	# as three lakes and "opposite sides" meant nothing. It is now continuous with
	# NARROW land bridges (which the owner likes and which stay), and the players are
	# on opposite banks -- so a straight line between two starts must cross water.
	var data := _generate(11, MapGenerator.Type.RIVER)
	assert_eq(data.starts.size(), 2)
	var a := Vector2(data.starts[0])
	var b := Vector2(data.starts[1])
	var crossings := 0
	var steps := int(a.distance_to(b))
	for i in range(steps + 1):
		var t := Vector2i(a.lerp(b, float(i) / float(maxi(1, steps))))
		if not data.is_ground_passable(t):
			crossings += 1
	assert_true(crossings > 0,
			"the straight line between the two starts never crosses the river")


func test_a_river_still_has_land_bridges() -> void:
	# The bridges are the liked part. A river with none would pass the connectivity
	# gate only by accident of the map edge, so assert them directly: somewhere along
	# the water there is dry ground crossing it.
	var data := _generate(11, MapGenerator.Type.RIVER)
	var problems := MapValidator.problems(data)
	assert_true(problems.is_empty(), "a river map is crossable: %s" % [problems])


# ── the gate (fix 5) ────────────────────────────────────────────────────────

func test_every_generated_map_passes_validation() -> void:
	# The gate is built into generate(), so this is really "the retry loop works".
	for type in [MapGenerator.Type.ISLAND, MapGenerator.Type.RIVER,
			MapGenerator.Type.DESERT, MapGenerator.Type.FOREST]:
		for p_seed in [1, 2, 3]:
			var data := MapGenerator.generate(p_seed, type, 2)
			assert_true((data.meta["problems"] as Array).is_empty(),
					"%s seed %d: %s" % [MapGenerator.type_name(type), p_seed,
					data.meta["problems"]])


func test_generation_records_which_attempt_succeeded() -> void:
	# So a map that needed three tries is still reproducible from the seed the player
	# was shown.
	var data := _generate(8)
	assert_true(data.meta.has("attempt"))
	assert_eq(int(data.meta["seed"]), 8, "the seed recorded is the one asked for")


func test_four_and_eight_player_maps_are_playable_too() -> void:
	for players in [4, 8]:
		var data := MapGenerator.generate(21, MapGenerator.Type.FOREST, players)
		assert_eq(data.starts.size(), players)
		assert_true((data.meta["problems"] as Array).is_empty(),
				"%d players: %s" % [players, data.meta["problems"]])


# ── cost, which the map size decides ────────────────────────────────────────

func test_a_generated_map_does_not_blow_the_entity_or_wire_budget() -> void:
	# Every tree is a SimResourceNode in `entities`, so tree DENSITY is a wire-format
	# decision, not a cosmetic one -- which is why they stand on a lattice rather than
	# on every tile of a wood. Printed as well as asserted, because the number is the
	# thing to watch as the generator is tuned.
	var data := _generate(1, MapGenerator.Type.FOREST, 2)
	var bytes := var_to_bytes(data.to_dict()).size()
	print("        forest 2P: %dx%d, %d entities (%d trees), map wire %d bytes"
			% [data.size.x, data.size.y, data.entities.size(),
			_entities_of(data, &"res.tree").size(), bytes])
	assert_true(data.entities.size() < 400,
			"%d entities is more than the snapshot can carry" % data.entities.size())
	assert_true(bytes < 49152, "a map is sent once, but %d bytes is too big" % bytes)


# ── applying it to a world ──────────────────────────────────────────────────

func _world_on(p_seed: int = 1, type: int = MapGenerator.Type.FOREST,
		players: int = 2) -> SimWorld:
	var cfg := MatchConfig.debug_generated(p_seed, type, players)
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	return w


func test_a_generated_map_becomes_a_world_with_a_start_for_every_player() -> void:
	var w := _world_on()
	var tcs: Dictionary = {}
	var villagers: Dictionary = {}
	for e in w.entities.values():
		if e is SimBuilding and e.def_id == &"building.town_center":
			tcs[e.owner_id] = int(tcs.get(e.owner_id, 0)) + 1
		elif e is SimUnit and e.def_id == &"unit.villager":
			villagers[e.owner_id] = int(villagers.get(e.owner_id, 0)) + 1

	for p in w.players:
		assert_eq(int(tcs.get(p.id, 0)), 1, "player %d has one town centre" % p.id)
		assert_eq(int(villagers.get(p.id, 0)), MapGen.STARTING_VILLAGERS,
				"player %d has %d villagers" % [p.id, MapGen.STARTING_VILLAGERS])
		assert_eq(int(p.stock.get(&"wood", 0)), int(MapGen.STARTING_STOCK[&"wood"]))


func test_the_map_size_comes_from_the_map_and_not_from_the_config_default() -> void:
	# A 96x96 map dropped into MatchConfig's 64x64 default would silently lose a
	# quarter of itself.
	var cfg := MatchConfig.debug_generated(1, MapGenerator.Type.FOREST, 2)
	var w := SimWorld.new()
	w.setup(cfg)
	assert_eq(w.map.size, Vector2i(96, 96))
	assert_eq(w.map.size, cfg.map_data.size)


func test_the_terrain_reaches_the_grid_with_its_move_costs() -> void:
	# Applied through `set_terrain()` rather than by writing the array, so a tile's
	# cost cannot disagree with its terrain (2.1).
	var w := _world_on(4, MapGenerator.Type.ISLAND)
	var water := 0
	for y in range(w.map.size.y):
		for x in range(w.map.size.x):
			var t := Vector2i(x, y)
			if w.map.terrain_at(t) == SimMap.Terrain.WATER_DEEP:
				water += 1
				assert_false(w.map.is_passable(t), "deep water at %s is not walkable" % t)
	assert_true(water > 0, "an island map put water in the grid")


func test_a_villager_on_a_generated_map_can_actually_gather() -> void:
	# THE ONE THAT MEANS "PLAYABLE". Everything above checks the map is well-formed;
	# this drives the real gather loop on it -- walk, chop, carry home, bank -- through
	# the ordinary command path.
	var w := _world_on(1, MapGenerator.Type.FOREST)
	var owner: int = w.players[0].id
	var villager: SimUnit = null
	for e in w.entities.values():
		if e is SimUnit and e.owner_id == owner and e.def_id == &"unit.villager":
			villager = e
			break
	assert_not_null(villager, "there is a villager to send")

	# The nearest tree, chosen by distance with a sorted-id tie-break so this test is
	# as deterministic as the sim it drives.
	var ids := w.entities.keys()
	ids.sort()
	var best := 0
	var best_d := 1 << 30
	for id in ids:
		var e = w.entities[id]
		if not (e is SimResourceNode) or e.def_id != &"res.tree":
			continue
		var d: int = (e.tile() - villager.tile()).length_squared()
		if d < best_d:
			best_d = d
			best = int(id)
	assert_true(best != 0, "there is a tree within reach")

	var before := int(w.players[0].stock.get(&"wood", 0))
	w.queue_command(GatherCommand.new(owner, [villager.id] as Array[int], best))
	for i in range(900):
		w.step()
	assert_true(int(w.players[0].stock.get(&"wood", 0)) > before,
			"wood went from %d to %d" % [before, int(w.players[0].stock.get(&"wood", 0))])


func test_standing_a_generated_map_up_costs_load_time_not_tick_time() -> void:
	# 11.2 predicted the pathfinding rebuild would scale from ~12 ms at 64x64. It is a
	# ONE-TIME setup cost that hides in load, unlike a per-tick cost -- but it is also
	# the number that would make an 8-player map unpleasant to start, so it is measured
	# rather than assumed. The TICK cost lives in `test_tick_cost.gd`, which measures it
	# per system; measuring the same thing in two places produced two different numbers
	# and no way to tell which to believe.
	for players in [2, 8]:
		var cfg := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, players)
		var w := SimWorld.new()
		var started := Time.get_ticks_usec()
		w.setup(cfg)
		MapGen.build(w, cfg)
		var build_ms := float(Time.get_ticks_usec() - started) / 1000.0

		print("        %dP %dx%d setup: %.1f ms, %d entities"
				% [players, w.map.size.x, w.map.size.y, build_ms, w.entities.size()])
		assert_true(build_ms < 3000.0, "%dP setup took %.0f ms" % [players, build_ms])


func test_two_worlds_from_the_same_generated_map_are_identical() -> void:
	# The determinism guarantee 2.4a made for the debug map, now for a generated one:
	# host and client must build byte-identical worlds from the same MatchConfig.
	var cfg := MatchConfig.debug_generated(77, MapGenerator.Type.RIVER, 2)
	var a := SimWorld.new()
	a.setup(cfg)
	MapGen.build(a, cfg)
	var b := SimWorld.new()
	b.setup(cfg)
	MapGen.build(b, cfg)
	assert_eq(a.state_hash(), b.state_hash())
	for i in range(20):
		a.step()
		b.step()
		assert_eq(a.state_hash(), b.state_hash(), "diverged on tick %d" % (i + 1))


func test_a_map_with_more_players_than_the_match_does_not_spawn_a_stranger() -> void:
	# A 4-player map started as a 2-player match: the extra bases are skipped rather
	# than spawned for a player who does not exist.
	var data := MapGenerator.generate(5, MapGenerator.Type.FOREST, 4)
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.colours = [0, 1]
	cfg.map_data = data
	cfg.map_size = data.size

	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	for e in w.entities.values():
		assert_true(e.owner_id == 0 or e.owner_id == 1 or e.owner_id == 2,
				"%s belongs to player %d, who is not in this match" % [e.def_id, e.owner_id])


# ── the wire format ─────────────────────────────────────────────────────────

func test_a_map_survives_a_round_trip_through_its_dictionary() -> void:
	# How a map reaches a joining client (12.1 step b) and how it is saved (2.4c).
	var data := _generate(6, MapGenerator.Type.RIVER)
	var back := MapData.from_dict(data.to_dict())
	assert_eq(back.size, data.size)
	assert_eq(back.terrain, data.terrain)
	assert_eq(back.starts, data.starts)
	assert_eq(back.entities.size(), data.entities.size())
	for i in range(data.entities.size()):
		assert_eq(back.entities[i], data.entities[i], "entity %d" % i)
	assert_true(MapValidator.problems(back).is_empty(), "and it is still playable")
