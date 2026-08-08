## The detail panel for whatever is selected (PLAN.md 4.3, "panel populates").
## Phase 4.3.
##
## Deliberately plain. The real HUD is phase 9 and is specified in UI_Design.md;
## what 4.3 owes is that selecting something SHOWS something, so that tapping has
## visible consequences before there is a designed panel to put them in. Anything
## prettier now would be work thrown away when the real layout lands.
##
## Reads its content from `GameView.facts_for()` -- snapshot data the view already
## holds -- rather than from the sim, which the view layer may not touch (PLAN.md 4).
##
## The training button (5.4) is the one place this panel ISSUES something rather
## than only displaying -- it emits `train_requested`/`cancel_requested` rather
## than calling `Net.submit_command()` itself, so every command still leaves the
## view layer through GameScene, the same path a tap or a box-select order does.
class_name SelectionPanel
extends PanelContainer

const HURT_COLOR := Color(1.0, 0.7, 0.25)
const CRITICAL_COLOR := Color(1.0, 0.35, 0.3)
## Matches the health-dot thresholds at 4.6 so one entity is never described as
## hurt in one place and healthy in another.
const HURT_FRACTION := 0.5
const CRITICAL_FRACTION := 0.25

signal train_requested(building_id: int, unit_def_id: StringName)
signal cancel_requested(building_id: int, index: int)

var _title: Label
var _detail: Label
var _train_row: HBoxContainer
var _train_button: Button
var _queue_label: Label
var _cancel_button: Button

var _building_id: int = 0
var _trainable: StringName = &""


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	box.add_child(_detail)

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

	show_nothing()


func show_nothing() -> void:
	visible = false
	_train_row.visible = false


## Populate from one entity, plus how many are selected in total. `is_mine`
## gates the training row -- a selected enemy town centre (once there are
## enemies) must show its health, not a button to train ITS villagers on this
## player's dime.
func show_entity(facts: Dictionary, selected_count: int = 1, is_mine: bool = true) -> void:
	if facts.is_empty():
		show_nothing()
		return

	visible = true
	var def_id: StringName = facts.get("def_id", &"")
	_title.text = _display_name(def_id)
	if selected_count > 1:
		_title.text += "  (+%d)" % (selected_count - 1)

	var hp := int(facts.get("hp", 0))
	var max_hp := int(facts.get("max_hp", 0))
	if max_hp <= 0:
		_detail.text = ""
	else:
		_detail.text = "%d / %d" % [hp, max_hp]
		var fraction := float(hp) / float(max_hp)
		if fraction <= CRITICAL_FRACTION:
			_detail.add_theme_color_override("font_color", CRITICAL_COLOR)
		elif fraction <= HURT_FRACTION:
			_detail.add_theme_color_override("font_color", HURT_COLOR)
		else:
			_detail.remove_theme_color_override("font_color")

	_update_training_row(facts, selected_count, is_mine)


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
