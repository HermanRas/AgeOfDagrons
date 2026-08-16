## The detail panel for whatever is selected (PLAN.md 4.3, 8.1a/8.1b/8.1c),
## rebuilt to UI_Design.md's two-column layout: an action column on the left
## (portrait + health above a 4x2 grid of verbs) and a detail grid on the right
## (4x3), separated by a gold rule.
##
## Reads its content from `GameView.facts_for()` -- snapshot data the view
## already holds -- rather than from the sim, which the view layer may not
## touch (PLAN.md 4).
##
## Decides nothing about WHAT can be done: `SelectionActions` answers that from
## facts alone, and this only draws the answer and reports taps back out. Every
## order still leaves the view layer through GameScene via a signal, never by
## calling `Net.submit_command()` here, the same route a tap or box-select
## order takes.
##
## The left column's actions are fixed slots reused in place; tapping one that
## `expands` (Build on a villager, Move on a soldier) refills the right grid
## instead of issuing an order, and tapping it again collapses back to the
## selection's own default detail.
##
## Built in `_init()`, not `_ready()`: a bare `.new()` should be fully wired for
## a headless test, the same convention `ResourceHUD`/`ControlGroupsHud` follow.
class_name SelectionPanel
extends PanelContainer

## A verb with a real command behind it fired on the current selection --
## `&"move"`, `&"stop"`, `&"harvest"`, `&"destroy"`. Disabled placeholders never
## reach here (`ActionSlot` swallows their press), so a listener does not have
## to re-check what MVP implements.
signal action_requested(action_id: StringName)

## A building was asked to train `unit_def_id` (5.4).
signal train_requested(building_id: int, unit_def_id: StringName)

## Cancel the production entry at `index` (always 0 today -- the front entry).
signal cancel_requested(building_id: int, index: int)

## Enter placement mode for `def_id` (5.1) -- the villager Build action's grid.
signal place_requested(def_id: StringName)

## Debug-only (PLAN.md 5.5): instantly destroys whatever is selected, since MVP
## has no combat to bring hp to 0 any other way.
signal debug_destroy_requested(target_id: int)

const _ACTION_COLUMNS := 4
const _DETAIL_COLUMNS := 4
const _SLOT_SIZE := 72.0
const _HEALTH_BAR_SIZE := Vector2(176.0, 30.0)
const _DIVIDER_COLOR := Color(0.937, 0.769, 0.290)

var _portrait: EntityPortraitView
var _title: Label
var _health_label: Label
var _health_bar: HealthBarView
var _single_row: HBoxContainer
var _actions_grid: GridContainer
var _divider: ColorRect
var _details_grid: GridContainer

var _action_slots: Array[ActionSlot] = []
var _detail_slots: Array[ActionSlot] = []

var _building_id: int = 0
var _selected_id: int = 0

## Which `expands` action is currently open in the detail grid, or `&""` for
## the selection's own default detail. Cleared whenever the selection changes
## so a stale Build grid never outlives the villager that opened it.
var _active_action: StringName = &""

## Which page of the detail grid is open. Reset alongside `_active_action`, and
## again whenever a different action is expanded: opening Build should always
## start at page 1, never at whatever page was left open last time.
var _detail_page: int = 0

## Last shown inputs, kept so re-expanding an action can rebuild the detail
## grid without GameScene having to re-send a snapshot it may not have yet.
var _facts: Dictionary = {}
var _selected_count: int = 1
var _all_def_ids: Array = []
## The selection owner's age, which gates the train and build rows. Kept with the
## other inputs so re-expanding an action rebuilds against the same age it was
## opened at rather than defaulting back to 1.
var _age: int = 1
## The selection owner's palette index, tinting every cropped portrait here.
var _colour: int = -1


