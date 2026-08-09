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


func _town_center_facts(id: int, queue_len: int = 0) -> Dictionary:
	return {"id": id, "def_id": &"building.town_center", "owner_id": 1, "hp": 2000,
			"max_hp": 2000, "alive": true, "queue_len": queue_len, "queue_fraction": 0.4}


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
	panel.show_entity(_villager_facts(1))
	var attack := _slot_with_action(panel._action_slots, &"attack")
	assert_not_null(attack, "attack lays out even though no command exists")
	assert_true(attack.disabled)


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
