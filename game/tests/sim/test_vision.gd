## Fog of war (PLAN.md 2.5): `VisionSystem` computes it, and `SnapshotSystem` spends
## it.
##
## The second half is the one that matters and gets the most tests here. Vision on
## its own is a drawing hint; vision used to filter the snapshot is the security
## property PLAN.md 5.1 step 6 states -- "the server must not send a client entities
## it cannot see" -- so most of what follows is written as "what does player 1
## actually receive", not "what does the grid say".
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


func _player(id: int) -> SimPlayer:
	return w.player_for(id)


func _fog(id: int, t: Vector2i) -> int:
	return VisionSystem.fog_at(w, _player(id), t)


## Ids present in player `id`'s snapshot, sorted.
func _sent_to(id: int) -> Array[int]:
	var ids: Array[int] = []
	for entry in SnapshotSystem.build(w, id)["updated"]:
		ids.append(int((entry as Dictionary)["id"]))
	ids.sort()
	return ids


func _entry_for(id: int, entity_id: int) -> Dictionary:
	for entry in SnapshotSystem.build(w, id)["updated"]:
		if int((entry as Dictionary)["id"]) == entity_id:
			return entry
	return {}


## Put `u` on `tile` at once, without walking it there. Both halves are needed and
## the second is easy to forget: `pos` is where the unit IS, and `SpatialHash` is
## how everything else finds it, so setting only the first leaves a unit that
## renders in one place and is queried in another.
##
## Written as a helper after five copies of it called `spatial.update()`, which does
## not exist -- the method is `move()`. GDScript raises on the bad call and ABORTS
## the test function, so four of those five still reported PASS on the assertions
## they had already made before the line was reached. Only the one where it came
## first was caught, by the runner's zero-assertion rule.
func _teleport(u: SimUnit, tile: Vector2i) -> void:
	u.pos = tile * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE / 2, SimWorld.SUBTILE / 2)
	w.spatial.move(u.id, u.tile())


# ── the grid ────────────────────────────────────────────────────────────────

func test_a_world_that_has_never_ticked_has_no_fog_at_all() -> void:
	# EMPTY MEANS NO FOG, deliberately: most of the sim suite never steps, and a
	# freshly set up world reading as entirely unseen would hide the whole map from
	# everybody -- indistinguishable from a filter that had simply broken.
	assert_true(_player(1).vision.is_empty())
	assert_eq(_fog(1, Vector2i(5, 5)), SimPlayer.Fog.VISIBLE, "no fog reads as lit")


func test_one_tick_allocates_the_grid_and_reveals_what_a_unit_stands_on() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_eq(_player(1).vision.size(), 48 * 48, "one byte per tile")
	assert_eq(_fog(1, v.tile()), SimPlayer.Fog.VISIBLE, "you can see where you stand")


func test_vision_is_a_circle_of_the_units_own_los() -> void:
	# The villager's los is 4 (units.json), and the shape is Euclidean rather than the
	# square a Chebyshev range would give: (3, 3) is 4.24 away and must be dark while
	# (4, 0) is exactly 4 and must be lit.
	var los: int = (GameDataRegistry.unit(&"unit.villager") as UnitDef).los
	assert_eq(los, 4, "the fixture only means anything at the authored range")
	var at := Vector2i(20, 20)
	w.spawn_unit(&"unit.villager", 1, at)
	w.step()

	assert_eq(_fog(1, at + Vector2i(los, 0)), SimPlayer.Fog.VISIBLE, "dead ahead, at range")
	assert_eq(_fog(1, at + Vector2i(0, -los)), SimPlayer.Fog.VISIBLE)
	assert_eq(_fog(1, at + Vector2i(los + 1, 0)), SimPlayer.Fog.UNSEEN, "one tile too far")
	assert_eq(_fog(1, at + Vector2i(3, 3)), SimPlayer.Fog.UNSEEN,
			"a corner of the square is outside the circle")


