## PLAN.md 10.1/10.4: the 5-slot HUD reads icon/count from EventBus only, and
## double-tap-to-assign vs single-tap-to-reselect on the same icon.
extends TestCase

var hud: ControlGroupsHud


func before_each() -> void:
	hud = ControlGroupsHud.new()


func after_each() -> void:
	hud.free()


func test_the_slots_sit_close_together() -> void:
	# Project owner, 2026-08-30: "the 5 groups need to be closer together". The gap a
	# player SEES is this plus about 3 px, because the ring art is a circle that fills
	# 240 of its 252 px canvas -- so the number that matters is small, and a later
	# tidy-up raising it back to a "normal" 8 would undo the change silently.
	assert_true(ControlGroupsHud.SLOT_SEPARATION <= 4,
			"got %d" % ControlGroupsHud.SLOT_SEPARATION)
	assert_true(ControlGroupsHud.SLOT_SEPARATION > 0,
			"not zero: the count badge overflows its slot by a pixel at the bottom "
			+ "right, and closing the gap entirely tucks it under the next ring")
	assert_eq(hud.get_theme_constant("separation"), ControlGroupsHud.SLOT_SEPARATION,
			"the constant is what the container actually uses")


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


# -- the stack's skin --------------------------------------------------------

func test_set_skin_reaches_every_slot() -> void:
	# One value for the whole stack, not one per slot: SimPlayer.control_groups
	# is per-player, so a control group always holds the LOCAL player's units.
	hud.set_skin(3, 5)
	for slot in range(SimPlayer.CONTROL_GROUP_COUNT):
		var widget: ControlGroupSlot = hud.get_child(slot)
		assert_eq(widget.skin_age, 3)
		assert_eq(widget.skin_colour, 5)


func test_the_skin_survives_a_membership_change() -> void:
	# Membership changes several times a second as units die; the colour never
	# changes. Re-emitting one must not quietly reset the other.
	hud.set_skin(2, 4)
	EventBus.control_group_changed.emit(0, &"unit.militia", 7)
	var widget: ControlGroupSlot = hud.get_child(0)
	assert_eq(widget.skin_colour, 4)
	assert_eq(widget.icon_def_id, &"unit.militia")
	assert_eq(widget.count, 7)


func test_slots_start_untinted_so_an_unwired_caller_draws_what_it_used_to() -> void:
	var widget: ControlGroupSlot = hud.get_child(0)
	assert_eq(widget.skin_colour, -1)
	assert_eq(widget.skin_age, 0)