func _init() -> void:
	custom_minimum_size = Vector2(320.0, 0.0)
	# No panel background by design (UI_Design.md redesign): the slot frames and
	# the gold divider carry the panel on their own. This override still has to
	# be cleared or PanelContainer's default themed box paints a rectangle
	# behind them -- the same halo HudStyle.add_panel_background() documents.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)

	var columns := HBoxContainer.new()
	margin.add_child(columns)

	var actions_column := VBoxContainer.new()
	columns.add_child(actions_column)

	_single_row = HBoxContainer.new()
	_single_row.add_theme_constant_override("separation", 10)
	actions_column.add_child(_single_row)

	_portrait = EntityPortraitView.new()
	_single_row.add_child(_portrait)

	var stats := VBoxContainer.new()
	_single_row.add_child(stats)

	var stats_top := HBoxContainer.new()
	stats.add_child(stats_top)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_top.add_child(_title)

	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 14)
	stats_top.add_child(_health_label)

	_health_bar = HealthBarView.new()
	# Overrides the bar art's own 176x46 pixel size: the redesign gives it a
	# shorter 30px lane so the portrait row stays under 72px tall.
	_health_bar.custom_minimum_size = _HEALTH_BAR_SIZE
	stats.add_child(_health_bar)

	_actions_grid = GridContainer.new()
	_actions_grid.columns = _ACTION_COLUMNS
	_actions_grid.add_theme_constant_override("h_separation", 4)
	_actions_grid.add_theme_constant_override("v_separation", 4)
	actions_column.add_child(_actions_grid)

	for i in range(SelectionActions.MAX_ACTIONS):
		var slot := ActionSlot.new()
		slot.action_pressed.connect(_on_action_pressed)
		_actions_grid.add_child(slot)
		_action_slots.append(slot)

	_divider = ColorRect.new()
	_divider.color = _DIVIDER_COLOR
	_divider.custom_minimum_size = Vector2(2.0, 0.0)
	columns.add_child(_divider)

	_details_grid = GridContainer.new()
	_details_grid.columns = _DETAIL_COLUMNS
	_details_grid.add_theme_constant_override("h_separation", 4)
	_details_grid.add_theme_constant_override("v_separation", 4)
	columns.add_child(_details_grid)

	for i in range(SelectionActions.MAX_DETAILS):
		var slot := ActionSlot.new()
		slot.action_pressed.connect(_on_detail_pressed)
		_details_grid.add_child(slot)
		_detail_slots.append(slot)

	show_nothing()


func show_nothing() -> void:
	visible = false
	_facts = {}
	_selected_id = 0
	_building_id = 0
	_active_action = &""
	_detail_page = 0
	_fill(_action_slots, [])
	_fill(_detail_slots, [])
	_divider.visible = false


## Populate from the primary selected entity, plus how many are selected in
## total. `is_mine` gates the ACTION column entirely -- a selected enemy town
## centre (once there are enemies) shows its portrait and health, never a
## button to spend this player's resources on it.
##
## `all_def_ids` is every currently selected entity's def_id, in selection
## order -- empty for a single selection, where the one portrait above already
## says what is selected. Optional so a caller that only has the primary's
## facts still compiles.
##
## `age` is the SELECTION OWNER's age (GameView.age_of). It gates which units a
## building offers to train and which buildings a villager offers to place, and
## defaults to 1 so a caller with no age still gets the age-1 menu.
##
## `colour` is that same owner's palette index (GameView.skin_for), and it tints
## every cropped portrait on the panel. The owner's, deliberately, not the local
## player's: a selected enemy unit is exactly the case where the player cannot
## see whose it is any other way. -1 leaves portraits untinted.
func show_entity(facts: Dictionary, selected_count: int = 1, is_mine: bool = true,
		all_def_ids: Array = [], age: int = 1, colour: int = -1) -> void:
	if facts.is_empty():
		show_nothing()
		return

	# A different entity (or a different-sized group) invalidates whatever
	# action was expanded -- a Build grid opened on one villager must not stay
	# open across a selection change.
	var next_id := int(facts.get("id", 0))
	if next_id != _selected_id or selected_count != _selected_count:
		_active_action = &""
		_detail_page = 0

	visible = true
	_facts = facts
	_selected_count = selected_count
	_all_def_ids = all_def_ids
	_age = age
	_colour = colour
	_selected_id = next_id
	_building_id = next_id

	var def_id: StringName = facts.get("def_id", &"")
	_title.text = _display_name(def_id)
	if selected_count > 1:
		_title.text += "  (+%d)" % (selected_count - 1)

	_portrait.def_id = def_id
	_portrait.set_skin(age, colour)
	_refresh_health(facts)

	_fill(_action_slots,
			SelectionActions.for_selection(facts, selected_count, is_mine, all_def_ids, age))
	_refresh_details()


