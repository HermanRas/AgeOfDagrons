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
class_name SelectionPanel
extends PanelContainer

const HURT_COLOR := Color(1.0, 0.7, 0.25)
const CRITICAL_COLOR := Color(1.0, 0.35, 0.3)
## Matches the health-dot thresholds at 4.6 so one entity is never described as
## hurt in one place and healthy in another.
const HURT_FRACTION := 0.5
const CRITICAL_FRACTION := 0.25

var _title: Label
var _detail: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	box.add_child(_detail)

	show_nothing()


func show_nothing() -> void:
	visible = false


## Populate from one entity, plus how many are selected in total.
func show_entity(facts: Dictionary, selected_count: int = 1) -> void:
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
		return

	_detail.text = "%d / %d" % [hp, max_hp]
	var fraction := float(hp) / float(max_hp)
	if fraction <= CRITICAL_FRACTION:
		_detail.add_theme_color_override("font_color", CRITICAL_COLOR)
	elif fraction <= HURT_FRACTION:
		_detail.add_theme_color_override("font_color", HURT_COLOR)
	else:
		_detail.remove_theme_color_override("font_color")


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
