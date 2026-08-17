## PLAN.md 4.11: pop_used/pop_cap, which had a field, a snapshot slot and a
## state_hash entry long before anything wrote them. PopulationSystem is what
## writes them, and the resource HUD's bottom row is what reads them.
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
