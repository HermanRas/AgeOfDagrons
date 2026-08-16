## PLAN.md 5.4: enqueue, progress, cancel/refund, spawn on a free adjacent tile.
extends TestCase

var w: SimWorld
var player: SimPlayer
var tc: SimBuilding


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	player = w.player_for(1)
	player.stock = {&"food": 1000}
	tc = w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)


func _villager_count() -> int:
	var n := 0
	for e in w.entities.values():
		if e is SimUnit:
			n += 1
	return n


func _train() -> void:
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()


func test_training_pays_the_cost_up_front_and_queues_it() -> void:
	_train()
	assert_eq(player.stock[&"food"], 1000 - 50, "villager costs 50 food (data/units.json)")
	assert_eq(tc.queue.size(), 1)
	assert_eq(_villager_count(), 0, "not spawned yet -- still training")


func test_a_finished_order_spawns_a_unit_on_a_free_adjacent_tile() -> void:
	_train()
	for i in range(300):        # build_time_ticks 250 + a few ticks of margin
		w.step()
		if _villager_count() > 0:
			break
	assert_eq(_villager_count(), 1)
	assert_true(tc.queue.is_empty(), "the queue drained once the unit spawned")

	var v: SimUnit = null
	for e in w.entities.values():
		if e is SimUnit:
			v = e
	assert_eq(v.owner_id, 1)
	assert_false(tc.footprint_rect().has_point(v.tile()), "spawned beside the town centre, not inside it")


func test_cancelling_refunds_the_full_cost_and_nothing_spawns() -> void:
	_train()
	w.queue_command(CancelProductionCommand.new(1, tc.id, 0))
	for i in range(300):
		w.step()

	assert_eq(player.stock[&"food"], 1000, "refunded in full")
	assert_true(tc.queue.is_empty())
	assert_eq(_villager_count(), 0, "a cancelled order never spawns")


func test_training_is_rejected_when_the_player_cannot_afford_it() -> void:
	player.stock = {&"food": 0}
	_train()
	assert_true(tc.queue.is_empty())


func test_training_is_rejected_for_a_building_that_does_not_train_that_unit() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.queue_command(TrainCommand.new(1, house.id, &"unit.villager"))
	w.step()
	assert_true(house.queue.is_empty(), "buildings.json declares houses do not train")
	assert_eq(player.stock[&"food"], 1000, "and nothing was spent")


func test_a_full_town_centre_backs_up_production_rather_than_losing_the_unit() -> void:
	# Wall off the entire map except the town centre's own footprint, so no
	# tile is ever free to spawn onto.
	for y in range(w.map.size.y):
		for x in range(w.map.size.x):
			w.map.set_terrain(Vector2i(x, y), SimMap.Terrain.ROCK)
	w.map.set_terrain_rect(tc.footprint_rect(), SimMap.Terrain.GRASS)
	w.map.set_occupied(tc.footprint_rect(), tc.id)

	_train()
	for i in range(300):
		w.step()
	assert_eq(_villager_count(), 0, "nowhere to stand, so it waits rather than vanishing")
	assert_eq(tc.queue.size(), 1)
	assert_true(bool(tc.queue[0].get("ready", false)), "finished training, just blocked on room")

	# Open one tile far away; the backed-up order should find it.
	w.map.set_terrain(Vector2i(40, 40), SimMap.Terrain.GRASS)
	for i in range(10):
		w.step()
	assert_eq(_villager_count(), 1, "spawned once room existed anywhere on the map")


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_worlds_given_the_same_training_order_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.player_for(1).stock = {&"food": 1000}
	var other_tc := other.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	other.queue_command(TrainCommand.new(1, other_tc.id, &"unit.villager"))

	for i in range(300):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))


func test_the_snapshot_names_what_is_queued_not_only_how_much() -> void:
	# The panel crops each queue slot's portrait from the unit's own sprite, and
	# it can only do that if the def id reaches the client. `queue_len` alone
	# shipped for a while, and every queue slot in the running game drew the word
	# "Queued" instead of a villager.
	_train()
	_train()
	var snap := SnapshotSystem.build(w, 1)
	var entry := {}
	for e in snap["updated"]:
		if int(e.get("id", 0)) == tc.id:
			entry = e
	assert_false(entry.is_empty(), "the town centre is in the snapshot")
	assert_eq(int(entry["queue_len"]), 2)
	assert_eq(entry["queue"], ["unit.villager", "unit.villager"],
			"and it says WHAT is queued")


func test_the_queue_snapshot_carries_no_sim_bookkeeping() -> void:
	# def ids only. `progress`, `total` and `cost` are the sim's own, and
	# `queue_fraction` is the only part of them the view has any use for --
	# shipping the rest would put sim state on the wire for nothing to read.
	_train()
	var snap := SnapshotSystem.build(w, 1)
	for e in snap["updated"]:
		if int(e.get("id", 0)) != tc.id:
			continue
		for queued in e["queue"]:
			assert_true(queued is String, "a bare def id, not the queue entry dictionary")


func test_a_cancelled_entry_leaves_the_snapshot_queue() -> void:
	_train()
	_train()
	w.queue_command(CancelProductionCommand.new(1, tc.id, 0))
	w.step()
	var snap := SnapshotSystem.build(w, 1)
	for e in snap["updated"]:
		if int(e.get("id", 0)) == tc.id:
			assert_eq((e["queue"] as Array).size(), 1)
			assert_eq(int(e["queue_len"]), 1, "the count and the list agree")