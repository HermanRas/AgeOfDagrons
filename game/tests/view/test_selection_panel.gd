## PLAN.md 4.3, 8.1a/8.1b/8.1c plus UI_Design.md's selection-panel redesign:
## the two-column detail panel, driven directly by the same facts dictionaries
## GameView.facts_for() produces -- no GameView or snapshot needed.
##
## What each selection can DO is `SelectionActions`' job and is asserted in
## test_selection_actions.gd; this covers what the PANEL does with that answer:
## header/health, filling and hiding slots, expanding a grid, and which signal
## a press turns into.
extends TestCase

var panel: SelectionPanel


func before_each() -> void:
	panel = SelectionPanel.new()


func after_each() -> void:
	panel.free()


func _villager_facts(id: int, hp: int = 30, max_hp: int = 30) -> Dictionary:
	return {"id": id, "def_id": &"unit.villager", "owner_id": 1, "hp": hp, "max_hp": max_hp,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0}


## Carries `queue` as well as `queue_len`, matching what GameView really builds.
## This file's copy of the fixture kept the old count-only shape after the one in
## test_selection_actions.gd was fixed -- so the queue slots here silently fell
## back to the "Queued" label with no portrait, exactly the bug both fixtures
## exist to catch. Two fixtures for one wire shape is the hazard; if a third
## appears, they should become one shared helper.
func _town_center_facts(id: int, queue_len: int = 0) -> Dictionary:
	var queue: Array[StringName] = []
	for i in range(queue_len):
		queue.append(&"unit.villager")
	return {"id": id, "def_id": &"building.town_center", "owner_id": 1, "hp": 2000,
			"max_hp": 2000, "alive": true, "queue_len": queue_len, "queue_fraction": 0.4,
			"queue": queue}


## Slots are reused and hidden past the end rather than freed, so "how many are
## shown" is a visibility count, not a child count.
func _visible(slots: Array[ActionSlot]) -> int:
	var n := 0
	for s in slots:
		if s.visible:
			n += 1
	return n


func _slot_with_action(slots: Array[ActionSlot], id: StringName) -> ActionSlot:
	for s in slots:
		if s.visible and s.action != null and s.action.id == id:
			return s
	return null


# ── showing and hiding ──────────────────────────────────────────────────────

func test_show_nothing_hides_the_panel() -> void:
	panel.show_entity(_villager_facts(1))
	panel.show_nothing()
	assert_false(panel.visible)


func test_empty_facts_is_the_same_as_show_nothing() -> void:
	panel.show_entity({})
	assert_false(panel.visible)


func test_show_nothing_clears_every_slot() -> void:
	panel.show_entity(_town_center_facts(5, 2))
	panel.show_nothing()
	assert_eq(_visible(panel._action_slots), 0)
	assert_eq(_visible(panel._detail_slots), 0)


# ── the header ──────────────────────────────────────────────────────────────

func test_the_title_shows_a_plus_count_for_more_than_one_selected() -> void:
	panel.show_entity(_villager_facts(1), 4)
	assert_true(panel._title.text.ends_with("(+3)"))


func test_health_reflects_the_fraction() -> void:
	panel.show_entity(_villager_facts(1, 15, 30))
	assert_almost_eq(panel._health_bar.fraction, 0.5, 0.001)
	assert_true(panel._health_bar.visible)
	assert_eq(panel._health_label.text, "15 / 30")


func test_health_is_hidden_for_something_with_no_max_hp() -> void:
	panel.show_entity({"id": 1, "def_id": &"res.tree", "owner_id": 0, "hp": 0, "max_hp": 0})
	assert_false(panel._health_bar.visible)


func test_the_portrait_follows_the_primary_selection() -> void:
	panel.show_entity(_villager_facts(1))
	assert_eq(panel._portrait.def_id, &"unit.villager")


# ── filling the columns ─────────────────────────────────────────────────────

func test_a_villager_fills_action_slots() -> void:
	panel.show_entity(_villager_facts(1))
	assert_true(_visible(panel._action_slots) > 0)
	assert_not_null(_slot_with_action(panel._action_slots, &"move"))


func test_something_not_mine_shows_health_but_no_actions() -> void:
	panel.show_entity(_villager_facts(1), 1, false)
	assert_true(panel.visible, "an enemy unit still shows what it is and its health")
	assert_eq(_visible(panel._action_slots), 0)


