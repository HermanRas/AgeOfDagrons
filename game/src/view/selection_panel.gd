## The detail panel for whatever is selected (PLAN.md 4.3, 8.1a/8.1b/8.1c).
##
## Reads its content from `GameView.facts_for()` -- snapshot data the view
## already holds -- rather than from the sim, which the view layer may not
## touch (PLAN.md 4).
##
## The training button (5.4) is the one place this panel ISSUES something
## rather than only displaying -- it emits `train_requested`/`cancel_requested`
## rather than calling `Net.submit_command()` itself, so every command still
## leaves the view layer through GameScene, the same path a tap or a
## box-select order does.
class_name SelectionPanel
extends PanelContainer

signal train_requested(building_id: int, unit_def_id: StringName)
signal cancel_requested(building_id: int, index: int)
## Debug-only (PLAN.md 5.5): instantly destroys whatever is selected, since MVP
## has no combat to bring hp to 0 any other way.
signal debug_destroy_requested(target_id: int)

const _GRID_COLUMNS := 5
## Beyond this many, the title's "(+N)" suffix already says how many more
## there are -- a portrait grid past 20 reads as clutter, not information
## (UI_Design.md 4's own "up to 15-20 units" figure).
const _GRID_MAX := 20

var _background: TextureRect
var _title: Label
var _portrait: EntityPortraitView
var _health_bar: HealthBarView
var _detail: Label
var _single_row: HBoxContainer
var _grid: GridContainer
var _train_row: HBoxContainer
var _train_button: Button
var _queue_label: Label
var _cancel_button: Button
var _destroy_button: Button

var _building_id: int = 0
var _trainable: StringName = &""
var _selected_id: int = 0


## Built in `_init()`, not `_ready()`: a bare `.new()` should be fully wired
## for a headless test, the same convention `ResourceHUD`/`ControlGroupsHud`
## already follow.
func _init() -> void:
	custom_minimum_size = Vector2(320.0, 0.0)
	_background = HudStyle.add_panel_background(self)
	if _background != null:
		_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	box.add_child(_title)

	_single_row = HBoxContainer.new()
	_single_row.add_theme_constant_override("separation", 10)
	box.add_child(_single_row)

	_portrait = EntityPortraitView.new()
	_single_row.add_child(_portrait)

	var stats := VBoxContainer.new()
	_single_row.add_child(stats)

	_health_bar = HealthBarView.new()
	stats.add_child(_health_bar)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	stats.add_child(_detail)

	_grid = GridContainer.new()
	_grid.columns = _GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)

	_train_row = HBoxContainer.new()
	box.add_child(_train_row)

	_train_button = Button.new()
	_train_button.pressed.connect(_on_train_pressed)
	_train_row.add_child(_train_button)

	_queue_label = Label.new()
	_train_row.add_child(_queue_label)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_train_row.add_child(_cancel_button)

	_destroy_button = Button.new()
	_destroy_button.text = "Destroy (debug)"
	_destroy_button.pressed.connect(_on_destroy_pressed)
	box.add_child(_destroy_button)

	show_nothing()


func show_nothing() -> void:
	visible = false
	_single_row.visible = false
	_grid.visible = false
	_train_row.visible = false
	_destroy_button.visible = false