func _refresh_health(facts: Dictionary) -> void:
	var hp := int(facts.get("hp", 0))
	var max_hp := int(facts.get("max_hp", 0))
	if max_hp <= 0:
		_health_label.text = ""
		_health_bar.visible = false
		return

	_health_label.text = "%d / %d" % [hp, max_hp]
	_health_bar.visible = true
	var fraction := float(hp) / float(max_hp)
	_health_bar.fraction = fraction
	if fraction <= HealthDot.CRITICAL_FRACTION:
		_health_label.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	elif fraction <= HealthDot.HURT_FRACTION:
		_health_label.add_theme_color_override("font_color", HealthDot.HURT_COLOR)
	else:
		_health_label.remove_theme_color_override("font_color")


## The right grid, for whatever is currently expanded. Hidden entirely (divider
## and all) when there is nothing to show, so a plain villager's panel is just
## its action column rather than a column of empty frames.
##
## `details_for()` hands back the WHOLE list and `page_of()` slices it, so the
## grid never silently drops what will not fit -- the age-4 build list is 19
## buildings in 12 slots. Visibility is decided on the full list rather than on
## the page, since only an empty list means "nothing to show".
func _refresh_details() -> void:
	var details := SelectionActions.details_for(
			_active_action, _facts, _selected_count, _all_def_ids, _age)
	_fill(_detail_slots, SelectionActions.page_of(details, _detail_page))
	_details_grid.visible = not details.is_empty()
	_divider.visible = not details.is_empty()


## How many pages the currently open detail list spans. For tests and for
## anything that wants to show a page indicator later.
func detail_page_count() -> int:
	return SelectionActions.page_count(SelectionActions.details_for(
			_active_action, _facts, _selected_count, _all_def_ids, _age).size())


func current_detail_page() -> int:
	return _detail_page


## Slots are reused in place and hidden past the end rather than freed: a
## selection refreshing every snapshot would otherwise churn ~20 nodes a tick.
## Hiding (not queue_free) also keeps a headless test's counts stable without
## waiting for a frame, the trap the old grid's free() comment recorded.
func _fill(slots: Array[ActionSlot], entries: Array[HudAction]) -> void:
	for i in range(slots.size()):
		# Skin BEFORE the action: set_action() is what crops the portrait, so a
		# slot skinned afterwards would show the previous owner's colour until
		# something else forced a refresh.
		slots[i].portrait_age = _age
		slots[i].portrait_colour = _colour
		slots[i].set_action(entries[i] if i < entries.size() else null)


func _on_action_pressed(action: HudAction) -> void:
	# An expanding action is a VIEW toggle, not an order -- it only decides what
	# the right grid lists. Tapping the open one again closes it.
	if action.expands:
		_active_action = &"" if _active_action == action.id else action.id
		# Always back to page 1: reopening Build and landing on page 2 because
		# that is where it was left would hide the buildings most used.
		_detail_page = 0
		_refresh_details()
		return

	var id := String(action.id)
	if id.begins_with("train:"):
		if _building_id != 0:
			train_requested.emit(_building_id, StringName(id.trim_prefix("train:")))
		return
	if action.id == &"destroy":
		if _selected_id != 0:
			debug_destroy_requested.emit(_selected_id)
		return

	action_requested.emit(action.id)


func _on_detail_pressed(action: HudAction) -> void:
	# The arrows turn the page and issue nothing. Checked first so neither can be
	# mistaken for a slot with a payload, and clamped in page_of() rather than
	# here -- one place decides what a page number means.
	if action.id == SelectionActions.PAGE_NEXT:
		# Clamped as it is stored, not only as it is read: ">" is never drawn on
		# the last page, so this cannot run off the end through the UI, but a
		# page number that only LOOKS valid because page_of() clamps it would
		# make "<" appear to do nothing on the first press back.
		_detail_page = mini(_detail_page + 1, maxi(0, detail_page_count() - 1))
		_refresh_details()
		return
	if action.id == SelectionActions.PAGE_PREV:
		_detail_page = maxi(0, _detail_page - 1)
		_refresh_details()
		return

	var id := String(action.id)
	if id.begins_with("place:"):
		place_requested.emit(StringName(id.trim_prefix("place:")))
		# Leaves build mode's grid open: placement is a drag-and-drop gesture on
		# the world (5.1), and coming back for a second house should not need
		# the Build action tapped again.
		return
	if id.begins_with("cancel:") and _building_id != 0:
		cancel_requested.emit(_building_id, int(id.trim_prefix("cancel:")))


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
