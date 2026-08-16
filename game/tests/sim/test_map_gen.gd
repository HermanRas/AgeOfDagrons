## Phases 2.3, 2.4a and 2.6: placement into the grid, the fixed debug map, and
## the starting conditions.
##
## The load-bearing assertion is determinism -- two worlds built from the same
## MatchConfig must be byte-identical by `state_hash()`, because a client and the
## host each build their own and a difference on tick 0 is a desync before a single
## command is issued (PLAN.md 7.1).
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	MapGen.build_debug_map(w)


func _of_type(t) -> Array:
	var out: Array = []
	for e in w.entities.values():
		if is_instance_of(e, t):
			out.append(e)
	return out


# ── determinism ────────────────────────────────────────────────────────────

func test_two_worlds_from_the_same_config_are_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	MapGen.build_debug_map(other)
	assert_eq(w.state_hash(), other.state_hash(),
			"host and client must build byte-identical starting worlds")


func test_building_the_same_map_twice_assigns_the_same_entity_ids() -> void:
	# Ids are what commands reference, so if two clients numbered entities
	# differently every order would target a different unit.
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	MapGen.build_debug_map(other)
	var mine := w.entities.keys()
	var theirs := other.entities.keys()
	mine.sort()
	theirs.sort()
	assert_eq(mine, theirs)
	for id in mine:
		assert_eq((w.entities[id] as SimEntity).def_id,
				(other.entities[id] as SimEntity).def_id, "entity %d is the same kind" % id)


# ── starting conditions (2.6) ──────────────────────────────────────────────

func test_the_player_starts_with_one_town_centre_and_five_villagers() -> void:
	var buildings := _of_type(SimBuilding)
	var units := _of_type(SimUnit)
	assert_eq(buildings.size(), 1, "exactly one town centre")
	assert_eq((buildings[0] as SimBuilding).def_id, &"building.town_center")
	assert_eq(units.size(), MapGen.STARTING_VILLAGERS, "5 villagers (PLAN.md 2.6)")
	for u in units:
		assert_eq((u as SimUnit).def_id, &"unit.villager")


func test_the_starting_town_centre_is_complete_and_at_full_health() -> void:
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	assert_eq(tc.phase, SimBuilding.Phase.COMPLETE, "you do not start on a foundation")
	assert_eq(tc.hp, tc.max_hp)
	assert_true(tc.max_hp > 1, "stats came from buildings.json, not the fallback")
	assert_almost_eq(tc.build_fraction(), 1.0)


func test_starting_units_take_their_stats_from_units_json() -> void:
	# This is what replaced SimWorld's hardcoded _UNIT_DEFS table at 0.4.
	var u: SimUnit = _of_type(SimUnit)[0]
	var d: UnitDef = w.unit_def(&"unit.villager")
	assert_not_null(d, "the registry resolves the villager")
	assert_eq(u.max_hp, d.hp)
	assert_eq(u.speed, d.speed)
	assert_eq(u.vision_range, d.los)
	assert_eq(u.domain, SimMap.Domain.LAND)


func test_villagers_stand_on_distinct_passable_tiles_outside_the_town_centre() -> void:
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	var rect := tc.footprint_rect()
	var seen: Array[Vector2i] = []
	for u in _of_type(SimUnit):
		var t: Vector2i = (u as SimUnit).tile()
		assert_false(seen.has(t), "no two villagers share tile %s" % t)
		seen.append(t)
		assert_false(rect.has_point(t), "%s is not inside the town centre" % t)
		assert_true(w.map.is_terrain_passable(t), "%s is walkable ground" % t)


# ── the debug skirmish: a second player (MatchConfig.debug_skirmish) ───────

func _skirmish() -> SimWorld:
	var s := SimWorld.new()
	s.setup(MatchConfig.debug_skirmish())
	MapGen.build_debug_map(s)
	return s


func test_the_skirmish_is_yellow_against_red() -> void:
	# Not the join-order blue/red: those are the only two colour bakes known to be
	# current, and a debug match that renders 60 stale atlases teaches nothing
	# (GameDataRegistry.stale_colour_atlases()).
	var s := _skirmish()
	assert_eq(s.players.size(), 2)
	assert_eq(s.players[0].colour, GameDataRegistry.colour_index(&"colour.yellow"))
	assert_eq(s.players[1].colour, GameDataRegistry.colour_index(&"colour.red"))