## Populate from the primary selected entity, plus how many are selected in
## total. `is_mine` gates the training row -- a selected enemy town centre
## (once there are enemies) must show its health, not a button to train ITS
## villagers on this player's dime.
##
## `all_def_ids` is every currently selected entity's def_id, in the same
## order as the selection -- empty for a single selection, where there is
## nothing a grid would add over the one portrait already shown. Passing it
## is optional so a caller that only cares about the primary (nothing in this
## codebase does today, but nothing should have to) still compiles.
func show_entity(facts: Dictionary, selected_count: int = 1, is_mine: bool = true,
		all_def_ids: Array = []) -> void:
	if facts.is_empty():
		show_nothing()
		return

	visible = true
	_selected_id = int(facts.get("id", 0))
	var def_id: StringName = facts.get("def_id", &"")
	_title.text = _display_name(def_id)
	if selected_count > 1:
		_title.text += "  (+%d)" % (selected_count - 1)

	var show_grid := selected_count > 1 and not all_def_ids.is_empty()
	_single_row.visible = not show_grid
	_grid.visible = show_grid
	if show_grid:
		_populate_grid(all_def_ids)
	else:
		_portrait.def_id = def_id

	var hp := int(facts.get("hp", 0))
	var max_hp := int(facts.get("max_hp", 0))
	if max_hp <= 0:
		_detail.text = ""
		_health_bar.visible = false
	else:
		_detail.text = "%d / %d" % [hp, max_hp]
		_health_bar.visible = true
		_health_bar.fraction = float(hp) / float(max_hp)
		var fraction := float(hp) / float(max_hp)
		if fraction <= HealthDot.CRITICAL_FRACTION:
			_detail.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
		elif fraction <= HealthDot.HURT_FRACTION:
			_detail.add_theme_color_override("font_color", HealthDot.HURT_COLOR)
		else:
			_detail.remove_theme_color_override("font_color")

	_update_training_row(facts, selected_count, is_mine)
	_destroy_button.visible = is_mine and _selected_id != 0


func _populate_grid(all_def_ids: Array) -> void:
	# free() rather than queue_free(): the latter defers to end-of-frame, so a
	# second show_entity() call before any frame passes (as happens back to
	# back in a headless test, and easily could live if two snapshots land
	# quickly) would still see the stale children via get_child_count().
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	for i in range(mini(all_def_ids.size(), _GRID_MAX)):
		var portrait := EntityPortraitView.new()
		portrait.def_id = all_def_ids[i]
		_grid.add_child(portrait)


func _update_training_row(facts: Dictionary, selected_count: int, is_mine: bool) -> void:
	_building_id = int(facts.get("id", 0))
	_trainable = &""

	var building: BuildingDef = GameDataRegistry.building(facts.get("def_id", &""))
	if not is_mine or selected_count != 1 or building == null or building.trains.is_empty():
		_train_row.visible = false
		return

	# One button for MVP's single trainable unit (unit.villager). A roster with
	# more than one trains[] entry needs a row of buttons, not this -- deferred
	# until a building actually declares a second one.
	_trainable = building.trains[0]
	var unit: UnitDef = GameDataRegistry.unit(_trainable)

	_train_row.visible = true
	_train_button.text = "Train %s" % (unit.name if unit != null else String(_trainable))

	var queue_len := int(facts.get("queue_len", 0))
	var queue_fraction := float(facts.get("queue_fraction", 0.0))
	_queue_label.text = "%d queued (%d%%)" % [queue_len, roundi(queue_fraction * 100.0)] \
			if queue_len > 0 else ""
	_cancel_button.visible = queue_len > 0


func _on_train_pressed() -> void:
	if _building_id != 0 and _trainable != &"":
		train_requested.emit(_building_id, _trainable)


func _on_cancel_pressed() -> void:
	if _building_id != 0:
		cancel_requested.emit(_building_id, 0)          # always the front entry


func _on_destroy_pressed() -> void:
	if _selected_id != 0:
		debug_destroy_requested.emit(_selected_id)


## The authored name from units.json / buildings.json, falling back to a tidied
## def id so an entity with no name still reads as something rather than blank.
func _display_name(def_id: StringName) -> String:
	var unit: UnitDef = GameDataRegistry.unit(def_id)
	if unit != null and not unit.name.is_empty():
		return unit.name
	var building: BuildingDef = GameDataRegistry.building(def_id)
	if building != null and not building.name.is_empty():
		return building.name
	return String(def_id).get_slice(".", 1).replace("_", " ").capitalize()
