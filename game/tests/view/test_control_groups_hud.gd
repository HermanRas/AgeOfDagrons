## PLAN.md 10.1/10.4: the 5-slot HUD reads icon/count from EventBus only, and
## double-tap-to-assign vs single-tap-to-reselect on the same icon.
extends TestCase

var hud: ControlGroupsHud


func before_each() -> void:
	hud = ControlGroupsHud.new()


func after_each() -> void:
	hud.free()


func test_control_group_changed_updates_only_the_named_slot() -> void:
	EventBus.control_group_changed.emit(2, &"unit.villager", 5)
	assert_eq(hud.slot_state(2), {"icon": &"unit.villager", "count": 5})
	assert_eq(hud.slot_state(0), {"icon": &"", "count": 0}, "an untouched slot stays empty")


func test_an_emptied_group_reverts_the_slot_to_empty() -> void:
	EventBus.control_group_changed.emit(1, &"unit.villager", 3)
	EventBus.control_group_changed.emit(1, &"", 0)
	assert_eq(hud.slot_state(1), {"icon": &"", "count": 0})


func test_two_presses_within_the_window_assign_instead_of_selecting() -> void:
	var assigned: Array[int] = []
	var selected: Array[int] = []
	hud.group_assign_requested.connect(func(slot: int) -> void: assigned.append(slot))
	hud.group_selected.connect(func(slot: int) -> void: selected.append(slot))

	hud._on_slot_pressed(3)
	hud._on_slot_pressed(3)

	assert_eq(assigned, [3])
	assert_true(selected.is_empty(), "a completed double-tap must not also queue a reselect")


func test_presses_on_different_slots_never_pair_into_a_double_tap() -> void:
	var assigned: Array[int] = []
	hud.group_assign_requested.connect(func(slot: int) -> void: assigned.append(slot))

	hud._on_slot_pressed(0)
	hud._on_slot_pressed(1)

	assert_true(assigned.is_empty(), "two different slots pressed back to back is not a double-tap on either")
