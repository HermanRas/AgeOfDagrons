## A building's RALLY POINT (project owner, 2026-08-27), the follow-up to 4.8: select a
## building, tap the ground, and anything leaving that building walks to the flag.
##
## "Anything leaving" is **both** ways out, on the owner's call — a garrison turned out
## and every unit the building trains. They had the same defect for the same reason
## (`find_free_adjacent` sweeps the rect's top edge, so a unit appears *behind* the art),
## and `SimWorld.send_to_waypoint` is one implementation so the two can never disagree.
##
## The cases worth the most here are the ones where the rally point must NOT be honoured
## or must not be seen: a corpse being put out of a falling tower, a fishing ship handed
## a landward flag, and an enemy's rally point on the wire — which is the only piece of
## pure *intention* the snapshot carries.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


func _run_until(pred: Callable, max_ticks: int) -> int:
	for i in range(max_ticks):
		w.step()
		if pred.call():
			return i + 1
	return -1


func _tower(owner: int = 1, at: Vector2i = Vector2i(20, 20)) -> SimBuilding:
	return w.spawn_building(&"building.watch_tower", owner, at)


# ── setting it ──────────────────────────────────────────────────────────────

func test_a_building_starts_with_no_rally_point() -> void:
	var tower := _tower()
	assert_false(tower.waypoint_set())
	assert_eq(tower.waypoint, SimBuilding.NO_WAYPOINT)


func test_the_sentinel_is_minus_one_and_not_zero() -> void:
	# Tile (0, 0) is a real tile on every map, so zero cannot mean "unset".
	assert_eq(SimBuilding.NO_WAYPOINT, Vector2i(-1, -1))
	var tower := _tower()
	tower.waypoint = Vector2i.ZERO
	assert_true(tower.waypoint_set(), "the origin tile is a legitimate rally point")


func test_the_command_sets_it() -> void:
	var tower := _tower()
	assert_true(SetWaypointCommand.new(1, tower.id, Vector2i(30, 30)).validate(w))
	w.queue_command(SetWaypointCommand.new(1, tower.id, Vector2i(30, 30)))
	w.step()
	assert_eq(tower.waypoint, Vector2i(30, 30))


func test_the_command_names_a_state_so_a_repeat_is_harmless() -> void:
	# The shape `ToggleGateCommand` settled on: it says where the flag should BE, not
	# "change it", so a duplicated packet cannot leave two clients disagreeing.
	var tower := _tower()
	for _i in range(3):
		w.queue_command(SetWaypointCommand.new(1, tower.id, Vector2i(30, 30)))
		w.step()
	assert_eq(tower.waypoint, Vector2i(30, 30))


func test_setting_it_again_moves_it() -> void:
	var tower := _tower()
	w.queue_command(SetWaypointCommand.new(1, tower.id, Vector2i(30, 30)))
	w.step()
	w.queue_command(SetWaypointCommand.new(1, tower.id, Vector2i(10, 10)))
	w.step()
	assert_eq(tower.waypoint, Vector2i(10, 10))


func test_the_sentinel_clears_it_and_is_always_legal() -> void:
	var tower := _tower()
	tower.waypoint = Vector2i(30, 30)
	assert_true(SetWaypointCommand.new(1, tower.id, SimBuilding.NO_WAYPOINT).validate(w))
	w.queue_command(SetWaypointCommand.new(1, tower.id, SimBuilding.NO_WAYPOINT))
	w.step()
	assert_false(tower.waypoint_set())


func test_a_tile_off_the_map_is_refused() -> void:
	var tower := _tower()
	assert_false(SetWaypointCommand.new(1, tower.id, Vector2i(999, 4)).validate(w))
	assert_false(SetWaypointCommand.new(1, tower.id, Vector2i(4, -7)).validate(w))


func test_you_cannot_set_a_rally_point_on_somebody_elses_building() -> void:
	var theirs := _tower(2)
	assert_false(SetWaypointCommand.new(1, theirs.id, Vector2i(30, 30)).validate(w))


func test_a_destroyed_building_takes_no_orders() -> void:
	var tower := _tower()
	tower.take_damage(tower.hp, 0)
	assert_false(SetWaypointCommand.new(1, tower.id, Vector2i(30, 30)).validate(w))


func test_any_owned_building_accepts_one_even_if_it_does_nothing() -> void:
	# A rally point on a house is pointless and allowed: a tap that is silently ignored
	# is worse than a flag that turns out to do nothing, because the flag at least says
	# what the game thought you meant.
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 20))
	assert_true(SetWaypointCommand.new(1, house.id, Vector2i(10, 10)).validate(w))


func test_a_foundation_accepts_one_so_it_is_ready_when_it_finishes() -> void:
	var tower := w.spawn_building(&"building.watch_tower", 1, Vector2i(20, 20),
			SimBuilding.Phase.FOUNDATION)
	assert_true(SetWaypointCommand.new(1, tower.id, Vector2i(10, 10)).validate(w))


# ── the garrison walks to it ────────────────────────────────────────────────

