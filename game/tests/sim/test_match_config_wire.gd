## Phase 12.1b: `MatchConfig` on the wire.
##
## Every client builds its own world from this one message (PLAN.md 2.4a), so anything
## the two sides could disagree about has to survive the trip -- and the typed arrays
## are the part that fails silently rather than loudly, because everything off the wire
## arrives as untyped Variants.
extends TestCase


func test_a_generated_config_round_trips_whole() -> void:
	var c := MatchConfig.debug_generated(7, MapGenerator.Type.FOREST, 4)
	var back := MatchConfig.from_dict(c.to_dict())

	assert_eq(back.player_ids, c.player_ids)
	assert_eq(back.colours, c.colours)
	assert_eq(back.map_size, c.map_size)
	assert_eq(back.mode, c.mode)
	assert_eq(back.seed, c.seed, "provenance travels for the lobby to display")
	assert_eq(back.map_type, c.map_type)


func test_the_map_travels_as_the_map_rather_than_as_a_seed() -> void:
	# The 2026-08-17 correction: FastNoiseLite's float maths is not guaranteed identical
	# between an ARM phone and an x86 desktop, so regenerating from the seed can put the
	# water somewhere else -- a desync before the first order.
	var c := MatchConfig.debug_generated(11, MapGenerator.Type.RIVER, 2)
	var back := MatchConfig.from_dict(c.to_dict())

	assert_not_null(back.map_data, "the map itself came across")
	assert_eq(back.map_data.size, c.map_data.size)
	assert_eq(back.map_data.terrain, c.map_data.terrain, "tile for tile, not regenerated")
	assert_eq(back.map_data.starts, c.map_data.starts)
	assert_eq(back.map_data.entities.size(), c.map_data.entities.size())


func test_two_worlds_built_from_the_two_sides_of_the_wire_are_identical() -> void:
	# The assertion that actually matters: a host and a client that each build from
	# their own copy must agree, which is what `state_hash()` is for.
	var host_cfg := MatchConfig.debug_generated(5, MapGenerator.Type.FOREST, 2)
	var client_cfg := MatchConfig.from_dict(host_cfg.to_dict())

	var a := SimWorld.new()
	a.setup(host_cfg)
	MapGen.build(a, host_cfg)

	var b := SimWorld.new()
	b.setup(client_cfg)
	MapGen.build(b, client_cfg)

	assert_eq(a.state_hash(), b.state_hash(),
			"host and client must not disagree about the world before the first tick")

	for i in range(40):
		a.step()
		b.step()
	assert_eq(a.state_hash(), b.state_hash(), "and must stay agreed as it ticks")


func test_ai_slots_survive_rather_than_becoming_an_array_of_nulls() -> void:
	# `ai_players` is Array[bool]; assigned straight off the wire it fills with nulls,
	# which reads as "nobody is a bot" and quietly turns the AI off in a hosted match.
	var c := MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	c.ai_players = [false, true] as Array[bool]

	var back := MatchConfig.from_dict(c.to_dict())
	assert_eq(back.ai_players.size(), 2)
	assert_false(back.ai_players[0])
	assert_true(back.ai_players[1], "the bot slot is still a bot on the other side")

	var w := SimWorld.new()
	w.setup(back)
	assert_false(w.players[0].is_ai)
	assert_true(w.players[1].is_ai, "and SimWorld reads it through to SimPlayer")


func test_a_config_with_no_generated_map_still_round_trips() -> void:
	# The fixed debug map is integer code and identical everywhere, so it carries no
	# MapData and must not acquire a broken one in transit.
	var c := MatchConfig.debug_single_player()
	var back := MatchConfig.from_dict(c.to_dict())

	assert_null(back.map_data)
	assert_eq(back.map_size, c.map_size)
	assert_eq(back.player_ids, c.player_ids)


func test_the_map_is_the_authority_on_its_own_size() -> void:
	# A config whose map_size disagreed with the map it carries would build a world the
	# wrong shape, and the mismatch would only show up as a desync.
	var c := MatchConfig.debug_generated(2, MapGenerator.Type.DESERT, 2)
	var d := c.to_dict()
	d["map_size"] = {"x": 8, "y": 8}

	var back := MatchConfig.from_dict(d)
	assert_eq(back.map_size, back.map_data.size, "the map wins, not the stale field")


func test_the_wire_form_survives_json_the_way_a_packet_would() -> void:
	# ENet hands Dictionaries around in-process, but a config that could not survive
	# JSON would break the moment anything logged or saved one (12.4's save/load).
	var c := MatchConfig.debug_generated(9, MapGenerator.Type.ISLAND, 2)
	var parsed = JSON.parse_string(JSON.stringify(c.to_dict()))

	assert_not_null(parsed, "the config is JSON-clean")
	var back := MatchConfig.from_dict(parsed)
	assert_eq(back.map_data.size, c.map_data.size)
	assert_eq(back.player_ids, c.player_ids)
	assert_eq(back.map_data.terrain, c.map_data.terrain)
