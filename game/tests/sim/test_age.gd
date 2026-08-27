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
	# ADVANCING COSTS RESOURCES since 2026-08-27 (ages.json took Age of Empires II's
	# ladder: 500 food, then 800+200, then 1000+800). These tests are about the TIMING
	# of an advance, not about affording one, so every player is handed enough to pay
	# for all three. Without it they were being refused for a reason none of them are
	# asking about -- which is what a fixture is for.
	for p in w.players:
		for kind in [&"food", &"wood", &"gold", &"stone"]:
			p.stock[kind] = 100000


func _player(id: int = 1) -> SimPlayer:
	return w.player_for(id)


## Everything a player needs to be refused for AGE REASONS ALONE: full stock, and
## somewhere for the unit to live.
##
## The population half arrived with 4.11's enforcement, and without it every train
## assertion below started failing for the right reason at the wrong time -- a
## `TrainCommand` is now refused at a pop cap of 0, which an empty world always has,
## so "an age-4 player can train a trebuchet" was failing on housing. A town centre
## and a house is 15 pop (buildings.json), comfortably over the dragon's 10, which is
## the most any single unit costs.
##
## Both are FORCED into place and may overlap the buildings a test spawns for itself.
## That is harmless here: nothing in this file asks whether a placement is legal --
## `PlaceBuildingCommand.validate()` is tested against tiles of its own -- and every
## spawn in the file is forced for the same reason.
func _rich(id: int = 1) -> void:
	for kind in [&"food", &"wood", &"gold", &"stone"]:
		_player(id).add_resource(kind, 10000)
	w.spawn_building(&"building.town_center", id, Vector2i(36, 36),
			SimBuilding.Phase.COMPLETE, true)
	w.spawn_building(&"building.house", id, Vector2i(30, 36),
			SimBuilding.Phase.COMPLETE, true)


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


func test_a_debug_jump_cancels_a_research_that_would_otherwise_demote_you() -> void:
	# Found by dev_preview/preview_match.gd on 2026-08-16: the preview starts a
	# real advance to age 2, then jumps to 3 and 4 -- and seconds later the
	# research landed, `tick_advance()` assigned `age = advancing_to`, and an
	# age-4 player was put back to age 2 with every building re-skinning down the
	# ladder behind them.
	_rich()
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	assert_true(_player().is_advancing(), "a research is genuinely in flight")

	w.queue_command(DebugSetAgeCommand.new(1, 4))
	w.step()
	assert_eq(_player().age, 4)
	assert_false(_player().is_advancing(), "the jump cancelled it rather than leaving it running")

	for i in range(_advance_ticks_for(2) + 10):
		w.step()
	assert_eq(_player().age, 4, "and nothing landed later to drag the age back down")


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


# -- timed advancement (9.2) -------------------------------------------------

func _advance_ticks_for(to_age: int) -> int:
	return GameDataRegistry.age(to_age).advance_time_ticks


func test_advancing_takes_time_rather_than_landing_at_once() -> void:
	# The whole difference from DebugSetAgeCommand, and what the ring reports.
	var total := _advance_ticks_for(2)
	assert_true(total > 0, "ages.json gives age 2 a research time")

	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	assert_eq(_player().age, 1, "still age 1 the tick the research starts")
	assert_true(_player().is_advancing())
	assert_eq(_player().advancing_to, 2)
	# AgeSystem runs AFTER CommandSystem within a tick, so an advance ordered
	# this tick is already one tick along by the end of it -- deliberate, and the
	# same reason ProductionSystem sits where it does: an order should not cost a
	# visible tick of nothing happening.
	assert_eq(_player().advance_ticks, 1, "counting from the tick it was ordered")

	for i in range(total - 2):
		w.step()
	assert_eq(_player().age, 1, "and right up to the last tick")
	assert_eq(_player().advance_ticks, total - 1)

	w.step()
	assert_eq(_player().age, 2, "then it lands")
	assert_false(_player().is_advancing(), "and the research clears itself")
	assert_eq(_player().advance_ticks, 0, "with its counter reset, not left at the total")


