## PLAN.md 4.11: pop_used/pop_cap, which had a field, a snapshot slot and a
## state_hash entry long before anything wrote them. PopulationSystem is what
## writes them, and the resource HUD's bottom row is what reads them.
##
## The second half of the file is the ENFORCEMENT, added 2026-08-17. Until then the
## counter was a caption: it read 5/10 and nothing acted on it, so a player could
## train straight past the limit -- which teaches a rule the game does not have.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	w.setup(cfg)


func _player(id: int) -> SimPlayer:
	return w.player_for(id)


func test_a_world_with_nothing_in_it_has_no_population_and_no_room() -> void:
	w.step()
	assert_eq(_player(1).pop_used, 0)
	assert_eq(_player(1).pop_cap, 0)


func test_the_cap_is_what_the_players_finished_buildings_provide() -> void:
	# A town centre is +10 and a house +5 (buildings.json), so this is 15 rather
	# than a number this test carries of its own.
	var tc: BuildingDef = GameDataRegistry.building(&"building.town_center")
	var house: BuildingDef = GameDataRegistry.building(&"building.house")
	w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()
	assert_eq(_player(1).pop_cap, tc.provides_pop + house.provides_pop)


func test_a_foundation_provides_nothing_until_it_is_finished() -> void:
	# Otherwise ten foundations nobody intends to raise would be ten houses'
	# worth of population.
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.FOUNDATION, true)
	w.step()
	assert_eq(_player(1).pop_cap, 0, "pegged out, not standing")

	house.phase = SimBuilding.Phase.COMPLETE
	w.step()
	assert_eq(_player(1).pop_cap,
			(GameDataRegistry.building(&"building.house") as BuildingDef).provides_pop)


func test_used_is_the_sum_of_pop_cost_not_a_headcount() -> void:
	# Two villagers at 1 apiece and a siege ram at 3 (units.json) is 5, not 3
	# units. A headcount would agree with the sum right up until the first unit
	# that costs more than one -- and every siege engine does.
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.villager", 1, Vector2i(11, 10))
	w.spawn_unit(&"unit.siege_ram", 1, Vector2i(12, 10))
	w.step()

	var villager: UnitDef = GameDataRegistry.unit(&"unit.villager")
	var ram: UnitDef = GameDataRegistry.unit(&"unit.siege_ram")
	assert_true(ram.pop_cost > 1, "the fixture only proves anything if it does")
	assert_eq(_player(1).pop_used, villager.pop_cost * 2 + ram.pop_cost)


func test_another_players_units_and_buildings_are_not_counted_against_yours() -> void:
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.spawn_building(&"building.house", 2, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()

	assert_eq(_player(1).pop_used, 1)
	assert_eq(_player(1).pop_cap, 0, "player 2's house does not house player 1")
	assert_eq(_player(2).pop_used, 0)
	assert_true(_player(2).pop_cap > 0)


func test_a_dead_unit_stops_occupying_a_slot_while_its_corpse_is_still_there() -> void:
	# A corpse renders for 10 s after death (4.7) and is still in `entities` for
	# every one of them. Counting it would hold a slot open for a unit the player
	# has already lost -- and the recount is the whole reason that cannot go stale.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.step()
	assert_eq(_player(1).pop_used, 1)

	v.alive = false
	w.step()
	assert_true(w.entities.has(v.id), "still there to be drawn")
	assert_eq(_player(1).pop_used, 0, "but not in the population")


func test_the_count_is_recomputed_rather_than_adjusted() -> void:
	# Written as "set it wrong and watch a tick fix it", because that is the
	# property being bought: no path a unit can leave the world by needs to
	# remember to decrement anything, so none of them can leak population.
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	_player(1).pop_used = 99
	_player(1).pop_cap = 99
	w.step()
	assert_eq(_player(1).pop_used, 1)
	assert_eq(_player(1).pop_cap, 0)


func test_population_reaches_the_snapshot_the_hud_reads() -> void:
	# The channel existed and carried 0/0 forever. This is the end-to-end check
	# that GameScene's population_changed has something real to emit.
	w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.step()

	var snap := SnapshotSystem.build(w, 1)
	var mine: Dictionary = snap["player_state"][1]
	assert_eq(int(mine["pop_used"]), 1)
	assert_eq(int(mine["pop_cap"]),
			(GameDataRegistry.building(&"building.house") as BuildingDef).provides_pop)


# ── enforcement: the cap is a rule, not a caption ───────────────────────────

## A town centre (10 pop, and the only thing on the debug map that trains) plus
## enough food to keep paying for villagers, so the only thing that can ever stop a
## train order in these tests is the population.
func _town_centre() -> SimBuilding:
	_player(1).stock = {&"food": 100000}
	return w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)


func _fill_with_villagers(count: int) -> void:
	for i in range(count):
		w.spawn_unit(&"unit.villager", 1, Vector2i(30 + i, 40))


func test_training_is_allowed_while_there_is_room() -> void:
	# The ordinary case first: the gate must not have broken training itself.
	var tc := _town_centre()
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1)


func test_training_at_the_cap_is_refused() -> void:
	# A town centre provides 10 and a villager costs 1 (data), so ten of them is a
	# full settlement. This is the hole 4.11 left open: the counter read 10/10 and
	# the eleventh villager trained anyway.
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap)
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()

	assert_eq(_player(1).pop_used, cap, "full")
	assert_true(tc.queue.is_empty(), "and refused")
	assert_eq(int(_player(1).stock[&"food"]), 100000, "nothing was charged for it")