func test_a_config_that_names_no_colour_still_falls_back_to_join_order() -> void:
	# The pre-lobby default, and what every client agrees on without being told.
	var cfg := MatchConfig.new()
	cfg.player_ids = [7, 9]
	var s := SimWorld.new()
	s.setup(cfg)
	assert_eq(s.players[0].colour, 0)
	assert_eq(s.players[1].colour, 1, "the SECOND player, not player id 9")


func test_the_enemy_gets_the_squad_and_nothing_else() -> void:
	# No base for player 2 on purpose -- this map has one start position, and a
	# forced second town centre would land on top of the first.
	var s := _skirmish()
	var theirs: Array = []
	for e in s.entities.values():
		if e.owner_id == 2:
			theirs.append(e)
	assert_eq(theirs.size(), MapGen.DEBUG_ENEMY_SQUAD.size(), "two soldiers")
	# Compared as Strings: sorting StringNames orders them by IDENTITY, which is
	# not their text and is not even stable between runs.
	var def_ids: Array[String] = []
	for e in theirs:
		assert_true(e is SimUnit, "the enemy owns no buildings")
		def_ids.append(String((e as SimUnit).def_id))
	def_ids.sort()
	assert_eq(def_ids, ["unit.archer", "unit.knight"] as Array[String])


func test_the_enemy_squad_takes_its_stats_from_units_json() -> void:
	# A def_id typo would spawn the SimWorld fallback -- 1 hp, no vision -- and
	# still render, since atlas_for() never returns null.
	var s := _skirmish()
	for e in s.entities.values():
		if e.owner_id != 2:
			continue
		var u: SimUnit = e
		var d: UnitDef = s.unit_def(u.def_id)
		assert_not_null(d, "%s resolves" % u.def_id)
		assert_eq(u.max_hp, d.hp)
		assert_true(d.attack_damage > 0, "%s is a soldier" % u.def_id)


func test_the_enemy_squad_stands_to_the_right_of_the_town_centre() -> void:
	# The whole point of where they are: the camera opens on the town centre, and
	# these have to be in shot. Iso sends (dx - dy) to screen x and (dx + dy) to
	# screen y, so "to the right, on roughly the same band" is that first
	# difference being positive and the second one small. Asserted in tile terms
	# rather than through Iso, which the sim layer may not name (PLAN.md 4).
	var s := _skirmish()
	var tc: SimBuilding = null
	for e in s.entities.values():
		if e is SimBuilding:
			tc = e
	assert_not_null(tc)
	for e in s.entities.values():
		if e.owner_id != 2:
			continue
		var rel: Vector2i = (e as SimUnit).tile() - tc.tile()
		assert_true(rel.x - rel.y >= 12,
				"%s is to the right of the town centre, clear of its 10x10 footprint" % e.def_id)
		assert_true(absi(rel.x + rel.y) <= 4,
				"%s is on the town centre's own horizontal band" % e.def_id)
		assert_true(s.map.is_terrain_passable((e as SimUnit).tile()),
				"%s stands on walkable ground" % e.def_id)


func test_the_skirmish_leaves_the_first_players_start_exactly_as_it_was() -> void:
	# Adding an opponent must not quietly change our own opening -- one town
	# centre, five villagers, the same resource clusters.
	var s := _skirmish()
	var mine: Array = []
	for e in s.entities.values():
		if e.owner_id == 1:
			mine.append(e)
	var units := 0
	var buildings := 0
	for e in mine:
		if e is SimUnit:
			units += 1
		elif e is SimBuilding:
			buildings += 1
	assert_eq(buildings, 1)
	assert_eq(units, MapGen.STARTING_VILLAGERS)
	for kind in MapGen.DEBUG_STARTING_STOCK:
		assert_eq(int(s.players[0].stock.get(kind, 0)), int(w.players[0].stock.get(kind, 0)),
				"the same starting %s" % kind)
	assert_true(s.players[1].stock.is_empty(), "and the enemy is given nothing to spend")


