## The age axis end to end: advancing it, and the two orders that gate on it.
##
## Worth its own file because age is the one piece of state whose CONSUMERS
## arrived before its producer. Buildings re-skin per age (PLAN.md 2.7), the
## menus gate on it, and the sim now refuses an order above the caller's age --
## all built before there was any way to advance. DebugSetAgeCommand is that way,
## and these are what say it works before anyone taps a button on a phone.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


func _player(id: int = 1) -> SimPlayer:
	return w.player_for(id)


func _rich(id: int = 1) -> void:
	for kind in [&"food", &"wood", &"gold", &"stone"]:
		_player(id).add_resource(kind, 10000)


# ── advancing ───────────────────────────────────────────────────────────────

func test_a_match_starts_in_age_one() -> void:
	assert_eq(_player().age, 1, "SimPlayer.age is 1-indexed and every match opens there")


func test_the_debug_command_moves_the_callers_age() -> void:
	w.queue_command(DebugSetAgeCommand.new(1, 3))
	w.step()
	assert_eq(_player(1).age, 3)


func test_it_moves_only_the_caller() -> void:
	# No target field at all, so ageing someone else is not expressible rather
	# than merely refused -- the strongest form of the ownership rule.
	w.queue_command(DebugSetAgeCommand.new(1, 4))
	w.step()
	assert_eq(_player(1).age, 4)
	assert_eq(_player(2).age, 1, "player 2 stayed where they were")


func test_an_age_outside_the_ladder_is_refused_rather_than_clamped() -> void:
	# Clamping would make "advance past the last age" silently succeed, and the
	# badge decides whether there IS a next age from the same age_count() -- so a
	# rejection here is the signal that the two have drifted apart.
	for bad in [0, -1, GameDataRegistry.age_count() + 1, 99]:
		w.queue_command(DebugSetAgeCommand.new(1, bad))
		w.step()
		assert_eq(_player(1).age, 1, "age %d is not on the ladder" % bad)


func test_the_age_is_absolute_so_applying_it_twice_is_the_same_as_once() -> void:
	# Why it is not a delta: a resend or a replay seam would compound one.
	w.queue_command(DebugSetAgeCommand.new(1, 3))
	w.queue_command(DebugSetAgeCommand.new(1, 3))
	w.step()
	assert_eq(_player(1).age, 3)


func test_the_age_survives_a_round_trip_through_the_wire_format() -> void:
	# Commands cross the net as dictionaries even in a solo match (PLAN.md 1.1),
	# so a command missing from Command.from_dict()'s match is one that works in
	# tests and vanishes in the game.
	var decoded := Command.from_dict(DebugSetAgeCommand.new(1, 4, 7).to_dict())
	assert_not_null(decoded, "debug_set_age is registered in Command.from_dict")
	assert_true(decoded is DebugSetAgeCommand)
	assert_eq((decoded as DebugSetAgeCommand).age, 4)
	assert_eq(decoded.player_id, 1)


func test_the_age_rides_the_snapshot_so_the_view_can_re_skin() -> void:
	# The whole point of advancing: SimPlayer.age reaching the client is what
	# makes a standing building change its art (PLAN.md 2.7 item 2).
	w.queue_command(DebugSetAgeCommand.new(1, 2))
	w.step()
	var snap := SnapshotSystem.build(w, 1)
	assert_eq(int(snap["player_state"][1]["age"]), 2)


# ── the sim enforces the gate the menus draw ────────────────────────────────

func test_a_building_above_the_callers_age_is_refused() -> void:
	# The menu already hides the wonder in age 1; this is what makes hiding it
	# SUFFICIENT, since the menu is a client and the server is the only trust
	# boundary (PLAN.md 5.1 step 4).
	_rich()
	var cmd := PlaceBuildingCommand.new(1, &"building.wonder", Vector2i(10, 10))
	assert_false(cmd.validate(w), "a wonder is age 4 and the caller is age 1")

	w.queue_command(DebugSetAgeCommand.new(1, 4))
	w.step()
	assert_true(cmd.validate(w), "and allowed once they get there")


func test_an_affordable_age_one_building_is_still_placeable() -> void:
	# The gate must not have quietly broken the ordinary case.
	_rich()
	assert_true(PlaceBuildingCommand.new(1, &"building.house", Vector2i(10, 10)).validate(w))


func test_a_unit_above_the_callers_age_is_refused_at_its_own_building() -> void:
	# `trains` is the building's roster across ALL ages, so without the per-unit
	# gate an age-2 archery range would happily queue a crossbowman.
	_rich()
	w.queue_command(DebugSetAgeCommand.new(1, 2))
	w.step()
	var range_building := w.spawn_building(&"building.archery_range", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)

	assert_true(TrainCommand.new(1, range_building.id, &"unit.archer").validate(w),
			"archers unlock with the range itself")
	assert_false(TrainCommand.new(1, range_building.id, &"unit.crossbowman").validate(w),
			"crossbowmen are age 3")

	w.queue_command(DebugSetAgeCommand.new(1, 3))
	w.step()
	assert_true(TrainCommand.new(1, range_building.id, &"unit.crossbowman").validate(w))


func test_the_gate_is_the_age_and_not_the_cost() -> void:
	# A player who can afford a crossbowman and is too young must still be
	# refused, or the gate is only ever doing what the price already did.
	_rich()
	var range_building := w.spawn_building(&"building.archery_range", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	var cmd := TrainCommand.new(1, range_building.id, &"unit.crossbowman")
	assert_true(_player().can_afford(GameDataRegistry.unit(&"unit.crossbowman").cost),
			"the cost is not what is stopping them")
	assert_false(cmd.validate(w))


func test_every_unit_becomes_trainable_by_age_four() -> void:
	# A sweep, because a typo in one `age_required` produces a unit that is in the
	# roster and can never be built -- which nothing else would report.
	_rich()
	w.queue_command(DebugSetAgeCommand.new(1, 4))
	w.step()

	var tile := Vector2i(6, 6)
	for building_id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(building_id)
		if bd.trains.is_empty():
			continue
		var b := w.spawn_building(building_id, 1, tile, SimBuilding.Phase.COMPLETE, true)
		tile.x += 12
		if tile.x > 34:
			tile.x = 6
			tile.y += 12
		for unit_id in bd.trains:
			assert_true(TrainCommand.new(1, b.id, unit_id).validate(w),
					"an age-4 player with full stock can train %s at %s"
					% [unit_id, building_id])
