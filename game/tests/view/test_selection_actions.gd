## UI_Design.md selection-panel redesign: what a selection can DO, and what an
## expanding action offers, decided from facts alone -- no panel, no tree.
extends TestCase


func _villager_facts(id: int = 1, hp: int = 30, max_hp: int = 30) -> Dictionary:
	return {"id": id, "def_id": &"unit.villager", "owner_id": 1, "hp": hp, "max_hp": max_hp,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0}


func _town_center_facts(id: int = 5, queue_len: int = 0) -> Dictionary:
	return {"id": id, "def_id": &"building.town_center", "owner_id": 1, "hp": 2000,
			"max_hp": 2000, "alive": true, "queue_len": queue_len, "queue_fraction": 0.4}


func _ids(actions: Array[HudAction]) -> Array:
	var out: Array = []
	for a in actions:
		out.append(a.id)
	return out


func _by_id(actions: Array[HudAction], id: StringName) -> HudAction:
	for a in actions:
		if a.id == id:
			return a
	return null


# ── the action column ───────────────────────────────────────────────────────

func test_nothing_selected_offers_no_actions() -> void:
	assert_true(SelectionActions.for_selection({}).is_empty())


func test_something_not_mine_offers_no_actions() -> void:
	var actions := SelectionActions.for_selection(_villager_facts(), 1, false)
	assert_true(actions.is_empty(),
			"an enemy's unit shows its health, never orders spending this player's side")


func test_a_villager_offers_move_stop_build_and_harvest() -> void:
	var ids := _ids(SelectionActions.for_selection(_villager_facts()))
	assert_true(ids.has(&"move"))
	assert_true(ids.has(&"stop"))
	assert_true(ids.has(&"build"))
	assert_true(ids.has(&"harvest"))


func test_a_building_offers_its_trainable_units_and_destroy() -> void:
	var actions := SelectionActions.for_selection(_town_center_facts())
	var ids := _ids(actions)
	assert_true(ids.has(&"train:unit.villager"),
			"the town centre's trains[] entry becomes its own action slot")
	assert_true(ids.has(&"destroy"))


func test_a_group_offers_only_what_every_member_can_do() -> void:
	var ids := _ids(SelectionActions.for_selection(
			_villager_facts(), 3, true, [&"unit.villager", &"unit.villager", &"unit.villager"]))
	assert_eq(ids, [&"move", &"stop", &"attack", &"destroy"])
	assert_false(ids.has(&"build"),
			"build is a villager verb, not one a mixed group can be told as a whole")


func test_unimplemented_actions_are_present_but_disabled() -> void:
	# MVP has no combat, repair or research; they lay out greyed rather than
	# being omitted, so the panel does not reflow as each lands.
	var unit := SelectionActions.for_selection(_villager_facts())
	assert_false(_by_id(unit, &"attack").enabled, "no attack command exists yet")

	var building := SelectionActions.for_selection(_town_center_facts())
	assert_false(_by_id(building, &"repair").enabled, "no repair command exists yet")
	assert_false(_by_id(building, &"upgrade").enabled, "no research command exists yet")


func test_implemented_actions_are_enabled() -> void:
	var actions := SelectionActions.for_selection(_villager_facts())
	assert_true(_by_id(actions, &"move").enabled)
	assert_true(_by_id(actions, &"stop").enabled, "StopCommand is real")
	assert_true(_by_id(actions, &"destroy").enabled, "DebugDestroyCommand is real")


func test_the_action_column_never_exceeds_its_grid() -> void:
	var actions := SelectionActions.for_selection(_town_center_facts())
	assert_true(actions.size() <= SelectionActions.MAX_ACTIONS)


func test_build_expands_rather_than_ordering() -> void:
	var build := _by_id(SelectionActions.for_selection(_villager_facts()), &"build")
	assert_true(build.expands, "tapping Build lists the buildings, it does not place one")


func test_move_does_not_expand_for_a_civilian() -> void:
	# Formations hang off Move for military units only; a villager's Move is a
	# plain order with nothing to choose. Note the villager DOES carry
	# attack.damage 3 to defend itself (data/units.json), so "can fight" alone
	# would wrongly qualify it -- being a gatherer is what rules it out.
	var move := _by_id(SelectionActions.for_selection(_villager_facts()), &"move")
	assert_false(move.expands)


func test_a_unit_that_only_fights_is_the_one_that_gets_formations() -> void:
	# No military unit exists in MVP's roster (units.json is the villager
	# alone), so this pins the RULE rather than any shipped def: no gather_rate
	# plus real damage is what makes something military.
	assert_true(GameDataRegistry.unit(&"unit.villager").attack_damage > 0,
			"the villager can fight back, which is exactly why damage alone cannot decide this")
	assert_false(GameDataRegistry.unit(&"unit.villager").gather_rate.is_empty(),
			"and it gathers, which is what marks it civilian")


# ── the detail grid ─────────────────────────────────────────────────────────

func test_build_expands_into_placeable_buildings() -> void:
	var details := SelectionActions.details_for(&"build", _villager_facts())
	assert_false(details.is_empty())
	for d in details:
		assert_true(String(d.id).begins_with("place:"))


func test_move_expands_into_formations_which_are_all_disabled() -> void:
	var details := SelectionActions.details_for(&"move", _villager_facts())
	assert_eq(details.size(), SelectionActions.FORMATIONS.size())
	for d in details:
		assert_false(d.enabled, "no formation system exists in the sim yet")


func test_a_building_with_nothing_expanded_shows_its_production_queue() -> void:
	var details := SelectionActions.details_for(&"", _town_center_facts(5, 2))
	assert_eq(details.size(), 2)
	assert_eq(details[0].id, &"cancel:0")
	assert_eq(details[0].badge, "40%", "the front entry shows how far along it is")


func test_an_empty_queue_shows_no_details() -> void:
	assert_true(SelectionActions.details_for(&"", _town_center_facts(5, 0)).is_empty())


func test_a_lone_unit_has_no_default_details() -> void:
	assert_true(SelectionActions.details_for(&"", _villager_facts()).is_empty(),
			"one villager's own portrait is already shown above the actions")


func test_a_group_lists_its_members() -> void:
	var many: Array = []
	for i in range(4):
		many.append(&"unit.villager")
	var details := SelectionActions.details_for(&"", _villager_facts(), 4, many)
	assert_eq(details.size(), 4)


func test_an_oversized_group_ends_in_an_overflow_count() -> void:
	var many: Array = []
	for i in range(30):
		many.append(&"unit.villager")
	var details := SelectionActions.details_for(&"", _villager_facts(), 30, many)

	assert_eq(details.size(), SelectionActions.MAX_DETAILS)
	var last: HudAction = details[details.size() - 1]
	assert_eq(last.id, &"overflow")
	assert_eq(last.label, "+19", "11 portraits shown, so 19 of the 30 are not")


func test_a_group_that_exactly_fills_the_grid_shows_no_overflow() -> void:
	var many: Array = []
	for i in range(SelectionActions.MAX_DETAILS):
		many.append(&"unit.villager")
	var details := SelectionActions.details_for(&"", _villager_facts(),
			SelectionActions.MAX_DETAILS, many)

	assert_eq(details.size(), SelectionActions.MAX_DETAILS)
	assert_ne(details[details.size() - 1].id, &"overflow")