func test_a_building_sees_from_its_walls_and_not_from_its_middle() -> void:
	# A 10x10 town centre with los 8 measured from the centre tile would see barely
	# three tiles past its own wall, and the player would have a blind spot exactly
	# where their base is.
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	var los: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).los
	w.step()

	var rect := tc.footprint_rect()
	assert_eq(_fog(1, rect.position), SimPlayer.Fog.VISIBLE, "its own ground")
	var beyond := Vector2i(rect.end.x - 1 + los, rect.position.y)
	assert_eq(_fog(1, beyond), SimPlayer.Fog.VISIBLE,
			"%d tiles clear of the east wall at los %d" % [los, los])
	assert_eq(_fog(1, beyond + Vector2i(1, 0)), SimPlayer.Fog.UNSEEN)


func test_explored_ground_stays_explored_but_stops_being_visible() -> void:
	# The third state earning its place: the ground does not move, so it stays drawn;
	# what was standing on it does, so it stops being sent.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.step()
	var seen := Vector2i(5, 5)
	assert_eq(_fog(1, seen), SimPlayer.Fog.VISIBLE)

	_teleport(v, Vector2i(40, 40))
	w.step()
	assert_eq(_fog(1, seen), SimPlayer.Fog.EXPLORED, "remembered, not currently watched")
	assert_eq(_fog(1, Vector2i(40, 40)), SimPlayer.Fog.VISIBLE, "and the new ground is lit")


func test_a_dead_scout_lights_nothing() -> void:
	# VisionSystem runs after DeathSystem, so the unit you just lost is not still
	# revealing the map in the very snapshot that reports its death.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_eq(_fog(1, Vector2i(20, 20)), SimPlayer.Fog.VISIBLE)

	v.alive = false
	w.step()
	assert_eq(_fog(1, Vector2i(20, 20)), SimPlayer.Fog.EXPLORED, "a corpse is not a scout")


func test_each_player_has_their_own_fog() -> void:
	w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	w.step()
	assert_eq(_fog(1, Vector2i(5, 5)), SimPlayer.Fog.VISIBLE)
	assert_eq(_fog(1, Vector2i(40, 40)), SimPlayer.Fog.UNSEEN)
	assert_eq(_fog(2, Vector2i(40, 40)), SimPlayer.Fog.VISIBLE)
	assert_eq(_fog(2, Vector2i(5, 5)), SimPlayer.Fog.UNSEEN)


func test_the_fog_is_part_of_the_state_hash() -> void:
	# It decides what each client is SENT, and it is the one piece of per-player state
	# that never comes back to be checked -- so two hosts disagreeing about it would
	# disagree about the wire while every entity still matched.
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	other.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.step()
	other.step()
	assert_eq(w.state_hash(), other.state_hash(), "same world, same fog")

	_player(1).vision[0] = SimPlayer.Fog.VISIBLE if _player(1).vision[0] == 0 else 0
	assert_ne(w.state_hash(), other.state_hash(), "one tile of fog is a divergence")


# ── the filter: what the client is actually sent ────────────────────────────

func test_your_own_units_are_sent_wherever_they_are() -> void:
	# Including into an unexplored corner: a unit must never vanish from its owner.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	w.step()
	assert_true(_sent_to(1).has(v.id))


func test_an_enemy_unit_out_of_vision_is_not_sent_at_all() -> void:
	# THE ONE THAT MATTERS. Its position is exactly what would leak.
	var mine := w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	var theirs := w.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	w.step()

	var sent := _sent_to(1)
	assert_true(sent.has(mine.id), "my own villager")
	assert_false(sent.has(theirs.id), "and no word of theirs")


func test_an_enemy_unit_in_vision_is_sent_in_full() -> void:
	w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var theirs := w.spawn_unit(&"unit.villager", 2, Vector2i(21, 20))
	w.step()

	var entry := _entry_for(1, theirs.id)
	assert_false(entry.is_empty(), "standing right next to mine")
	assert_true(entry.has("hp"), "and in full, not remembered")
	assert_false(bool(entry.get("remembered", false)))


func test_a_walked_past_enemy_unit_disappears_again() -> void:
	# Explored ground keeps its terrain, never its traffic.
	var scout := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var theirs := w.spawn_unit(&"unit.villager", 2, Vector2i(21, 20))
	w.step()
	assert_true(_sent_to(1).has(theirs.id))

	_teleport(scout, Vector2i(2, 2))
	w.step()
	assert_eq(_fog(1, Vector2i(21, 20)), SimPlayer.Fog.EXPLORED, "still remembered ground")
	assert_false(_sent_to(1).has(theirs.id), "but they are not on it as far as we know")