func test_an_ejected_garrison_walks_to_the_rally_point() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))
	tower.waypoint = Vector2i(30, 30)

	w.queue_command(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL))
	w.step()

	assert_eq(archer.garrisoned_in, 0)
	assert_eq(archer.task, SimUnit.Task.MOVE, "it was given an order, not left standing")
	assert_eq(archer.task_target_tile, Vector2i(30, 30))
	assert_true(_run_until(func(): return archer.tile() == Vector2i(30, 30), 900) > 0,
			"and it got there")


func test_without_one_it_stands_where_it_came_out_exactly_as_before() -> void:
	# The owner's words: "happy for current ejection if no waypoint is set".
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))
	assert_false(tower.waypoint_set())

	w.queue_command(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL))
	w.step()

	assert_true(archer.is_idle(), "no order")
	assert_eq(CombatSystem.tile_gap(archer.tile(), tower.footprint_rect()), 1,
			"standing against the building, which is the old behaviour")


func test_a_whole_garrison_is_sent_not_just_the_first() -> void:
	var tower := _tower()
	var inside: Array[SimUnit] = []
	for i in range(5):
		var u := w.spawn_unit(&"unit.archer", 1, Vector2i(21 + i, 24))
		inside.append(u)
		assert_true(w.garrison_unit(tower, u))
	tower.waypoint = Vector2i(30, 30)

	w.queue_command(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL))
	w.step()
	for u in inside:
		assert_eq(u.task_target_tile, Vector2i(30, 30), "unit %d" % u.id)


# ── trained units walk to it too (the owner's call) ─────────────────────────

func test_a_trained_unit_walks_to_the_rally_point() -> void:
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10))
	tc.waypoint = Vector2i(30, 30)
	tc.enqueue_training(&"unit.villager", 1, {})

	var trained := _run_until(func(): return _newest_unit() != null, 60)
	assert_true(trained > 0, "something was trained")
	var u := _newest_unit()
	assert_eq(u.task, SimUnit.Task.MOVE)
	assert_eq(u.task_target_tile, Vector2i(30, 30))


func test_a_trained_unit_without_a_rally_point_is_left_alone() -> void:
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10))
	tc.enqueue_training(&"unit.villager", 1, {})

	assert_true(_run_until(func(): return _newest_unit() != null, 60) > 0)
	assert_true(_newest_unit().is_idle(),
			"production behaves exactly as it has since 5.4")


func test_every_unit_of_a_queue_is_sent_not_only_the_first() -> void:
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10))
	tc.waypoint = Vector2i(30, 30)
	for _i in range(3):
		tc.enqueue_training(&"unit.villager", 1, {})

	assert_true(_run_until(func(): return tc.queue.is_empty(), 200) > 0)
	var sent := 0
	for e in w.entities.values():
		if e is SimUnit and (e as SimUnit).task_target_tile == Vector2i(30, 30):
			sent += 1
	assert_eq(sent, 3)


## The most recently spawned unit, by id — `_next_id` only ever increases.
func _newest_unit() -> SimUnit:
	var best: SimUnit = null
	for e in w.entities.values():
		if e is SimUnit and (best == null or e.id > best.id):
			best = e
	return best


# ── the cases where it must NOT apply ──────────────────────────────────────

func test_a_garrison_killed_with_its_building_is_not_sent_anywhere() -> void:
	# They are put out so their corpses have somewhere to be, not sent. Walking a unit
	# toward a flag on the tick it dies would be a route search for a corpse.
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))
	tower.waypoint = Vector2i(30, 30)

	tower.take_damage(tower.hp, 0)
	w.step()

	assert_false(archer.alive)
	assert_ne(archer.task, SimUnit.Task.MOVE, "no order was given to a dying unit")


func test_a_ship_handed_a_landward_rally_point_simply_stays_put() -> void:
	# The bug this shape cannot reintroduce: "boats spawn and sail on land, its very
	# funny" (2026-08-23). An unreachable route comes back empty, `set_path([])` retires
	# the task, and the ship is left where it was launched.
	var dock := w.spawn_building(&"building.dock", 1, Vector2i(20, 30))
	assert_not_null(dock)
	dock.waypoint = Vector2i(30, 10)          # solid grass, no water anywhere near
	dock.enqueue_training(&"unit.fishing_ship", 1, {})

	for _i in range(120):
		w.step()
	for e in w.entities.values():
		if e is SimUnit and (e as SimUnit).def_id == &"unit.fishing_ship":
			assert_ne(e.tile(), Vector2i(30, 10), "it did not walk onto the grass")


func test_an_unreachable_rally_point_does_not_strand_the_unit() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))
	# Legal tile, but walled off from everything by impassable terrain around it.
	tower.waypoint = Vector2i(40, 40)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			w.map.set_terrain(Vector2i(40, 40) + Vector2i(dx, dy), SimMap.Terrain.WATER_DEEP)
	if w.paths != null:
		w.paths.mark_dirty(Rect2i(Vector2i(38, 38), Vector2i(5, 5)))

	w.queue_command(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL))
	for _i in range(120):
		w.step()
	assert_eq(archer.garrisoned_in, 0, "it is out")
	assert_true(archer.alive)