func test_a_disabled_action_slot_is_shown_but_not_pressable() -> void:
	# Repair, since attack became a real command at 4.13. The rule under test is
	# the layout one and has not changed: an unimplemented verb takes its slot
	# greyed, so the panel does not reflow the day it lands.
	panel.show_entity(_town_center_facts(5))
	var repair := _slot_with_action(panel._action_slots, &"repair")
	assert_not_null(repair, "repair lays out even though no command exists")
	assert_true(repair.disabled)


func test_an_attack_slot_is_pressable_now_that_the_command_exists() -> void:
	panel.show_entity(_villager_facts(1))
	var attack := _slot_with_action(panel._action_slots, &"attack")
	assert_not_null(attack)
	assert_false(attack.disabled)


func test_the_detail_grid_and_divider_hide_when_there_is_nothing_to_show() -> void:
	panel.show_entity(_villager_facts(1))
	assert_false(panel._details_grid.visible,
			"a lone villager's panel is its action column alone, not empty frames")
	assert_false(panel._divider.visible)


func test_a_buildings_queue_fills_the_detail_grid() -> void:
	panel.show_entity(_town_center_facts(5, 2))
	assert_true(panel._details_grid.visible)
	assert_true(panel._divider.visible)
	assert_eq(_visible(panel._detail_slots), 2)


func test_a_smaller_selection_does_not_leave_stale_slots_filled() -> void:
	panel.show_entity(_town_center_facts(5, 3))
	assert_eq(_visible(panel._detail_slots), 3)
	panel.show_entity(_town_center_facts(5, 1))
	assert_eq(_visible(panel._detail_slots), 1)


# ── expanding an action ─────────────────────────────────────────────────────

func test_pressing_build_expands_the_detail_grid_instead_of_ordering() -> void:
	var placed: Array = []
	panel.place_requested.connect(func(def_id: StringName) -> void: placed.append(def_id))
	panel.show_entity(_villager_facts(1))

	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)

	assert_true(placed.is_empty(), "expanding is a view toggle, not an order")
	assert_true(panel._details_grid.visible)
	assert_true(_visible(panel._detail_slots) > 0)


func test_pressing_the_open_action_again_collapses_it() -> void:
	panel.show_entity(_villager_facts(1))
	var build := _slot_with_action(panel._action_slots, &"build").action
	panel._on_action_pressed(build)
	panel._on_action_pressed(build)
	assert_false(panel._details_grid.visible)


func test_changing_selection_closes_an_expanded_action() -> void:
	panel.show_entity(_villager_facts(1))
	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)
	assert_true(panel._details_grid.visible)

	# A Build grid opened on one villager must not stay open over the next.
	panel.show_entity(_villager_facts(2))
	assert_false(panel._details_grid.visible)


# ── presses that become orders ──────────────────────────────────────────────

func test_destroy_requested_names_the_selected_entity() -> void:
	var destroyed: Array[int] = []
	panel.debug_destroy_requested.connect(func(id: int) -> void: destroyed.append(id))
	panel.show_entity(_villager_facts(7))

	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"destroy").action)
	assert_eq(destroyed, [7])


func test_train_requested_names_the_building_and_the_trainable_unit() -> void:
	var trained: Array = []
	panel.train_requested.connect(func(building_id: int, unit_def_id: StringName) -> void:
		trained.append([building_id, unit_def_id]))
	panel.show_entity(_town_center_facts(5))

	panel._on_action_pressed(
			_slot_with_action(panel._action_slots, &"train:unit.villager").action)
	assert_eq(trained, [[5, &"unit.villager"]])


func test_a_plain_verb_reports_itself() -> void:
	var fired: Array = []
	panel.action_requested.connect(func(id: StringName) -> void: fired.append(id))
	panel.show_entity(_villager_facts(1))

	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"stop").action)
	assert_eq(fired, [&"stop"])


func test_picking_a_building_from_the_build_grid_requests_placement() -> void:
	var placed: Array = []
	panel.place_requested.connect(func(def_id: StringName) -> void: placed.append(def_id))
	panel.show_entity(_villager_facts(1))
	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)

	var first: HudAction = panel._detail_slots[0].action
	panel._on_detail_pressed(first)
	assert_eq(placed, [first.payload])


func test_cancelling_a_queue_entry_names_the_building_and_index() -> void:
	var cancelled: Array = []
	panel.cancel_requested.connect(func(building_id: int, index: int) -> void:
		cancelled.append([building_id, index]))
	panel.show_entity(_town_center_facts(5, 2))

	panel._on_detail_pressed(panel._detail_slots[0].action)
	assert_eq(cancelled, [[5, 0]])


