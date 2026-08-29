## UI_Design.md selection-panel redesign: what a selection can DO, and what an
## expanding action offers, decided from facts alone -- no panel, no tree.
extends TestCase


func _villager_facts(id: int = 1, hp: int = 30, max_hp: int = 30) -> Dictionary:
	return {"id": id, "def_id": &"unit.villager", "owner_id": 1, "hp": hp, "max_hp": max_hp,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0}


func _militia_facts(id: int = 2) -> Dictionary:
	return {"id": id, "def_id": &"unit.militia", "owner_id": 1, "hp": 40, "max_hp": 40,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0}


## `queue` carries the def ids of what is being trained, and it is part of the
## fixture rather than an optional extra: the version of this that omitted it
## matched the shape GameView ACTUALLY produced at the time, which had a count
## and no ids -- so the queue tests passed while every queue slot in the running
## game drew the word "Queued" instead of the unit. A fixture that agrees with a
## bug is worse than no fixture.
func _town_center_facts(id: int = 5, queue_len: int = 0) -> Dictionary:
	var queue: Array[StringName] = []
	for i in range(queue_len):
		queue.append(&"unit.villager")
	return {"id": id, "def_id": &"building.town_center", "owner_id": 1, "hp": 2000,
			"max_hp": 2000, "alive": true, "queue_len": queue_len, "queue_fraction": 0.4,
			"queue": queue}


## A unit of the local player's, for the stance and ability rows (4.12, 4.10). `stance`
## and `ability_cooldown` are part of the fixture rather than optional extras, for the
## reason `_town_center_facts` records about `queue`: `GameView._facts` really does carry
## both on every unit, and a fixture that omitted them would test the defaults instead of
## the wire.
func _unit_facts(def_id: StringName, stance: int = SimUnit.Stance.DEFENSIVE,
		ability_cooldown: int = 0, id: int = 3) -> Dictionary:
	return {"id": id, "def_id": def_id, "owner_id": 1, "hp": 30, "max_hp": 30,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0,
			"stance": stance, "ability_cooldown": ability_cooldown}


func _building_facts(def_id: StringName, id: int = 6) -> Dictionary:
	return {"id": id, "def_id": def_id, "owner_id": 1, "hp": 1000, "max_hp": 1000,
			"alive": true, "queue_len": 0, "queue_fraction": 0.0}


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


# ── stance and ability (4.12, 4.10) ─────────────────────────────────────────

