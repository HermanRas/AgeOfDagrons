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
	# PLAN.md 5.8's `buildable: false`. A wall tier is four defs and only two of them
	# are a player's to pick: the short segment IS the tier (it carries
	# `wall_lengths`, and the drag reads that to decide what to lay), and the gate is
	# placed on its own. Without the filter the grid would carry all twelve pieces and
	# eight of them would each place one fixed-length block -- which is exactly the
	# outcome buildings.json refused to ship walls at all rather than allow.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var offered: Array = []
	for a in details:
		if a.payload != null:
			offered.append(a.payload)

	for hidden in [&"building.wall_wood_medium", &"building.wall_wood_long",
			&"building.wall_stone_medium", &"building.wall_stone_long",
			&"building.wall_reinforced_medium", &"building.wall_reinforced_long"]:
		assert_false(offered.has(hidden), "%s is placed by the drag, not by the menu" % hidden)

	for shown in [&"building.wall_wood_short", &"building.wall_wood_gate",
			&"building.wall_stone_short", &"building.wall_stone_gate",
			&"building.wall_reinforced_short", &"building.wall_reinforced_gate"]:
		assert_true(offered.has(shown), "%s is a menu entry" % shown)


func test_a_wall_tier_is_one_entry_per_material_plus_its_gate() -> void:
	# The project owner's shape (2026-08-21): all three tiers stay available at age 4,
	# so a player there has six wall entries -- wood, stone and reinforced, each with
	# a gate -- rather than one wall that re-skinned the other two away.
	var details := SelectionActions.details_for(&"build", _villager_facts(), 1, [], 4)
	var walls := 0
	for a in details:
		if a.payload != null and String(a.payload).begins_with("building.wall_"):
			walls += 1
	assert_eq(walls, 6, "three tiers, a wall and a gate each")


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
	assert_eq((by_age[2] as Array).size(), 2, "wood and its gate at age 2")
	assert_eq((by_age[3] as Array).size(), 4, "stone joins at age 3")
	assert_eq((by_age[4] as Array).size(), 6, "reinforced joins at age 4")


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