# ── the wire, the hash, and the one thing that must not leak ───────────────

func test_the_command_survives_the_wire() -> void:
	var back := Command.from_dict(
			SetWaypointCommand.new(4, 77, Vector2i(12, 34), 9).to_dict())
	assert_true(back is SetWaypointCommand)
	assert_eq((back as SetWaypointCommand).building_id, 77)
	assert_eq((back as SetWaypointCommand).tile, Vector2i(12, 34))
	assert_eq(back.player_id, 4)
	assert_eq(back.issued_tick, 9)


func test_the_command_carries_its_tile_as_plain_json() -> void:
	# A command dict is JSON-stringified into the replay log, and JSON has no Vector2i.
	# The SNAPSHOT's copy of the same tile is a Vector2i, because snapshots are binary.
	var d := SetWaypointCommand.new(1, 5, Vector2i(3, 7)).to_dict()
	assert_true(d["tile"] is Dictionary)
	var round_trip = JSON.parse_string(JSON.stringify(d))
	assert_eq(int(round_trip["tile"]["x"]), 3)
	assert_eq(int(round_trip["tile"]["y"]), 7)


func test_it_is_in_the_state_hash() -> void:
	# Two hosts disagreeing about a rally point send the same trained army to two
	# different places, which `pos` only reports seconds later.
	var tower := _tower()
	var before := w.state_hash()
	tower.waypoint = Vector2i(30, 30)
	assert_ne(w.state_hash(), before)


func test_the_owner_is_told_their_own_rally_point() -> void:
	var tower := _tower(1)
	tower.waypoint = Vector2i(30, 30)
	w.step()
	assert_eq(_entry(1, tower.id).get("waypoint"), Vector2i(30, 30))


func test_an_enemys_rally_point_is_blanked_rather_than_sent() -> void:
	# Where an enemy is massing is their INTENTION, not a fact about the world you could
	# get by looking at their tower.
	var theirs := _tower(2)
	theirs.waypoint = Vector2i(30, 30)
	_give_everyone_vision()
	w.step()

	var entry := _entry(1, theirs.id)
	assert_false(entry.is_empty(), "player 1 can see the building itself")
	assert_eq(entry.get("waypoint"), SimBuilding.NO_WAYPOINT,
			"but not where its garrison is being sent")


func test_it_is_blanked_and_not_erased_so_buildings_keep_one_wire_shape() -> void:
	# `to_wire` groups `updated` into shape tables by sorted field names (12.1f), so
	# erasing the key for enemies would split EVERY building in the game into two
	# shapes -- costing more than the Vector2i it saved.
	var mine := _tower(1, Vector2i(10, 10))
	var theirs := _tower(2, Vector2i(30, 30))
	theirs.waypoint = Vector2i(31, 31)
	_give_everyone_vision()
	w.step()

	assert_true(_entry(1, mine.id).has("waypoint"))
	assert_true(_entry(1, theirs.id).has("waypoint"), "present, just blank")
	var a := _entry(1, mine.id).keys()
	var b := _entry(1, theirs.id).keys()
	a.sort()
	b.sort()
	assert_eq(a, b, "identical field sets, so identical wire shapes")


func test_a_remembered_building_reports_no_rally_point() -> void:
	var theirs := _tower(2)
	theirs.waypoint = Vector2i(30, 30)
	assert_false(SnapshotSystem._remembered(theirs).has("waypoint"))


## Enough vision for player 1 to see the whole board, so `_entry_for` takes its
## "visible enemy" branch rather than the remembered one.
##
## A NON-EMPTY `vision` IS ALSO WHAT TURNS THE FILTER ON: `SimPlayer.vision`'s own note
## records that empty means "no fog", and `_entry_for` returns the full snapshot for
## everybody in that case. So a test about the fog filter has to fill this in, or it
## quietly asserts nothing about the filter at all.
func _give_everyone_vision() -> void:
	for p in w.players:
		p.vision = PackedByteArray()
		p.vision.resize(w.map.size.x * w.map.size.y)
		p.vision.fill(SimPlayer.Fog.VISIBLE)


func _entry(viewer: int, id: int) -> Dictionary:
	for entry in SnapshotSystem.build(w, viewer).get("updated", []):
		if int(entry["id"]) == id:
			return entry
	return {}


# ── determinism ─────────────────────────────────────────────────────────────

func test_two_worlds_with_the_same_rally_point_stay_identical() -> void:
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	for world in [w, other]:
		var tc: SimBuilding = world.spawn_building(&"building.town_center", 1,
				Vector2i(10, 10))
		world.queue_command(SetWaypointCommand.new(1, tc.id, Vector2i(30, 30)))
		for _i in range(4):
			tc.enqueue_training(&"unit.villager", 1, {})

	for _i in range(400):
		w.step()
		other.step()
	assert_eq(w.state_hash(), other.state_hash())