func test_two_skirmish_worlds_are_identical() -> void:
	# Same requirement as the single-player map: the host and the client each
	# build their own, and a difference on tick 0 is a desync before a command.
	assert_eq(_skirmish().state_hash(), _skirmish().state_hash())


# ── placement into the grid (2.3) ──────────────────────────────────────────

func test_the_town_centre_claims_its_whole_measured_footprint() -> void:
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	assert_eq(tc.footprint, Vector2i(10, 10), "the [10, 10] from buildings.json")
	var rect := tc.footprint_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			assert_eq(w.map.occupant(Vector2i(x, y)), tc.id,
					"%s belongs to the town centre" % Vector2i(x, y))
	assert_ne(w.map.occupant(rect.position + Vector2i(-1, -1)), tc.id,
			"and nothing outside it does")


func test_a_buildings_origin_tile_round_trips_through_its_centre_position() -> void:
	# pos is the footprint centre so the view can draw every entity the same way;
	# origin_tile() has to recover the grid's view of it exactly.
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	var origin := tc.origin_tile()
	assert_eq(SimBuilding.centre_of(origin, tc.footprint), tc.pos)
	assert_eq(tc.footprint_rect(), Rect2i(origin, tc.footprint))


func test_resource_nodes_are_placed_and_occupy_their_tiles() -> void:
	var nodes := _of_type(SimResourceNode)
	assert_true(nodes.size() >= 15, "wood, gold and deer were all placed")
	var kinds: Array[StringName] = []
	for n in nodes:
		var node: SimResourceNode = n
		if not kinds.has(node.kind):
			kinds.append(node.kind)
		assert_eq(w.map.occupant(node.tile()), node.id, "node claims its tile")
		assert_true(node.amount > 0, "and starts with something in it")
	for kind in [&"wood", &"gold", &"food"] as Array[StringName]:
		assert_true(kinds.has(kind), "the map has a %s source" % kind)


func test_nodes_take_their_amounts_from_resources_json() -> void:
	for n in _of_type(SimResourceNode):
		var node: SimResourceNode = n
		var d: ResourceDef = w.resource_def(node.def_id)
		assert_not_null(d, "%s resolves" % node.def_id)
		assert_eq(node.amount, d.amount_for(node.size_class))
		assert_eq(node.starting_amount, node.amount)
		assert_eq(node.gather_slots, d.gather_slots)


func test_the_debug_map_places_no_wildlife_now_that_food_is_berry_bushes() -> void:
	# res.berry_bush replaced res.deer as the debug map's food node (session
	# decision, MapGen.DEBUG_FOOD's own header) -- it is gathered like a tree,
	# not hunted, so nothing the debug map places should carry the wildlife
	# flag. res.deer's own wildlife flag is still exercised directly at the
	# data level (test_game_data.gd), just not spawned here any more.
	for n in _of_type(SimResourceNode):
		assert_false((n as SimResourceNode).is_wildlife,
				"%s should not be wildlife on the debug map" % (n as SimResourceNode).def_id)


func test_nothing_overlaps_anything_else() -> void:
	# The whole point of routing placement through the grid.
	var claimed: Dictionary = {}
	for e in w.entities.values():
		if e is SimUnit:
			continue                      # units are not written into occupancy
		var rect: Rect2i = (e as SimBuilding).footprint_rect() if e is SimBuilding \
				else Rect2i((e as SimEntity).tile(), Vector2i.ONE)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var t := Vector2i(x, y)
				assert_false(claimed.has(t), "%s claimed twice" % t)
				claimed[t] = e.id


# ── the debug map itself (2.4a) ────────────────────────────────────────────

func test_the_map_is_the_configured_size_and_walkable_in_the_middle() -> void:
	var cfg := MatchConfig.debug_single_player()
	assert_eq(w.map.size, cfg.map_size)
	assert_true(w.map.is_terrain_passable(Vector2i(cfg.map_size.x / 2, cfg.map_size.y / 2)))


func test_the_map_edge_is_marked_so_it_is_visible_before_a_camera_clamp_exists() -> void:
	assert_eq(w.map.terrain_at(Vector2i(0, 0)), SimMap.Terrain.DIRT)
	assert_eq(w.map.terrain_at(Vector2i(w.map.size.x - 1, w.map.size.y - 1)),
			SimMap.Terrain.DIRT)
	assert_eq(w.map.terrain_at(Vector2i(w.map.size.x / 2, w.map.size.y / 2)),
			SimMap.Terrain.GRASS, "the interior is grass")


