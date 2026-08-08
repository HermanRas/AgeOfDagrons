## PLAN.md 4.3, 8.1a/8.1b/8.1c: the detail panel, driven directly by the same
## facts dictionaries GameView.facts_for() produces -- no GameView or snapshot
## needed to exercise it.
extends TestCase

var panel: SelectionPanel


func before_each() -> void:
	panel = SelectionPanel.new()


func after_each() -> void:
	panel.free()


func _villager_facts(id: int, hp: int = 30, max_hp: int = 30) -> Dictionary:
	return {"id": id, "def_id": &"unit.villager", "owner_id": 1, "hp": hp, "max_hp": max_hp,
			"alive": true, "task": 0, "queue_len": 0, "queue_fraction": 0.0}


func _town_center_facts(id: int) -> Dictionary:
	return {"id": id, "def_id": &"building.town_center", "owner_id": 1, "hp": 2000, "max_hp": 2000,
			"alive": true, "queue_len": 0, "queue_fraction": 0.0}


func test_show_nothing_hides_the_panel() -> void:
	panel.show_entity(_villager_facts(1))
	panel.show_nothing()
	assert_false(panel.visible)


func test_empty_facts_is_the_same_as_show_nothing() -> void:
	panel.show_entity({})
	assert_false(panel.visible)


func test_a_single_selection_shows_the_portrait_row_not_the_grid() -> void:
	panel.show_entity(_villager_facts(1))
	assert_true(panel.visible)
	assert_true(panel._single_row.visible)
	assert_false(panel._grid.visible)
	assert_eq(panel._portrait.def_id, &"unit.villager")


func test_a_multi_selection_with_def_ids_shows_the_grid_not_the_portrait_row() -> void:
	panel.show_entity(_villager_facts(1), 3, true, [&"unit.villager", &"unit.villager", &"unit.villager"])
	assert_true(panel._grid.visible)
	assert_false(panel._single_row.visible)
	assert_eq(panel._grid.get_child_count(), 3)


func test_a_multi_selection_without_def_ids_falls_back_to_the_single_row() -> void:
	# A caller that only ever passes the primary's facts (no grid list) must
	# still show something rather than an empty panel.
	panel.show_entity(_villager_facts(1), 3)
	assert_true(panel._single_row.visible)
	assert_false(panel._grid.visible)


func test_the_grid_is_capped_and_rebuilt_each_call() -> void:
	var many: Array = []
	for i in range(30):
		many.append(&"unit.villager")
	panel.show_entity(_villager_facts(1), many.size(), true, many)
	assert_eq(panel._grid.get_child_count(), SelectionPanel._GRID_MAX)

	panel.show_entity(_villager_facts(1), 2, true, [&"unit.villager", &"unit.villager"])
	assert_eq(panel._grid.get_child_count(), 2, "a smaller selection must not leave stale portraits")


func test_health_bar_reflects_the_fraction() -> void:
	panel.show_entity(_villager_facts(1, 15, 30))
	assert_almost_eq(panel._health_bar.fraction, 0.5, 0.001)
	assert_true(panel._health_bar.visible)


func test_health_bar_is_hidden_for_something_with_no_max_hp() -> void:
	panel.show_entity({"id": 1, "def_id": &"res.tree", "owner_id": 0, "hp": 0, "max_hp": 0})
	assert_false(panel._health_bar.visible)


func test_the_title_shows_a_plus_count_for_more_than_one_selected() -> void:
	panel.show_entity(_villager_facts(1), 4)
	assert_true(panel._title.text.ends_with("(+3)"))


func test_destroy_requested_names_the_selected_entity() -> void:
	var destroyed: Array[int] = []
	panel.debug_destroy_requested.connect(func(id: int) -> void: destroyed.append(id))
	panel.show_entity(_villager_facts(7))
	panel._on_destroy_pressed()
	assert_eq(destroyed, [7])


func test_destroy_button_hidden_for_something_not_mine() -> void:
	panel.show_entity(_villager_facts(1), 1, false)
	assert_false(panel._destroy_button.visible)


func test_train_row_shows_for_a_single_owned_trainable_building() -> void:
	panel.show_entity(_town_center_facts(5))
	assert_true(panel._train_row.visible)


func test_train_requested_names_the_building_and_the_trainable_unit() -> void:
	var trained: Array = []
	panel.train_requested.connect(func(building_id: int, unit_def_id: StringName) -> void:
		trained.append([building_id, unit_def_id]))
	panel.show_entity(_town_center_facts(5))
	panel._on_train_pressed()
	assert_eq(trained, [[5, &"unit.villager"]])


func test_train_row_hidden_when_multiple_are_selected() -> void:
	panel.show_entity(_town_center_facts(5), 2)
	assert_false(panel._train_row.visible)


func test_train_row_hidden_for_a_building_that_is_not_mine() -> void:
	panel.show_entity(_town_center_facts(5), 1, false)
	assert_false(panel._train_row.visible)


func test_train_row_hidden_for_a_unit() -> void:
	panel.show_entity(_villager_facts(1))
	assert_false(panel._train_row.visible)
