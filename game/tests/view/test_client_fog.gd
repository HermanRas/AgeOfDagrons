## The fog a client computes for itself (PLAN.md 12.1f).
##
## THE TEST THAT MATTERS IS THE FIRST ONE: the grid this produces must be the grid
## `VisionSystem` produces for the same world. Everything else here is detail. The whole
## risk of not sending the fog is that two implementations of the same circle drift apart,
## and fog is exactly the sort of cosmetic thing that could diverge for weeks before
## anybody noticed -- so it is asserted tile by tile against the server's own answer,
## rather than by checking that it looks about right.
extends TestCase

var world: SimWorld
var cfg: MatchConfig


func before_each() -> void:
	cfg = MatchConfig.debug_generated(3, MapGenerator.Type.FOREST, 2)
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)


## The snapshot's `updated` array, exactly as it goes over the wire and exactly what
## `GameView` hands to `ClientFog`.
##
## THE RAW ENTRIES, deliberately -- not `GameView._facts`. The first version of this class
## read `pos` out of `_facts`, which does not have it: `_facts` stores `tile`, already
## divided down to whole tiles. Every entity came out at tile (0, 0) and the fog lit a
## wedge at the map origin. **Every test in this file passed**, because they all fed it
## wire entries, which have `pos` -- so the tests were right and the caller was wrong, and
## only a screenshot showed it. Hence this helper returns the same shape the real caller
## passes, and nothing here builds a convenient dictionary of its own.
func _entries_for(player_id: int) -> Array:
	return SnapshotSystem.build(world, player_id).get("updated", [])


func _client_grid(player_id: int, ticks: int) -> ClientFog:
	var fog := ClientFog.new()
	fog.setup(world.map.size)
	for i in range(ticks):
		world.step()
		fog.apply(_entries_for(player_id), player_id)
	return fog


func test_the_client_computes_exactly_the_grid_the_server_would_have_sent() -> void:
	# The point of the whole change. Run both for long enough that units have wandered and
	# EXPLORED has accumulated behind them, then compare every tile.
	var fog := _client_grid(1, 12)
	var server: PackedByteArray = world.player_for(1).vision

	assert_eq(fog.cells.size(), server.size(), "same shape")
	assert_true(server.size() > 0, "the server actually has fog to compare against")

	var mismatches := 0
	var first := -1
	for i in range(server.size()):
		if fog.cells[i] != server[i]:
			mismatches += 1
			if first < 0:
				first = i
	if mismatches > 0:
		var x := first % world.map.size.x
		var y := first / world.map.size.x
		fail("%d of %d tiles differ; first at (%d, %d): client %d, server %d"
				% [mismatches, server.size(), x, y, fog.cells[first], server[first]])
	else:
		assert_eq(mismatches, 0, "every tile agrees with the server")


func test_it_sees_its_own_town_centre_from_the_footprint_not_the_centre_tile() -> void:
	# The gap that would appear if `_rect_of` used the entity's tile instead of its
	# footprint: a 10x10 building looking out from its middle leaves a blind ring around
	# its own walls. Asserted through the server's agreement above too, but named here so
	# a failure says which rule broke.
	var fog := _client_grid(1, 4)
	var found := false
	for e in world.entities.values():
		if e is SimBuilding and e.owner_id == 1:
			var rect: Rect2i = (e as SimBuilding).footprint_rect()
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var i := y * world.map.size.x + x
					assert_eq(fog.cells[i], SimPlayer.Fog.VISIBLE,
							"tile (%d, %d) of my own building is visible" % [x, y])
			found = true
			break
	assert_true(found, "player 1 has a building to stand on")


func test_explored_is_sticky_and_visible_is_not() -> void:
	# The asymmetry every RTS has: ground you walked past stays drawn, but you do not keep
	# seeing what is happening on it.
	var fog := ClientFog.new()
	fog.setup(world.map.size)
	world.step()
	fog.apply(_entries_for(1), 1)

	var lit: Array[int] = []
	for i in range(fog.cells.size()):
		if fog.cells[i] == SimPlayer.Fog.VISIBLE:
			lit.append(i)
	assert_true(lit.size() > 0, "something is visible to begin with")

	# Nobody's entities at all: everything currently visible must fall back to explored,
	# and nothing may fall all the way to unseen.
	fog.apply([], 1)
	for i in lit:
		assert_eq(fog.cells[i], SimPlayer.Fog.EXPLORED,
				"tile %d decayed to explored rather than staying lit or going dark" % i)


func test_a_dead_entity_lights_nothing() -> void:
	# `VisionSystem` skips them for a reason worth keeping: the scout you just lost should
	# not still be lighting up the map in the snapshot that tells you it died.
	world.step()
	var entries := _entries_for(1)
	for entry in entries:
		entry["alive"] = false

	var fog := ClientFog.new()
	fog.setup(world.map.size)
	fog.apply(entries, 1)
	for i in range(fog.cells.size()):
		if fog.cells[i] == SimPlayer.Fog.VISIBLE:
			fail("tile %d lit by an entity that is not alive" % i)
	assert_eq(0, 0, "nothing was lit")


func test_another_players_entities_light_nothing_of_yours() -> void:
	# Player 2's units are not in player 1's facts at all, but the filter here is the
	# second line of defence and cheap to assert.
	world.step()
	var fog := ClientFog.new()
	fog.setup(world.map.size)
	fog.apply(_entries_for(2), 1)          # player 2's facts, asked as player 1
	for i in range(fog.cells.size()):
		if fog.cells[i] == SimPlayer.Fog.VISIBLE:
			fail("tile %d lit by somebody else's entity" % i)
	assert_eq(0, 0, "nothing was lit")


func test_no_board_means_no_fog_rather_than_a_black_screen() -> void:
	# A unit test's snapshot, or a replay from before 2.5. An empty grid is what every
	# reader already treats as "draw none".
	var fog := ClientFog.new()
	assert_true(fog.cells.is_empty())
	fog.apply(_entries_for(1), 1)
	assert_true(fog.cells.is_empty(), "applying facts to a fog with no board is a no-op")


func test_the_snapshot_no_longer_carries_a_fog_grid() -> void:
	# The saving itself. 36,872 bytes of it on an 8-player board, every tick, per player.
	world.step()
	var snap := SnapshotSystem.build(world, 1)
	assert_false(snap.has("vision"),
			"the grid is computed by the client now, not shipped to it")