# -- paging the build grid ---------------------------------------------------

func _press_detail(id: StringName) -> bool:
	var slot := _slot_with_action(panel._detail_slots, id)
	if slot == null:
		return false
	panel._on_detail_pressed(slot.action)
	return true


func _open_build(age: int) -> void:
	panel.show_entity(_villager_facts(1), 1, true, [], age)
	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)


func test_the_build_grid_opens_on_page_one() -> void:
	_open_build(4)
	assert_eq(panel.current_detail_page(), 0)
	assert_eq(panel.detail_page_count(), 2, "19 buildings do not fit 12 slots")
	assert_null(_slot_with_action(panel._detail_slots, SelectionActions.PAGE_PREV),
			"there is nothing before page 1")
	assert_not_null(_slot_with_action(panel._detail_slots, SelectionActions.PAGE_NEXT))


func test_the_forward_arrow_turns_the_page_and_issues_nothing() -> void:
	# The arrows must not reach place_requested -- tapping > is navigation, and
	# placing a building because the player turned the page would be a disaster
	# in a build menu.
	var placed: Array = []
	panel.place_requested.connect(func(def_id: StringName) -> void: placed.append(def_id))

	_open_build(4)
	assert_true(_press_detail(SelectionActions.PAGE_NEXT))
	assert_eq(panel.current_detail_page(), 1)
	assert_true(placed.is_empty(), "> is navigation, not an order")


func test_the_back_arrow_returns_to_page_one() -> void:
	_open_build(4)
	_press_detail(SelectionActions.PAGE_NEXT)
	assert_not_null(_slot_with_action(panel._detail_slots, SelectionActions.PAGE_PREV),
			"page 2 leads with <")
	assert_true(_press_detail(SelectionActions.PAGE_PREV))
	assert_eq(panel.current_detail_page(), 0)


func test_a_building_on_page_two_can_actually_be_placed() -> void:
	# The whole point: before paging, the buildings past slot 12 were unreachable.
	var placed: Array = []
	panel.place_requested.connect(func(def_id: StringName) -> void: placed.append(def_id))

	_open_build(4)
	_press_detail(SelectionActions.PAGE_NEXT)
	var wonder := _slot_with_action(panel._detail_slots, &"place:building.wonder")
	assert_not_null(wonder, "the wonder is on page 2 and is on screen")
	panel._on_detail_pressed(wonder.action)
	assert_eq(placed, [&"building.wonder"])


func test_placing_from_page_two_stays_on_page_two() -> void:
	# Placement leaves build mode open on purpose (coming back for a second house
	# should not need Build tapped again); the page has to survive with it, or
	# every placement would bounce the player back to page 1.
	_open_build(4)
	_press_detail(SelectionActions.PAGE_NEXT)
	_press_detail(&"place:building.wonder")
	assert_eq(panel.current_detail_page(), 1)


func test_reopening_build_starts_at_page_one_again() -> void:
	_open_build(4)
	_press_detail(SelectionActions.PAGE_NEXT)
	assert_eq(panel.current_detail_page(), 1)

	# Close, then reopen.
	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)
	panel._on_action_pressed(_slot_with_action(panel._action_slots, &"build").action)
	assert_eq(panel.current_detail_page(), 0,
			"reopening on page 2 would hide the buildings most used")


func test_selecting_something_else_resets_the_page() -> void:
	_open_build(4)
	_press_detail(SelectionActions.PAGE_NEXT)
	panel.show_entity(_villager_facts(2), 1, true, [], 4)
	assert_eq(panel.current_detail_page(), 0)


func test_an_age_one_villager_sees_no_arrows() -> void:
	_open_build(1)
	assert_eq(panel.detail_page_count(), 1)
	assert_null(_slot_with_action(panel._detail_slots, SelectionActions.PAGE_NEXT))
	assert_null(_slot_with_action(panel._detail_slots, SelectionActions.PAGE_PREV))


func test_no_page_ever_shows_more_slots_than_the_grid_has() -> void:
	for age in [1, 2, 3, 4]:
		_open_build(age)
		for page in range(panel.detail_page_count()):
			assert_true(_visible(panel._detail_slots) <= SelectionActions.MAX_DETAILS,
					"age %d page %d fits" % [age, page])
			_press_detail(SelectionActions.PAGE_NEXT)

