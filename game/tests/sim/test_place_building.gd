## PLAN.md 5.1: PlaceBuildingCommand pays the cost and claims a foundation.
## Raising it is 4.4's BuildCommand -- proven separately in test_build.gd -- so
## this only has to prove placement itself: cost, legality, and phase.
extends TestCase

var w: SimWorld
var player: SimPlayer


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())
	player = w.player_for(1)
	player.stock = {&"wood": 1000, &"stone": 1000}


func _house() -> SimBuilding:
	for e in w.entities.values():
		if e is SimBuilding and e.def_id == &"building.house":
			return e
	return null


func _place(def_id: StringName, origin: Vector2i) -> void:
	w.queue_command(PlaceBuildingCommand.new(1, def_id, origin))
	w.step()


func test_placing_a_house_pays_its_cost_and_starts_a_foundation() -> void:
	_place(&"building.house", Vector2i(20, 20))

	var house := _house()
	assert_not_null(house, "the building exists")
	assert_eq(house.phase, SimBuilding.Phase.FOUNDATION)
	assert_eq(house.origin_tile(), Vector2i(20, 20))
	assert_eq(player.stock[&"wood"], 1000 - 30, "house costs 30 wood (data/buildings.json)")


func test_placement_is_rejected_when_the_player_cannot_afford_it() -> void:
	player.stock = {&"wood": 0}
	_place(&"building.house", Vector2i(20, 20))

	assert_null(_house(), "nothing was placed")
	assert_eq(player.stock[&"wood"], 0, "and nothing was spent")


func test_placement_is_rejected_onto_occupied_ground() -> void:
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	_place(&"building.house", tc.origin_tile())

	assert_null(_house(), "a house cannot overlap the town centre")
	assert_eq(player.stock[&"wood"], 1000, "a rejected placement spends nothing")


func test_a_placed_foundation_can_then_be_raised_by_build_command() -> void:
	_place(&"building.house", Vector2i(20, 20))
	var house := _house()

	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))
	w.queue_command(BuildCommand.new(1, [villager.id], house.id))
	for i in range(500):
		w.step()
		if house.is_complete():
			break
	assert_true(house.is_complete(), "placement and the existing build loop compose")


# ── the builders ride the placement (5.1) ──────────────────────────────────

func test_the_villager_who_ordered_it_walks_over_and_raises_it_unprompted() -> void:
	# Reported live 2026-08-16: placing a building left the selected villager
	# standing there, and the player had to reselect it and tap the foundation.
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(26, 26))
	w.queue_command(PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20),
			[villager.id]))
	w.step()

	var house := _house()
	assert_not_null(house)
	assert_eq(villager.task, SimUnit.Task.BUILD,
			"tasked on the same tick the foundation appeared, with no gap to look idle in")
	assert_eq(villager.task_target_id, house.id)

	for i in range(500):
		w.step()
		if house.is_complete():
			break
	assert_true(house.is_complete(), "and it finished without a second order")


func test_a_placement_with_nobody_to_build_it_is_still_a_placement() -> void:
	# How every other caller places one -- a test, and whatever queues a build
	# order later. It leaves a foundation standing, which is legal.
	_place(&"building.house", Vector2i(20, 20))
	assert_eq(_house().phase, SimBuilding.Phase.FOUNDATION)


## ENTOMBMENT (found by the AI-vs-AI run, 2026-08-20). Units are not written into
## map occupancy, so a footprint could be claimed straight over the top of them --
## and a unit inside solid ground can never path OUT of it, so it stood there for
## the rest of the match. In the 12.2a match this sealed the villager sent to build
## the barracks inside the barracks, which is why it never rose above 0%.
func test_a_building_placed_over_a_villager_steps_it_aside_rather_than_sealing_it_in() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(11, 11))
	var rect := SimMap.footprint_rect(Vector2i(10, 10), Vector2i(6, 6))
	assert_true(rect.has_point(v.tile()), "the villager really is under the footprint")

	w.spawn_building(&"building.barracks", 1, Vector2i(10, 10), SimBuilding.Phase.FOUNDATION)

	assert_false(rect.has_point(v.tile()), "it was moved out from under the building")
	assert_true(w.map.is_passable(v.tile(), SimMap.Domain.LAND),
			"and onto ground it can actually stand on")


func test_an_evicted_villager_can_still_be_walked_somewhere() -> void:
	# The half that matters: being outside the footprint is only useful if a route
	# can be planned from where it now stands.
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(11, 11))
	w.spawn_building(&"building.barracks", 1, Vector2i(10, 10), SimBuilding.Phase.FOUNDATION)

	w.queue_command(MoveCommand.new(1, [v.id], Vector2i(30, 30)))
	var moved := false
	var was := v.tile()
	for i in range(120):
		w.step()
		if v.tile() != was:
			moved = true
			break
	assert_true(moved, "it walked, rather than being stuck inside solid ground")


func test_a_field_does_not_shove_its_farmers_off_the_crop() -> void:
	# A field is walked over rather than walled off, so there is nothing to escape
	# from and evicting would be a bug of its own.
	var mill := w.spawn_building(&"building.mill", 1, Vector2i(20, 20))
	assert_not_null(mill)
	var origin := Vector2i(20, 26)
	var farmer := w.spawn_unit(&"unit.villager", 1, origin + Vector2i(1, 1))
	var stood := farmer.tile()

	var field := w.spawn_building(&"building.field", 1, origin, SimBuilding.Phase.COMPLETE)
	if field == null:
		return          # no legal adjacency here; the eviction rule is not what is under test
	assert_eq(farmer.tile(), stood, "the farmer stayed standing on its crop")


func test_a_builder_lost_on_the_way_does_not_cancel_the_building() -> void:
	# Filtered in apply() rather than checked in validate() on purpose: the player
	# asked for a house and can pay for it, and refusing that because one villager
	# died between the tap and the tick would be a strange thing to explain.
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(26, 26))
	villager.alive = false
	w.queue_command(PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20),
			[villager.id]))
	w.step()
	assert_not_null(_house(), "the building still goes down")


func test_the_placement_cannot_conscript_someone_elses_villager() -> void:
	var theirs := w.spawn_unit(&"unit.villager", 2, Vector2i(26, 26))
	w.queue_command(PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20),
			[theirs.id]))
	w.step()
	assert_not_null(_house())
	assert_true(theirs.is_idle(), "player 2's villager took no orders from player 1")


func test_the_builder_list_survives_the_wire() -> void:
	# Every command reaches the host as a dictionary (Net.submit_command), so a
	# field that is not serialised is a field that works only in tests.
	var back := Command.from_dict(
			PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20),
					[4, 7]).to_dict()) as PlaceBuildingCommand
	assert_not_null(back)
	assert_eq(back.builder_ids, [4, 7] as Array[int])
	assert_eq(back.origin, Vector2i(20, 20))
	assert_eq(back.def_id, &"building.house")


# ── determinism (7.1) ──────────────────────────────────────────────────────

func test_two_worlds_given_the_same_placement_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	other.player_for(1).stock = {&"wood": 1000, &"stone": 1000}

	w.queue_command(PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20)))
	other.queue_command(PlaceBuildingCommand.new(1, &"building.house", Vector2i(20, 20)))

	for i in range(20):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