# ── grid bookkeeping ───────────────────────────────────────────────────────

func test_despawning_frees_the_tiles_a_building_held() -> void:
	# Occupancy is keyed by entity id, so if despawn() did not clear it first the
	# tiles would stay claimed forever by a building that no longer exists -- and
	# 5.5 would leave unbuildable holes in the map.
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	var rect := tc.footprint_rect()
	w.despawn(tc.id)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			assert_eq(w.map.occupant(Vector2i(x, y)), 0, "%s freed" % Vector2i(x, y))
	assert_true(w.map.can_place_building(rect), "and something else can be built there")


func test_a_building_cannot_be_placed_on_top_of_the_town_centre() -> void:
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	var blocked := w.spawn_building(&"building.house", 1, tc.origin_tile())
	assert_null(blocked, "spawn_building refuses an occupied footprint")


func test_a_building_can_be_placed_on_free_ground() -> void:
	var tc: SimBuilding = _of_type(SimBuilding)[0]
	var origin := tc.origin_tile() + Vector2i(0, 20)
	var house := w.spawn_building(&"building.house", 1, origin)
	assert_not_null(house)
	assert_eq(house.footprint, Vector2i(4, 4), "the [4, 4] from buildings.json")
	assert_eq(w.map.occupant(origin), house.id)


func test_a_second_node_cannot_take_an_occupied_tile() -> void:
	var origin := (_of_type(SimBuilding)[0] as SimBuilding).origin_tile()
	var first := w.spawn_resource_node(&"res.tree", origin + Vector2i(0, 20))
	assert_not_null(first)
	assert_null(w.spawn_resource_node(&"res.tree", origin + Vector2i(0, 20)),
			"two trees cannot share a tile")


# ── entity behaviour introduced here ───────────────────────────────────────

func test_gathering_takes_only_what_is_left() -> void:
	# Crediting the request rather than the return value would make a
	# nearly-empty tree yield infinite wood.
	var n := SimResourceNode.new()
	n.amount = 7
	n.starting_amount = 7
	assert_eq(n.gather(5), 5)
	assert_eq(n.amount, 2)
	assert_eq(n.gather(5), 2, "only 2 were left")
	assert_eq(n.amount, 0)
	assert_true(n.is_depleted())
	assert_eq(n.gather(5), 0, "a depleted node yields nothing")


func test_remaining_fraction_reports_depletion() -> void:
	var n := SimResourceNode.new()
	n.amount = 100
	n.starting_amount = 100
	assert_almost_eq(n.remaining_fraction(), 1.0)
	n.gather(75)
	assert_almost_eq(n.remaining_fraction(), 0.25)
	assert_almost_eq(SimResourceNode.new().remaining_fraction(), 0.0, 0.0001,
			"an unconfigured node does not divide by zero")


func test_build_progress_moves_through_the_phases_and_reports_completion() -> void:
	var b := SimBuilding.new()
	b.build_total = 100
	b.max_hp = 550
	assert_eq(b.phase, SimBuilding.Phase.FOUNDATION)
	assert_false(b.add_build_progress(40), "not done yet")
	assert_eq(b.phase, SimBuilding.Phase.UNDER_CONSTRUCTION)
	assert_almost_eq(b.build_fraction(), 0.4)
	assert_eq(b.hp, 220, "hp rises with build progress, not stuck at the starting sliver")
	assert_true(b.add_build_progress(60), "returns true on the tick it completes")
	assert_eq(b.phase, SimBuilding.Phase.COMPLETE)
	assert_eq(b.hp, 550, "full hp on completion, not left short by a rounding remainder")
	assert_false(b.add_build_progress(10), "and does not complete twice")
	assert_eq(b.build_progress, 100, "progress does not overshoot the total")


func test_a_building_with_no_build_time_is_already_finished() -> void:
	# 2.6's starting town centre has build_progress == build_total == whatever
	# buildings.json says, but a def with no build time must not divide by zero.
	var b := SimBuilding.new()
	assert_almost_eq(b.build_fraction(), 1.0)