func test_an_explored_building_is_still_sent_but_only_as_a_memory() -> void:
	# A building does not move, so telling the player it is there gives away nothing
	# that will have changed -- and it is what makes an explored hillside keep the
	# town somebody built on it.
	var scout := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))
	var theirs := w.spawn_building(&"building.house", 2, Vector2i(31, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_false(bool(_entry_for(1, theirs.id).get("remembered", false)), "seen in full")

	_teleport(scout, Vector2i(2, 2))
	w.step()

	var entry := _entry_for(1, theirs.id)
	assert_false(entry.is_empty(), "the house is remembered")
	assert_true(bool(entry["remembered"]))
	assert_false(entry.has("hp"), "but not whether it is being burned down")
	assert_false(entry.has("max_hp"))
	assert_false(entry.has("queue"), "nor what it is training")
	assert_true(entry.has("pos"), "it is still somewhere, and still something")
	assert_true(entry.has("def_id"))


func test_an_explored_resource_node_is_remembered_without_its_amount() -> void:
	# Same rule, and gaia's trees are most of what it applies to. How much wood is
	# left in a forest last seen an hour ago is a commentary on somebody's economy.
	var scout := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(31, 30), 1)
	w.step()
	assert_true(_entry_for(1, tree.id).has("amount"), "in plain sight, in full")

	_teleport(scout, Vector2i(2, 2))
	w.step()

	var entry := _entry_for(1, tree.id)
	assert_true(bool(entry.get("remembered", false)), "the forest is still there")
	assert_false(entry.has("amount"), "but not how much is left in it")


func test_a_never_explored_building_is_not_sent() -> void:
	w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	var theirs := w.spawn_building(&"building.house", 2, Vector2i(40, 40),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_false(_sent_to(1).has(theirs.id))


func test_a_building_destroyed_behind_the_fog_stops_being_sent() -> void:
	# The documented simplification: AoE would leave a stale ghost, which needs a
	# per-player copy of every static as it was last seen. This leaks "it is gone" and
	# never leaks anything live.
	var scout := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))
	var theirs := w.spawn_building(&"building.house", 2, Vector2i(31, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	_teleport(scout, Vector2i(2, 2))
	w.step()
	assert_true(_sent_to(1).has(theirs.id), "remembered while it stands")

	theirs.alive = false
	w.step()
	assert_false(_sent_to(1).has(theirs.id))


func test_a_big_building_is_seen_from_any_corner_of_its_footprint() -> void:
	# Any tile, not all of them: requiring the whole footprint would make a town
	# centre vanish while its owner stood next to it.
	var tc := w.spawn_building(&"building.town_center", 2, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	# One tile off the north-west corner, far from the far side of a 10x10.
	w.spawn_unit(&"unit.villager", 1, tc.footprint_rect().position - Vector2i(1, 1))
	w.step()

	var entry := _entry_for(1, tc.id)
	assert_false(entry.is_empty())
	assert_false(bool(entry.get("remembered", false)), "seen, not merely remembered")


func test_the_snapshot_carries_only_the_viewers_own_fog() -> void:
	# Shipping everybody's grid would hand the client the very map the filter exists
	# to withhold.
	w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	w.step()

	var mine: PackedByteArray = SnapshotSystem.build(w, 1)["vision"]
	assert_eq(mine.size(), 48 * 48)
	assert_eq(mine, _player(1).vision)
	assert_ne(mine, _player(2).vision, "and it is not the other player's")

	var snap := SnapshotSystem.build(w, 1)
	assert_false(snap.has("player_state") and (snap["player_state"][2] as Dictionary).has("vision"),
			"no per-player vision rides in player_state either")


func test_a_player_who_is_not_in_the_world_sees_everything() -> void:
	# A spectator, a replay, or a test asking for a player id the world has never
	# heard of. Unfiltered is the useful answer and the safe one -- there is no client
	# on the other end of it to withhold anything from.
	w.spawn_unit(&"unit.villager", 1, Vector2i(5, 5))
	w.spawn_unit(&"unit.villager", 2, Vector2i(40, 40))
	w.step()
	assert_eq(_sent_to(99).size(), 2)