# -- portraits carry the selection owner's colour ----------------------------

func test_the_panel_portrait_takes_the_owners_skin() -> void:
	panel.show_entity(_villager_facts(1), 1, true, [], 3, 5)
	assert_eq(panel._portrait.skin_age, 3)
	assert_eq(panel._portrait.skin_colour, 5)


func test_every_slot_is_skinned_before_its_action_is_set() -> void:
	# set_action() is what crops the portrait, so a slot skinned afterwards would
	# show the previous owner's colour until something forced a refresh.
	panel.show_entity(_town_center_facts(5), 1, true, [], 2, 6)
	var train := _slot_with_action(panel._action_slots, &"train:unit.villager")
	assert_not_null(train)
	assert_eq(train.portrait_colour, 6)
	assert_eq(train.portrait_age, 2)


func test_an_enemy_selection_shows_their_colour_not_ours() -> void:
	# The case the whole change exists for: with is_mine false there are no
	# actions at all, so the portrait is the ONLY thing that can say whose it is.
	panel.show_entity(_villager_facts(1), 1, false, [], 1, 4)
	assert_eq(panel._portrait.skin_colour, 4)
	assert_eq(_visible(panel._action_slots), 0, "still no orders for something not ours")


func test_the_colour_defaults_to_untinted_for_a_caller_that_passes_none() -> void:
	panel.show_entity(_villager_facts(1))
	assert_eq(panel._portrait.skin_colour, -1)

# -- the name strip over a portrait -------------------------------------------

func _caption_of(slots: Array[ActionSlot], id: StringName) -> String:
	var slot := _slot_with_action(slots, id)
	if slot == null or not slot._caption.visible:
		return ""
	return slot._caption.text


func test_a_portrait_slot_is_captioned_with_its_name() -> void:
	# A build grid is a dozen brown isometric buildings; the sprite says what
	# KIND of thing it is and the caption says which one.
	_open_build(4)
	assert_eq(_caption_of(panel._detail_slots, &"place:building.house"), "House")
	assert_eq(_caption_of(panel._detail_slots, &"place:building.town_center"), "Town Center")

	# The wonder is an age-4 building, so it is on page 2 -- captions have to
	# survive a page turn, since the slots are reused in place rather than rebuilt.
	_press_detail(SelectionActions.PAGE_NEXT)
	assert_eq(_caption_of(panel._detail_slots, &"place:building.wonder"), "Wonder")


func test_a_train_slot_is_captioned_too() -> void:
	panel.show_entity(_town_center_facts(5), 1, true, [], 1)
	assert_eq(_caption_of(panel._action_slots, &"train:unit.villager"), "Villager")


func test_a_verb_icon_is_not_captioned() -> void:
	# An icon file means a verb whose icon is already a picture OF the word.
	# Printing "Move" across it adds nothing and costs a fifth of the tile.
	panel.show_entity(_villager_facts(1))
	var move := _slot_with_action(panel._action_slots, &"move")
	assert_not_null(move)
	assert_false(move._caption.visible)
	assert_false(move._caption_bg.visible)


func test_the_caption_makes_room_for_a_badge() -> void:
	# A queue slot carries the unit's name AND its "84%" along the same bottom
	# edge; without this they print over each other.
	panel.show_entity(_town_center_facts(5, 2), 1, true, [], 1)
	var front := panel._detail_slots[0]
	assert_eq(front.action.id, &"cancel:0")
	assert_false(front.action.badge.is_empty(), "the front queue entry shows progress")
	assert_true(front._caption.offset_right < -ActionSlot.CAPTION_INSET,
			"the strip stops short of the badge")

	var second := panel._detail_slots[1]
	assert_true(second.action.badge.is_empty())
	assert_eq(second._caption.offset_right, -ActionSlot.CAPTION_INSET,
			"and uses the full width when there is no badge")


func test_an_emptied_slot_leaves_no_caption_behind() -> void:
	# Slots are reused in place rather than freed, so a strip left visible from a
	# previous occupant would draw a black bar over the next one's art.
	_open_build(4)
	assert_true(panel._detail_slots[0]._caption.visible)
	panel.show_nothing()
	panel.show_entity(_villager_facts(1))
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and not slot.action.icon.is_empty():
			assert_false(slot._caption.visible, "%s carries no stale caption" % slot.action.id)