func test_building_a_house_makes_room_again() -> void:
	# The other half of the rule being real: the refusal has to be answerable, or the
	# player is simply stuck with no way to read what to do about it.
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap)
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_true(tc.queue.is_empty())

	w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "the house paid for the eleventh villager")


func test_a_queued_unit_reserves_its_population() -> void:
	# WITHOUT THIS THE CAP IS TRIVIALLY BEATABLE: a player one slot short of full
	# could queue twenty villagers in one sitting and ProductionSystem would spawn
	# every one of them, because `pop_used` only counts units that already exist.
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap - 1)

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "the last slot is spent on this one")

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "and the next order has nowhere to put its unit")


func test_a_cancelled_order_gives_its_slot_back() -> void:
	# It follows from counting the queue rather than being separate machinery, and it
	# is what stops a mis-tap from costing a slot until the end of the match.
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap - 1)
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	w.queue_command(CancelProductionCommand.new(1, tc.id, 0))
	w.step()
	assert_true(tc.queue.is_empty(), "cancelled")

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "the slot came back with it")


func test_the_cap_counts_pop_cost_and_not_orders() -> void:
	# A siege ram is 3 (units.json), so a player with two slots left cannot have one
	# even though they could have two villagers. An order count would let it through.
	var ram: UnitDef = GameDataRegistry.unit(&"unit.siege_ram")
	assert_true(ram.pop_cost > 1, "the fixture only proves anything if it does")

	var workshop := w.spawn_building(&"building.siege_workshop", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.spawn_building(&"building.town_center", 1, Vector2i(30, 10),
			SimBuilding.Phase.COMPLETE, true)
	var p := _player(1)
	p.stock = {&"food": 100000, &"wood": 100000, &"gold": 100000, &"stone": 100000}
	p.age = 4                                  # the workshop's roster is gated by age
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap - ram.pop_cost + 1)

	w.queue_command(TrainCommand.new(1, workshop.id, &"unit.siege_ram"))
	w.step()
	assert_true(workshop.queue.is_empty(), "%d of %d used; a ram needs %d"
			% [p.pop_used, cap, ram.pop_cost])

	# And the population was genuinely the reason: a house is 5 more, which is room
	# for a ram three times over.
	w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.COMPLETE, true)
	w.queue_command(TrainCommand.new(1, workshop.id, &"unit.siege_ram"))
	w.step()
	assert_eq(workshop.queue.size(), 1)


func test_the_gate_answers_on_the_very_first_tick() -> void:
	# THE REASON `has_room_for()` DERIVES THE POPULATION rather than reading
	# `pop_used`/`pop_cap`. Commands are validated by CommandSystem, which runs FIRST
	# in the tick; PopulationSystem runs LAST. So on the first tick of a match the
	# report is still the 0/0 it was initialised with, and a gate that trusted it
	# would refuse the first villager of every game ever played.
	var tc := _town_centre()
	assert_eq(_player(1).pop_cap, 0, "nothing has counted yet")
	assert_true(PopulationSystem.has_room_for(w, 1, 1),
			"but the town centre is standing there, so there is room")

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "accepted on the first tick of the match")


func test_an_unfinished_house_does_not_open_the_cap() -> void:
	# The counter already ignores foundations; so must the gate, or a player could
	# peg out ten houses they never intend to raise and train against them.
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	_fill_with_villagers(cap)
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 30),
			SimBuilding.Phase.FOUNDATION, true)

	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_true(tc.queue.is_empty(), "a foundation houses nobody")

	house.phase = SimBuilding.Phase.COMPLETE
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "and does the moment it is finished")


func test_a_rubble_queue_reserves_nothing() -> void:
	# A destroyed building's queue never spawns anything (ProductionSystem skips it),
	# so holding population for it would charge the player for units that are not
	# coming. Two town centres: one keeps the cap up while the other falls.
	var doomed := _town_centre()
	var second := w.spawn_building(&"building.town_center", 1, Vector2i(30, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.queue_command(TrainCommand.new(1, doomed.id, &"unit.villager"))
	w.step()
	assert_eq(doomed.queue.size(), 1)
	assert_eq(PopulationSystem.queued_pop(w, 1), 1)

	doomed.alive = false
	w.step()
	assert_eq(doomed.phase, SimBuilding.Phase.DESTROYED)
	assert_false(doomed.queue.is_empty(), "the entry is still sitting in the wreck")
	assert_eq(PopulationSystem.queued_pop(w, 1), 0, "but it is not coming, so it costs nothing")

	# The surviving town centre can still fill the slot the wreck was holding.
	w.queue_command(TrainCommand.new(1, second.id, &"unit.villager"))
	w.step()
	assert_eq(second.queue.size(), 1)


func test_another_players_units_do_not_fill_your_cap() -> void:
	var tc := _town_centre()
	var cap: int = (GameDataRegistry.building(&"building.town_center") as BuildingDef).provides_pop
	for i in range(cap * 2):
		w.spawn_unit(&"unit.villager", 2, Vector2i(30 + i, 40))
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()
	assert_eq(tc.queue.size(), 1, "player 2's crowd is not living in player 1's houses")