func test_a_fighter_offers_a_stance_and_a_trade_cart_does_not() -> void:
	# The same `attack_damage > 0` test the Attack verb uses, so the two can never
	# disagree about who is worth offering a fight to. A stance on something that cannot
	# land a blow is a control that changes nothing -- `StanceSystem` refuses to acquire
	# for it, so the order would be retired on the tick it was given.
	assert_true(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.militia"))).has(&"stance"))
	assert_true(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.villager"))).has(&"stance"),
			"the villager carries damage 3 and hiding indoors is not always an option")
	assert_false(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.trade_cart"))).has(&"stance"))
	assert_false(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.monk"))).has(&"stance"),
			"a monk cannot fight, so a stance would be a control that does nothing")


func test_the_stance_row_says_which_one_is_set_without_being_opened() -> void:
	var row := SelectionActions.for_selection(_unit_facts(&"unit.militia",
			SimUnit.Stance.STAND_GROUND))
	assert_eq(_by_id(row, &"stance").badge, "Hold",
			"abbreviated because a badge is corner text on a 72 px tile")


func test_stance_expands_into_the_four_with_the_live_one_ringed() -> void:
	var facts := _unit_facts(&"unit.militia", SimUnit.Stance.AGGRESSIVE)
	var details := SelectionActions.details_for(&"stance", facts)
	assert_eq(details.size(), 4)
	var ringed := 0
	for d in details:
		if d.selected:
			ringed += 1
			assert_eq(d.id, &"stance:%d" % SimUnit.Stance.AGGRESSIVE)
		assert_true(d.enabled,
				"including the current one -- `enabled = false` already means two other "
				+ "things, both of which draw greyed")
	assert_eq(ringed, 1, "read off the SNAPSHOT, so it says what the unit is doing")


func test_the_stance_ids_carry_the_enum_value_and_not_a_name() -> void:
	# The value goes on the wire as an int and `SetStanceCommand` validates the range, so
	# the panel must not be the place that decides what 2 means.
	var details := SelectionActions.details_for(&"stance", _unit_facts(&"unit.militia"))
	assert_eq(details[0].id, &"stance:0")
	assert_eq(details[3].id, &"stance:3")


func test_only_the_monk_and_the_dragon_offer_an_ability() -> void:
	assert_true(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.monk"))).has(&"ability"))
	assert_true(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.dragon"))).has(&"ability"))
	assert_false(_ids(SelectionActions.for_selection(
			_unit_facts(&"unit.villager"))).has(&"ability"))


func test_the_ability_slot_is_labelled_with_the_ability_and_not_the_word_ability() -> void:
	# The reason a train button says "Archer": the player is being asked to spend a
	# cooldown and needs to know on what.
	var row := SelectionActions.for_selection(_unit_facts(&"unit.monk"))
	assert_eq(_by_id(row, &"ability").label, "Heal")
	var dragon := SelectionActions.for_selection(_unit_facts(&"unit.dragon"))
	assert_eq(_by_id(dragon, &"ability").label, "Fire Breath")


func test_the_ability_slot_greys_while_it_is_cooling_and_counts_down_in_seconds() -> void:
	# IDEA.md 4.10's own wording: "greyed out and unclickable".
	var ready := SelectionActions.for_selection(_unit_facts(&"unit.dragon"))
	assert_true(_by_id(ready, &"ability").enabled)

	var cooling := SelectionActions.for_selection(
			_unit_facts(&"unit.dragon", SimUnit.Stance.DEFENSIVE, 91))
	var slot := _by_id(cooling, &"ability")
	assert_false(slot.enabled)
	assert_eq(slot.badge, "10s",
			"ticks are a sim unit and 91 of them means nothing to a player; it rounds "
			+ "UP so a cooldown with any time left never reads 0")


func test_a_units_row_never_outgrows_its_eight_slots() -> void:
	# Two verbs were added on 2026-08-29 and `_capped` slices silently, so this sweeps
	# the whole roster rather than checking whichever unit has the most today.
	for id in GameDataRegistry.unit_ids():
		var row := SelectionActions.for_selection(_unit_facts(id))
		assert_true(row.size() <= SelectionActions.MAX_ACTIONS,
				"%s asks for %d of %d slots" % [id, row.size(), SelectionActions.MAX_ACTIONS])


func test_a_building_offers_its_trainable_units_and_destroy() -> void:
	var actions := SelectionActions.for_selection(_town_center_facts())
	var ids := _ids(actions)
	assert_true(ids.has(&"train:unit.villager"),
			"the town centre's trains[] entry becomes its own action slot")
	assert_true(ids.has(&"destroy"))


func test_a_group_offers_only_what_every_member_can_do() -> void:
	var ids := _ids(SelectionActions.for_selection(
			_villager_facts(), 3, true, [&"unit.villager", &"unit.villager", &"unit.villager"]))
	# STANCE JOINED THE GROUP ROW ON 2026-08-29 (4.12), and the group is where it is
	# actually used -- nobody sets a stance one soldier at a time, which is why
	# `SetStanceCommand` carries many ids. Members that cannot fight ignore it, exactly
	# as a trade cart in the group ignores Attack.
	assert_eq(ids, [&"move", &"stop", &"attack", &"stance", &"destroy"])
	assert_false(ids.has(&"build"),
			"build is a villager verb, not one a mixed group can be told as a whole")


func test_unimplemented_actions_are_present_but_disabled() -> void:
	# Repair and research still have no command; they lay out greyed rather than
	# being omitted, so the panel does not reflow as each lands. Attack used to be
	# on this list and came off it at 4.13.
	var building := SelectionActions.for_selection(_town_center_facts())
	assert_false(_by_id(building, &"repair").enabled, "no repair command exists yet")
	assert_false(_by_id(building, &"upgrade").enabled, "no research command exists yet")


func test_implemented_actions_are_enabled() -> void:
	var actions := SelectionActions.for_selection(_villager_facts())
	assert_true(_by_id(actions, &"move").enabled)
	assert_true(_by_id(actions, &"stop").enabled, "StopCommand is real")
	assert_true(_by_id(actions, &"destroy").enabled, "DebugDestroyCommand is real")


# ── attack (4.13) ───────────────────────────────────────────────────────────

func test_attack_is_enabled_for_anything_that_carries_damage() -> void:
	# Including the villager: damage 3 to defend herself (units.json), and a
	# peasant who may not be told to fight back would be a stranger rule than one
	# who may. What gates the button is damage, not being military -- the
	# "military" distinction decides FORMATIONS, and only that.
	assert_true(_by_id(SelectionActions.for_selection(_villager_facts()), &"attack").enabled)
	assert_true(_by_id(SelectionActions.for_selection(_militia_facts()), &"attack").enabled)


func test_attack_stays_disabled_for_a_unit_with_no_attack_at_all() -> void:
	var cart := _villager_facts().duplicate()
	cart["def_id"] = &"unit.trade_cart"
	assert_eq(GameDataRegistry.unit(&"unit.trade_cart").attack_damage, 0, "the premise")
	assert_false(_by_id(SelectionActions.for_selection(cart), &"attack").enabled)


func test_a_mixed_group_may_still_be_told_to_attack() -> void:
	# AttackCommand accepts a mixed selection and tasks whoever can fight, so one
	# trade cart in a group must not disarm the whole group.
	var group := SelectionActions.for_selection(_villager_facts(), 3, true,
			[&"unit.villager", &"unit.trade_cart", &"unit.militia"])
	assert_true(_by_id(group, &"attack").enabled)


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
	# The rule is "fights INSTEAD of working", not "can fight": the villager
	# carries attack.damage to defend herself, so damage alone would wrongly
	# qualify her. This used to pin the rule against the villager alone because
	# the roster had no military unit; it now checks both sides of it against
	# real shipped defs.
	assert_true(GameDataRegistry.unit(&"unit.villager").attack_damage > 0,
			"the villager can fight back, which is exactly why damage alone cannot decide this")
	assert_false(GameDataRegistry.unit(&"unit.villager").gather_rate.is_empty(),
			"and it gathers, which is what marks it civilian")

	var militia := _by_id(SelectionActions.for_selection(_militia_facts()), &"move")
	assert_true(militia.expands, "the militia neither gathers nor builds, so Move offers formations")
	var villager := _by_id(SelectionActions.for_selection(_villager_facts()), &"move")
	assert_false(villager.expands)


# ── the detail grid ─────────────────────────────────────────────────────────

func test_build_expands_into_placeable_buildings() -> void:
	var details := SelectionActions.details_for(&"build", _villager_facts())
	assert_false(details.is_empty())
	for d in details:
		assert_true(String(d.id).begins_with("place:"))


func test_move_expands_into_formations_and_they_are_live() -> void:
	# Disabled placeholders from 4.3 until 2026-08-29, when `Formation` made them real.
	var details := SelectionActions.details_for(&"move", _villager_facts())
	assert_eq(details.size(), SelectionActions.FORMATIONS.size())
	for d in details:
		assert_true(d.enabled, "4.14 landed")
		assert_false(d.selected, "and none is chosen until the player picks one")


func test_the_chosen_formation_is_ringed_rather_than_greyed() -> void:
	# `enabled = false` already means "not built yet" and "nothing to act on", both of
	# which draw greyed -- so the current choice needed a third state or it would be the
	# one slot that looks broken. It also stays PRESSABLE, because pressing it again is
	# the only way back to a plain move order.
	var details := SelectionActions.details_for(&"move", _villager_facts(), 1, [], 1,
			Formation.VEE)
	var ringed := 0
	for d in details:
		if d.selected:
			ringed += 1
			assert_eq(d.id, &"formation:vee")
			assert_true(d.enabled, "pressing it again turns the formation off")
	assert_eq(ringed, 1)


func test_the_panel_and_the_sim_agree_on_which_formations_exist() -> void:
	# The same object, not a copy: a menu offering a shape the server refuses is a button
	# that silently does nothing, and `MoveCommand.validate` refuses an unknown one.
	assert_eq(SelectionActions.FORMATIONS, Formation.SHAPES)


func test_a_building_with_nothing_expanded_shows_its_production_queue() -> void:
	var details := SelectionActions.details_for(&"", _town_center_facts(5, 2))
	assert_eq(details.size(), 2)
	assert_eq(details[0].id, &"cancel:0")
	assert_eq(details[0].badge, "40%", "the front entry shows how far along it is")


func test_each_queue_slot_names_the_unit_so_it_can_draw_its_portrait() -> void:
	# ActionSlot crops the portrait from `payload`, so an empty payload is a slot
	# that falls all the way back to its label -- which is what "Queued" was.
	var details := SelectionActions.details_for(&"", _town_center_facts(5, 2))
	for d in details:
		assert_eq(d.payload, &"unit.villager", "the slot knows WHAT is queued")
		assert_eq(d.label, "Villager", "and labels it by name, not 'Queued'")


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


# -- age gating (Task C) -----------------------------------------------------

func test_a_building_lists_only_the_units_its_owner_has_the_age_for() -> void:
	# An archery range trains archers from age 2 and crossbowmen from age 3
	# (Age & Unit Planning.md). Both live in one `trains` list; the gate is the
	# unit's own age_required, read against the OWNER's age.
	var age2 := _ids(SelectionActions.for_selection(
			_building_facts(&"building.archery_range"), 1, true, [], 2))
	assert_true(age2.has(&"train:unit.archer"), "archers unlock with the range itself")
	assert_false(age2.has(&"train:unit.crossbowman"),
			"a crossbowman in age 2 would be a promise about a future age")

	var age3 := _ids(SelectionActions.for_selection(
			_building_facts(&"building.archery_range"), 1, true, [], 3))
	assert_true(age3.has(&"train:unit.archer"))
	assert_true(age3.has(&"train:unit.crossbowman"), "and it arrives in age 3")


func test_the_castle_fills_in_across_two_ages() -> void:
	# The castle is the widest gate in the roster: knights in age 3, then elite
	# swordsmen, the trebuchet and the dragon in age 4.
	var age3 := _ids(SelectionActions.for_selection(
			_building_facts(&"building.castle"), 1, true, [], 3))
	assert_true(age3.has(&"train:unit.knight"))
	assert_false(age3.has(&"train:unit.elite_swordsman"))
	assert_false(age3.has(&"train:unit.dragon"))

	var age4 := _ids(SelectionActions.for_selection(
			_building_facts(&"building.castle"), 1, true, [], 4))
	for unit_id in [&"train:unit.knight", &"train:unit.elite_swordsman",
			&"train:unit.trebuchet", &"train:unit.dragon"]:
		assert_true(age4.has(unit_id), "age 4 castle offers %s" % unit_id)


func test_a_train_row_never_overflows_its_grid_at_any_age() -> void:
	# The reason units are OMITTED above their age rather than shown disabled:
	# an age-4 castle trains four things and still has to fit `upgrade`, `repair`
	# and `destroy` into the same 8 slots.
	for building_id in GameDataRegistry.building_ids():
		for age in [1, 2, 3, 4]:
			var actions := SelectionActions.for_selection(
					_building_facts(building_id), 1, true, [], age)
			assert_true(actions.size() <= SelectionActions.MAX_ACTIONS,
					"%s in age %d fits its action column" % [building_id, age])


func test_the_build_menu_gates_on_age() -> void:
	var age1 := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 1)
	var ids1: Array = []
	for d in age1:
		ids1.append(StringName(String(d.id).trim_prefix("place:")))
	assert_true(ids1.has(&"building.town_center"))
	assert_true(ids1.has(&"building.house"))
	assert_false(ids1.has(&"building.dock"), "the dock is an age-2 building")
	assert_false(ids1.has(&"building.wonder"), "and the wonder an age-4 one")

	var age4 := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var ids4: Array = []
	for d in age4:
		ids4.append(StringName(String(d.id).trim_prefix("place:")))
	assert_true(ids4.has(&"building.wonder"))


func test_the_build_menu_order_is_stable_rather_than_interning_order() -> void:
	# building_ids() sorts an Array[StringName], which orders by StringName
	# IDENTITY, not by string -- so taking its order straight through would move
	# the buttons around between runs. The menu re-sorts by (age, name).
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var previous_age := 0
	for d in details:
		var bd: BuildingDef = GameDataRegistry.building(StringName(String(d.id).trim_prefix("place:")))
		assert_true(bd.age_required >= previous_age,
				"buildings arrive in age order, so age 1's never move once learned")
		previous_age = bd.age_required


func test_the_age_defaults_to_one_so_a_caller_without_an_age_still_gets_a_menu() -> void:
	# Every `age` parameter added for Task C is optional. A caller that has not
	# been updated must get the age-1 menu, never an empty one.
	assert_false(SelectionActions.for_selection(_town_center_facts()).is_empty())
	assert_false(SelectionActions.details_for(&"build", _villager_facts()).is_empty())

# -- paging the detail grid --------------------------------------------------

func _fake_details(n: int) -> Array[HudAction]:
	var out: Array[HudAction] = []
	for i in range(n):
		out.append(HudAction.new(&"place:b%d" % i, "B%d" % i))
	return out


func _ids_of(actions: Array[HudAction]) -> Array:
	var out: Array = []
	for a in actions:
		out.append(a.id)
	return out


func test_a_list_that_fits_needs_no_arrows() -> void:
	var page := SelectionActions.page_of(_fake_details(SelectionActions.MAX_DETAILS), 0)
	assert_eq(page.size(), SelectionActions.MAX_DETAILS, "all 12 are slots, none an arrow")
	assert_false(_ids_of(page).has(SelectionActions.PAGE_NEXT))
	assert_false(_ids_of(page).has(SelectionActions.PAGE_PREV))
	assert_eq(SelectionActions.page_count(SelectionActions.MAX_DETAILS), 1)


func test_one_item_too_many_pages_with_the_arrow_in_the_last_slot() -> void:
	# The project owner's shape: last icon on page 1 is ">".
	var details := _fake_details(SelectionActions.MAX_DETAILS + 1)
	assert_eq(SelectionActions.page_count(details.size()), 2)

	var first := SelectionActions.page_of(details, 0)
	assert_eq(first.size(), SelectionActions.MAX_DETAILS, "the page is still full")
	assert_eq(first[first.size() - 1].id, SelectionActions.PAGE_NEXT,
			"the LAST slot is >")
	assert_ne(first[0].id, SelectionActions.PAGE_PREV, "page 1 has no < ")


func test_the_second_page_leads_with_the_back_arrow() -> void:
	# And: first icon on page 2 is "<".
	var details := _fake_details(SelectionActions.MAX_DETAILS + 1)
	var second := SelectionActions.page_of(details, 1)
	assert_eq(second[0].id, SelectionActions.PAGE_PREV, "the FIRST slot is <")
	# 13 items, and page 1 spent a slot on ">" -- so it showed 11 and TWO are
	# left, not one. The arrow costs a slot on the page it appears on.
	assert_eq(second.size(), 3, "< plus the two items that did not fit")
	assert_false(_ids_of(second).has(SelectionActions.PAGE_NEXT),
			"nothing follows, so no >")


func test_a_middle_page_carries_both_arrows() -> void:
	# The third part of the spec: if more is needed, the last icon on page 2 is
	# also ">". 25 items forces exactly that.
	var details := _fake_details(25)
	assert_eq(SelectionActions.page_count(25), 3)

	var middle := SelectionActions.page_of(details, 1)
	assert_eq(middle[0].id, SelectionActions.PAGE_PREV)
	assert_eq(middle[middle.size() - 1].id, SelectionActions.PAGE_NEXT)
	assert_eq(middle.size(), SelectionActions.MAX_DETAILS,
			"both arrows plus 10 items exactly fills the grid")


func test_no_page_ever_overflows_the_grid_and_none_is_empty() -> void:
	# The property the whole scheme exists for, swept rather than spot-checked:
	# an off-by-one in _page_offsets would show up as a 13-slot page or a page
	# with nothing but arrows on it.
	for total in range(1, 60):
		var details := _fake_details(total)
		for page in range(SelectionActions.page_count(total)):
			var slots := SelectionActions.page_of(details, page)
			assert_true(slots.size() <= SelectionActions.MAX_DETAILS,
					"%d items, page %d fits the grid" % [total, page])
			var content := 0
			for a in slots:
				if a.id != SelectionActions.PAGE_NEXT and a.id != SelectionActions.PAGE_PREV:
					content += 1
			assert_true(content > 0, "%d items, page %d shows something" % [total, page])


func test_every_item_appears_exactly_once_across_the_pages() -> void:
	# Paging that loses an item is the failure a cap already had; paging that
	# repeats one is worse, because it looks like it worked.
	for total in [1, 12, 13, 19, 23, 24, 25, 47]:
		var details := _fake_details(total)
		var seen: Array = []
		for page in range(SelectionActions.page_count(total)):
			for a in SelectionActions.page_of(details, page):
				if a.id == SelectionActions.PAGE_NEXT or a.id == SelectionActions.PAGE_PREV:
					continue
				assert_false(seen.has(a.id), "%s appears once across %d items" % [a.id, total])
				seen.append(a.id)
		assert_eq(seen.size(), total, "all %d items are reachable" % total)


func test_a_page_number_past_the_end_clamps_to_the_last_page() -> void:
	var details := _fake_details(13)
	assert_eq(_ids_of(SelectionActions.page_of(details, 99)),
			_ids_of(SelectionActions.page_of(details, 1)),
			"a stale page number lands on the last real page, not an empty grid")


## The buildings the MENU is supposed to offer at `age` -- every def gated by age and
## not flagged `buildable: false`. Derived from the data rather than listed, so adding
## a building does not need this test edited; the point is the FILTER, not the count.
func _offerable(age: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd != null and bd.buildable and bd.age_required <= age:
			out.append(id)
	return out


func test_the_whole_build_roster_is_reachable_by_paging() -> void:
	# Against the real shipped data, not fakes: a roster that does not fit a 12-slot
	# grid is the case this was built for.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	assert_eq(details.size(), _offerable(4).size(),
			"details_for hands back the WHOLE offerable list -- capping it is what paging replaced")

	var reachable: Array = []
	for page in range(SelectionActions.page_count(details.size())):
		for a in SelectionActions.page_of(details, page):
			if a.payload != null and a.payload != &"":
				reachable.append(a.payload)

	for building_id in _offerable(4):
		assert_true(reachable.has(building_id),
				"%s can be reached by an age-4 villager" % building_id)


func test_the_menu_does_not_offer_the_wall_segments_the_drag_chooses() -> void:
	# PLAN.md 5.8's `buildable: false`. A wall tier is four defs and only ONE of them
	# is a player's to pick: the short segment IS the tier, since it carries
	# `wall_lengths` and the drag reads that to decide what to lay. Without the filter
	# the grid would carry all twelve pieces and eleven of them would each place one
	# fixed-length block -- which is exactly the outcome buildings.json refused to ship
	# walls at all rather than allow.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var offered: Array = []
	for a in details:
		if a.payload != null:
			offered.append(a.payload)

	for hidden in [&"building.wall_wood_medium", &"building.wall_wood_long",
			&"building.wall_stone_medium", &"building.wall_stone_long",
			&"building.wall_reinforced_medium", &"building.wall_reinforced_long"]:
		assert_false(offered.has(hidden), "%s is placed by the drag, not by the menu" % hidden)

	# THE GATES LEFT THE MENU on 2026-08-22, and that is a fix rather than a
	# restriction. A gate is 9x2 and `PlaceBuildingCommand` carries no facing and never
	# transposes a footprint, so a tap-placed gate could only ever lie east-west -- a
	# north-south wall could not have one at all, and there was no rotate control to
	# fix it with. `UpgradeBuildingCommand` replaces the whole idea: a gate is now made
	# by upgrading a long segment, which already knows its axis.
	for hidden_gate in [&"building.wall_wood_gate", &"building.wall_stone_gate",
			&"building.wall_reinforced_gate"]:
		assert_false(offered.has(hidden_gate),
				"%s is made by upgrading a wall, not from the menu" % hidden_gate)

	for shown in [&"building.wall_wood_short", &"building.wall_stone_short",
			&"building.wall_reinforced_short"]:
		assert_true(offered.has(shown), "%s is a menu entry" % shown)


func test_a_wall_tier_is_one_menu_entry() -> void:
	# The project owner's shape (2026-08-21): all three tiers stay available at age 4,
	# so a player there has three wall entries -- wood, stone and reinforced -- rather
	# than one wall that re-skinned the other two away. Three and not six, because the
	# gates came off this list when they became an upgrade (2026-08-22).
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var walls := 0
	for a in details:
		if a.payload != null and String(a.payload).begins_with("building.wall_"):
			walls += 1
	assert_eq(walls, 3, "one entry per tier, no gates")


## A finished wall segment, which is what the upgrade button needs to see. `phase`
## matters here where it does not for `_building_facts`: only a COMPLETE building
## offers the upgrade, the same rule the gate's open/close button already follows.
func _wall_facts(def_id: StringName,
		phase: int = SimBuilding.Phase.COMPLETE) -> Dictionary:
	var f := _building_facts(def_id)
	f["phase"] = phase
	return f


func test_a_finished_long_wall_offers_its_tier_s_gate() -> void:
	# The `upgrade` slot has been a disabled placeholder on every building since the
	# panel was written. This is the first thing that makes it a real verb.
	var action := _by_id(SelectionActions.for_selection(
			_wall_facts(&"building.wall_wood_long"), 1, true, [], 2), &"upgrade")
	assert_true(action.enabled, "a long wall can become a gate")
	assert_eq(action.payload, &"building.wall_wood_gate", "and it names which one")
	# LABELLED WITH THE TARGET, not "Upgrade": the player is being asked to spend, and
	# "Upgrade" on a wall says nothing about what they get. Same rule as a train button.
	assert_eq(action.label, GameDataRegistry.building(&"building.wall_wood_gate").name)
	# And NO icon, so `ActionSlot` falls through to cropping the gate's own sprite
	# rather than drawing the tech-tree glyph `ICONS` maps upgrade to.
	assert_eq(action.icon, "", "the gate's portrait reads better than a stand-in glyph")


func test_a_wall_still_being_built_does_not_offer_the_upgrade() -> void:
	var action := _by_id(SelectionActions.for_selection(
			_wall_facts(&"building.wall_wood_long", SimBuilding.Phase.FOUNDATION),
			1, true, [], 2), &"upgrade")
	assert_false(action.enabled, "there is no finished wall to convert yet")


func test_the_short_and_medium_segments_offer_no_upgrade() -> void:
	# A gate is 9x2 and the conversion keeps the ground the building already holds,
	# so only the long piece has room for one.
	for too_short in [&"building.wall_wood_short", &"building.wall_wood_medium"]:
		var action := _by_id(SelectionActions.for_selection(
				_wall_facts(too_short), 1, true, [], 2), &"upgrade")
		assert_false(action.enabled, "%s is too short to hold a gate" % too_short)


func test_a_gate_does_not_offer_to_become_another_gate() -> void:
	var action := _by_id(SelectionActions.for_selection(
			_wall_facts(&"building.wall_wood_gate"), 1, true, [], 2), &"upgrade")
	assert_false(action.enabled, "the chain ends at the gate")


func test_the_upgrade_button_is_age_gated_on_the_gate() -> void:
	# Held as well as on the server (`UpgradeBuildingCommand.validate`), so a player
	# is not shown a live button for something the host would refuse.
	var wall := _wall_facts(&"building.wall_stone_long")
	assert_false(_by_id(SelectionActions.for_selection(wall, 1, true, [], 2),
			&"upgrade").enabled, "a stone gate is age 3")
	assert_true(_by_id(SelectionActions.for_selection(wall, 1, true, [], 3),
			&"upgrade").enabled)


func test_every_building_that_declares_an_upgrade_can_actually_take_it() -> void:
	# Derived from the data rather than listed: the target must exist and must have
	# the SAME footprint, because `SimWorld.convert_building` keeps the ground the
	# building already holds. A target that wanted more of it would silently occupy
	# tiles nobody checked were free, and that is a relationship between two separate
	# JSON entries with nothing else pinning it.
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd == null or bd.upgrades_to == &"":
			continue
		var to: BuildingDef = GameDataRegistry.building(bd.upgrades_to)
		assert_not_null(to, "%s upgrades to %s, which exists" % [id, bd.upgrades_to])
		assert_eq(to.footprint, bd.footprint,
				"%s and %s claim the same ground" % [id, bd.upgrades_to])
		assert_true(to.upgrades_to == &"", "%s does not upgrade onward" % bd.upgrades_to)
		# The upgrade must cost SOMETHING, or the tier's cheaper piece is strictly
		# worse than the thing it becomes and nobody would ever build one.
		assert_false(UpgradeBuildingCommand.cost_delta(bd, to).is_empty(),
				"%s charges for the upgrade" % id)


func test_walls_are_age_gated_like_everything_else() -> void:
	# Wood at age 2, stone at 3, reinforced at 4 -- the roster's ladder. Age 1 offers
	# no wall at all, which is also why a new player still sees no paging arrow.
	var by_age := {}
	for age in [1, 2, 3, 4]:
		var offered: Array = []
		for a in SelectionActions.details_for(&"build", _villager_facts(), 1, [], age):
			if a.payload != null and String(a.payload).begins_with("building.wall_"):
				offered.append(a.payload)
		by_age[age] = offered
	assert_true((by_age[1] as Array).is_empty(), "no walls in age 1")
	assert_eq((by_age[2] as Array).size(), 1, "wood at age 2")
	assert_eq((by_age[3] as Array).size(), 2, "stone joins at age 3")
	assert_eq((by_age[4] as Array).size(), 3, "reinforced joins at age 4")


func test_the_age_four_build_list_pages() -> void:
	# Not pinned to a number: the roster grows, and what matters is that paging
	# covers whatever it has grown to. `page_count` is arithmetic over the list size,
	# so this asserts the two agree rather than restating one of them.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	assert_true(details.size() > SelectionActions.MAX_DETAILS,
			"the age-4 roster does not fit one grid, which is why paging exists")
	assert_true(SelectionActions.page_count(details.size()) >= 2)


func test_age_one_needs_no_paging_at_all() -> void:
	# Five buildings. A new player never sees an arrow, which is the reason the
	# sort puts age-1 buildings first.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 1)
	assert_eq(SelectionActions.page_count(details.size()), 1)
	assert_eq(_ids_of(SelectionActions.page_of(details, 0)).size(), details.size())


func test_page_one_holds_the_buildings_a_player_has_had_longest() -> void:
	# What the (age, name) sort buys once paging exists: advancing to age 4 must
	# not push the town centre onto page 2.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var first_page: Array = []
	for a in SelectionActions.page_of(details, 0):
		if a.payload != null:
			first_page.append(a.payload)
	for building_id in [&"building.town_center", &"building.house", &"building.mill",
			&"building.lumber_camp", &"building.mining_camp"]:
		assert_true(first_page.has(building_id),
				"%s is an age-1 building and stays on page 1" % building_id)


# ── research (PLAN.md 9.3) ──────────────────────────────────────────────────

## A FINISHED building of the local player's. `phase` is the part that matters and is
## the part the older fixtures above deliberately leave out -- Gate, Garrison, Upgrade
## and now Research all refuse anything that is not COMPLETE.
func _finished(def_id: StringName, queue: Array = [], id: int = 7) -> Dictionary:
	return {"id": id, "def_id": def_id, "owner_id": 1, "hp": 1000, "max_hp": 1000,
			"alive": true, "phase": SimBuilding.Phase.COMPLETE,
			"queue_len": queue.size(), "queue_fraction": 0.0, "queue": queue}


func _held(ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for id in ids:
		out[id] = true
	return out


func test_only_a_building_that_teaches_something_offers_research() -> void:
	# Twenty-four of the thirty-one get no slot at all rather than a disabled one --
	# a house does not have research the way a house does have repair.
	var smith := SelectionActions.for_selection(_finished(&"building.blacksmith"), 1, true, [], 2)
	assert_true(_ids(smith).has(&"research"))

	var house := SelectionActions.for_selection(_finished(&"building.house"), 1, true, [], 4)
	assert_false(_ids(house).has(&"research"),
			"and it is absent, not greyed -- absent is what keeps every other row unchanged")


func test_the_castle_still_fits_its_eight_slots() -> void:
	# The trap this file's own source warns about: `_capped` slices at MAX_ACTIONS and
	# the castle already emits eight. It has no techs precisely so it still emits eight.
	var castle := _finished(&"building.castle")
	var actions := SelectionActions.for_selection(castle, 1, true, [], 4)
	assert_false(_ids(actions).has(&"research"))
	assert_true(actions.size() <= SelectionActions.MAX_ACTIONS)


func test_a_foundation_teaches_nothing_yet() -> void:
	var raw := _finished(&"building.blacksmith")
	raw["phase"] = SimBuilding.Phase.FOUNDATION
	assert_false(_ids(SelectionActions.for_selection(raw, 1, true, [], 2)).has(&"research"))


func test_the_research_badge_counts_what_is_bought_against_what_is_offered() -> void:
	var smith := _finished(&"building.blacksmith")
	var fresh := _by_id(SelectionActions.for_selection(smith, 1, true, [], 2), &"research")
	assert_eq(fresh.badge, "0/4", "four blacksmith technologies unlock in age 2")

	var some := _by_id(SelectionActions.for_selection(smith, 1, true, [], 2,
			_held([&"tech.forging"])), &"research")
	assert_eq(some.badge, "1/4")


func test_the_research_row_expands_rather_than_ordering_anything() -> void:
	# One slot for twelve technologies. It has to expand or the blacksmith would want
	# twelve of the action column's eight.
	var a := _by_id(SelectionActions.for_selection(
			_finished(&"building.blacksmith"), 1, true, [], 4), &"research")
	assert_true(a.expands)
	assert_true(a.enabled)


func test_the_detail_grid_lists_only_the_techs_this_age_has_reached() -> void:
	var smith := _finished(&"building.blacksmith")
	var age2 := SelectionActions.details_for(&"research", smith, 1, [], 2)
	var age4 := SelectionActions.details_for(&"research", smith, 1, [], 4)
	assert_eq(age2.size(), 4, "one tier")
	assert_eq(age4.size(), 12, "all three")
	assert_false(_ids(age2).has(&"research:tech.blast_furnace"),
			"an age-4 tech is omitted, not greyed -- the tech tree is where promises live")


func test_a_researched_tech_is_ringed_and_not_pressable() -> void:
	var details := SelectionActions.details_for(&"research", _finished(&"building.blacksmith"),
			1, [], 2, &"", _held([&"tech.forging"]))
	var forging := _by_id(details, &"research:tech.forging")
	assert_true(forging.selected, "ringed, which is the third state `enabled` could not say")
	assert_false(forging.enabled, "there is nothing left to press")


func test_a_tech_whose_prerequisite_is_missing_names_it() -> void:
	# Shown disabled rather than omitted, unlike the age gate: "research Forging first"
	# is something the player can act on now, on this building, in this menu.
	var details := SelectionActions.details_for(&"research", _finished(&"building.blacksmith"),
			1, [], 3)
	var iron := _by_id(details, &"research:tech.iron_casting")
	assert_not_null(iron, "it is listed")
	assert_false(iron.enabled)
	assert_eq(iron.badge, "Forging")

	var ready := _by_id(SelectionActions.details_for(&"research",
			_finished(&"building.blacksmith"), 1, [], 3, &"", _held([&"tech.forging"])),
			&"research:tech.iron_casting")
	assert_true(ready.enabled, "and it lights up the moment the prerequisite lands")
	assert_false(ready.cost.is_empty(), "priced, like a train slot")


func test_a_tech_already_in_the_queue_is_not_offered_again() -> void:
	var smith := _finished(&"building.blacksmith", ["tech.forging"])
	var forging := _by_id(SelectionActions.details_for(&"research", smith, 1, [], 2),
			&"research:tech.forging")
	assert_false(forging.enabled)
	assert_eq(forging.badge, "...")


func test_a_queued_research_draws_its_own_name_rather_than_the_word_Queued() -> void:
	# 5.4's defect, arriving through the other door: the queue carries def ids and
	# `GameDataRegistry.unit()` answers null for a tech id.
	var smith := _finished(&"building.blacksmith", ["tech.forging"])
	var queue := SelectionActions.details_for(&"", smith, 1, [], 2)
	assert_eq(queue.size(), 1)
	assert_eq(queue[0].label, "Forging")
	assert_eq(queue[0].id, &"cancel:0", "and tapping it still cancels")
	assert_true(queue[0].payload == null or queue[0].payload == &"",
			"no payload -- ActionSlot would try to crop a portrait a tech has not got")


func test_the_blacksmiths_full_ladder_still_fits_one_page() -> void:
	# Twelve is exactly MAX_DETAILS. Asserted so the day a thirteenth is added, this
	# says so rather than the thirteenth silently not being there.
	var details := SelectionActions.details_for(&"research",
			_finished(&"building.blacksmith"), 1, [], 4)
	assert_eq(SelectionActions.page_count(details.size()), 1)
	assert_eq(details.size(), SelectionActions.MAX_DETAILS)

# ── the [P8] icon set, 2026-08-30 ───────────────────────────────────────────
#
# THE ONE FAILURE THESE CATCH IS A FILENAME, and it is the failure this whole
# mechanism is built to be blind to: `ActionSlot` prefers an icon file over a
# label and falls back silently when `ResourceLoader.exists()` says no, which is
# what let five stand-ins and twenty-seven missing techs ship looking finished.
# A typo'd entry in `ICONS` does not error, does not warn and does not draw --
# the tile just goes back to printing a word, and the only way to see it is to
# open that building in that age.


func test_every_icon_in_the_map_is_a_file_that_exists() -> void:
	for key in SelectionActions.ICONS:
		var path: String = "res://assets/ui/icons/%s" % SelectionActions.ICONS[key]
		assert_true(ResourceLoader.exists(path),
				"ICONS[%s] points at a file that is not there: %s" % [key, path])
	assert_true(ResourceLoader.exists("res://assets/ui/icons/%s"
			% SelectionActions.TECH_FALLBACK_ICON))
	for value in SelectionActions.STANCE_ICONS:
		var path: String = "res://assets/ui/icons/%s" % SelectionActions.STANCE_ICONS[value]
		assert_true(ResourceLoader.exists(path),
				"STANCE_ICONS[%d] points at a file that is not there: %s" % [value, path])


func test_every_technology_has_an_icon_of_its_own() -> void:
	# The fallback exists so a 28th tech draws a scroll rather than a paragraph, and
	# this is what stops it becoming the answer for all of them.
	for id in GameDataRegistry.tech_ids():
		assert_true(SelectionActions.ICONS.has(id),
				"no icon for technology %s -- it would draw the generic scroll" % id)


func test_no_two_actions_share_one_icon_file() -> void:
	# The five stand-ins of asset_request.md [P8] 2 were exactly this: harvest drew
	# res_wood, repair and stance SHARED act_guard, upgrade and research SHARED
	# hud_techtree. Sharing is legal and invisible, so it needs saying out loud when
	# it is meant -- the gate pair below is the only place it still is.
	var seen := {}
	for key in SelectionActions.ICONS:
		var file: String = SelectionActions.ICONS[key]
		assert_false(seen.has(file),
				"%s and %s both draw %s" % [seen.get(file, &""), key, file])
		seen[file] = key


func test_a_formation_tile_carries_both_the_diagram_and_the_word() -> void:
	var details := SelectionActions.details_for(&"move", _militia_facts(), 1, [], 1, &"vee")
	assert_eq(details.size(), 4)
	for a in details:
		assert_false(a.icon.is_empty(), "%s has no diagram" % a.id)
		assert_true(a.captioned, "%s would draw a picture with no word on it" % a.id)
	assert_true(_by_id(details, &"formation:vee").selected)


func test_a_stance_tile_carries_both_the_glyph_and_the_word() -> void:
	# Two of the four are shields and two are blades. Without the caption a player
	# picking Stand Ground is choosing between two similar pictures at 52 px.
	var facts := _militia_facts()
	facts["stance"] = SimUnit.Stance.DEFENSIVE
	var details := SelectionActions.details_for(&"stance", facts)
	assert_eq(details.size(), 4)
	for a in details:
		assert_false(a.icon.is_empty(), "%s has no glyph" % a.id)
		assert_true(a.captioned, "%s would draw a picture with no word on it" % a.id)


func test_the_gate_pair_is_the_only_deliberate_sharing_left() -> void:
	# enter/exit are the gate's two states AND a garrison's two directions, which is
	# PLAN.md 13.2 item 4b answered rather than a compromise. They are separate keys
	# pointing at separate files, so this is about the two CONSUMERS agreeing.
	var locked := _finished(&"building.wall_stone_gate")
	locked["gate_locked"] = true
	var open_it := _by_id(SelectionActions.for_selection(locked, 1, true, [], 4), &"gate")
	assert_eq(open_it.icon, SelectionActions.ICONS[&"exit"])
	assert_eq(open_it.label, "Open Gate")