func test_progress_climbs_one_tick_at_a_time() -> void:
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	var first := _player().advance_ticks
	w.step()
	assert_eq(_player().advance_ticks, first + 1)
	assert_eq(_player().advance_total_ticks, _advance_ticks_for(2),
			"the total comes from the age being advanced INTO")


func test_a_second_advance_is_refused_while_one_is_running() -> void:
	# Otherwise a double tap would restart the research, and the ring would jump
	# back to empty for no reason the player could see.
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	var started := _player().advance_ticks

	assert_false(AdvanceAgeCommand.new(1).validate(w))
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	assert_eq(_player().advance_ticks, started + 1, "the first research kept counting")


func test_advancing_is_refused_at_the_last_age() -> void:
	w.queue_command(DebugSetAgeCommand.new(1, GameDataRegistry.age_count()))
	w.step()
	assert_false(AdvanceAgeCommand.new(1).validate(w), "there is no age 5 to reach")


func test_it_advances_only_the_caller() -> void:
	w.queue_command(AdvanceAgeCommand.new(1))
	for i in range(_advance_ticks_for(2) + 1):
		w.step()
	assert_eq(_player(1).age, 2)
	assert_eq(_player(2).age, 1)
	assert_false(_player(2).is_advancing())


func test_the_progress_rides_the_snapshot_as_ints() -> void:
	# The sim carries no floats; the ring's fraction is computed in the view.
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	w.step()
	var ps: Dictionary = SnapshotSystem.build(w, 1)["player_state"][1]
	assert_eq(int(ps["advancing_to"]), 2)
	assert_true(ps["advance_ticks"] is int)
	assert_true(ps["advance_total_ticks"] is int)
	assert_eq(int(ps["advance_total_ticks"]), _advance_ticks_for(2))


func test_an_advance_in_flight_is_part_of_the_state_hash() -> void:
	# `age` alone is not enough: two worlds that started an advance at different
	# ticks would agree on every hash until it completed, then diverge with
	# nothing to say when they parted.
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)
	# The same handout `before_each` gives `w`. Stock is in the hash, so a second world
	# built without it is not the identical world this test needs it to be.
	for p in other.players:
		for kind in [&"food", &"wood", &"gold", &"stone"]:
			p.stock[kind] = 100000
	assert_eq(w.state_hash(), other.state_hash(), "identical worlds start equal")

	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	other.step()
	assert_ne(w.state_hash(), other.state_hash(),
			"one of them is researching and the hash says so")


func test_the_wire_format_round_trips() -> void:
	var decoded := Command.from_dict(AdvanceAgeCommand.new(1, 9).to_dict())
	assert_not_null(decoded, "advance_age is registered in Command.from_dict")
	assert_true(decoded is AdvanceAgeCommand)
	assert_eq(decoded.player_id, 1)


func test_an_advance_is_paid_for_out_of_stock() -> void:
	# This used to read "a free advance is still gated on cost being affordable" and
	# asserted the stock was UNCHANGED, pinning the mechanism while `cost` was empty.
	# ages.json now charges Age of Empires II's ladder (2026-08-27), so the same test
	# can assert the thing it was always standing in for.
	var cost: Dictionary = GameDataRegistry.age(2).cost
	assert_false(cost.is_empty(), "age 2 costs something")

	var before: Dictionary = _player().stock.duplicate()
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	for kind in cost:
		assert_eq(int(_player().stock.get(kind, 0)),
				int(before.get(kind, 0)) - int(cost[kind]),
				"%s was charged at the moment the research started" % kind)


func test_an_advance_nobody_can_pay_for_is_refused() -> void:
	# The other half, and the one the AI leans on: a bot whose rules say "advance"
	# simply waits until the food is there, because the command refuses it until then.
	# That is what replaced a script step timing out and giving up.
	_player().stock[&"food"] = 0
	assert_false(AdvanceAgeCommand.new(1).validate(w),
			"cannot advance on an empty larder")
	w.queue_command(AdvanceAgeCommand.new(1))
	w.step()
	assert_eq(_player().age, 1, "and nothing happened")
	assert_false(_player().is_advancing())