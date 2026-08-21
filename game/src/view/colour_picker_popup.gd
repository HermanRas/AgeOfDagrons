## Picking a player colour from the palette, for the skirmish screen / lobby
## (PLAN.md 1.6, 12.1c).
##
## REPLACES A CYCLE. Colour used to be one button per slot that stepped to the next
## free colour on each press: cheap to write, and it made choosing violet from eight
## a matter of pressing five times and watching. Worse on a joined client, where
## each press was a round trip to the host, so the player was cycling blind through
## a list they could not see. This shows the list.
##
## ONLY THE COLOURS THAT ARE FREE ARE ON IT, which is the whole rule the cycle was
## enforcing, moved from "the press cannot land on a taken colour" to "a taken
## colour is not on the screen". With colour the only thing telling players apart
## (PLAN.md 1), a duplicate is not a cosmetic slip -- it is an unplayable match --
## so the constraint is worth stating in the UI rather than only in the handler.
## Your OWN current colour is on it, marked, because a grid that omitted it would
## be a grid with no answer to "which one am I".
##
## AN IN-SCENE OVERLAY, NOT A `Popup`. Godot's popups position themselves in screen
## coordinates and take their own window on some platforms; this project's screens
## are all full-rect Controls under `canvas_items` stretch, and a modal built the
## same way is one that lays out identically on a phone and can be exercised by a
## test with no tree, no window and no mouse. `HudPanel`'s three pages make the
## same choice.
##
## IT DECIDES NOTHING. It emits the index that was pressed;
## `SkirmishScreen._on_colour_pressed` is what applies it locally or asks the host
## for it, because the no-duplicates rule belongs to whoever can see every slot.
class_name ColourPickerPopup
extends Control

## The palette index the player pressed. Never a taken one -- those have no button.
signal colour_chosen(index: int)
signal cancelled()

const COLUMNS := 4
const SWATCH := Vector2(112.0, 68.0)

var _title: Label
var _grid: GridContainer

## The swatch buttons currently on the grid, keyed by palette index, so a test can
## press the button for a particular colour rather than the third child of a
## container.
var _swatches: Dictionary = {}          # int index -> Button


func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Blocks, so a press that misses a swatch does not fall through onto the slot
	# rows underneath and change a role by accident.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# The same flat fill and gold border the three corner pages wear -- see
	# `HudPanel.page_style` for why `panel_background.png` is not used at this size.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", HudPanel.page_style())
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	column.add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_grid)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(0.0, 40.0)
	cancel.pressed.connect(_on_cancel)
	column.add_child(cancel)


## Show the free colours plus `current`.
##
## `taken` is what everybody ELSE holds, and the caller decides what "everybody
## else" means -- on the host that is the other ACTIVE slots, since a closed slot
## holds no player and its colour is nobody's. That distinction cost a bug once
## already (`SkirmishScreen._cycle_colour`'s note) and it stays on the caller's side
## of the line.
func open_for(who: String, current: int, taken: Array[int]) -> void:
	_title.text = "%s — pick a colour" % who
	_rebuild(current, taken)
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Which colours the grid is currently offering, sorted. For tests, and for the one
## assertion worth making about this control: that nothing anybody else holds is on
## it.
func offered() -> Array[int]:
	var out: Array[int] = []
	for index in _swatches:
		out.append(int(index))
	out.sort()
	return out


## The button for one palette index, or null if it is not on the grid.
func swatch_for(index: int) -> Button:
	return _swatches.get(index)


func _rebuild(current: int, taken: Array[int]) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_swatches.clear()

	var count := GameDataRegistry.colour_count() if GameDataRegistry != null else 0
	for index in range(count):
		# The one exception to "free colours only": your own. Otherwise the grid has
		# no way to show which colour you already have, and pressing it -- a no-op --
		# is a perfectly reasonable way to close a picker you opened by accident.
		if taken.has(index) and index != current:
			continue
		var button := _swatch(index, index == current)
		_swatches[index] = button
		_grid.add_child(button)

	# A grid with nothing on it means the palette is smaller than the match, which
	# `colours.json` sizes against PLAN.md 3.1's eight players so it should not
	# happen -- said out loud rather than presented as an empty box, because an empty
	# box reads as a broken screen.
	if _swatches.is_empty():
		var empty := Label.new()
		empty.text = "every colour is taken"
		empty.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
		_grid.add_child(empty)


## One colour, drawn AS that colour. The swatch is the whole button rather than a
## chip beside a name, because that is what the project owner's mockup is: flat
## blocks of colour in a grid. The name is written across it so the grid is still
## usable by somebody who cannot separate two of the hues -- which is the entire
## reason `colours.json` chose these eight on a lightness ladder in the first place.
func _swatch(index: int, is_current: bool) -> Button:
	var colour := GameDataRegistry.colour(index) if GameDataRegistry != null else Color.WHITE

	var button := Button.new()
	button.custom_minimum_size = SWATCH
	button.text = String(GameDataRegistry.colour_slug(index)).capitalize() \
			if GameDataRegistry != null else "Colour %d" % (index + 1)
	button.add_theme_font_size_override("font_size", 15)

	var style := StyleBoxFlat.new()
	style.bg_color = colour
	# THE CURRENT COLOUR IS THE ONE WITH THE GOLD BORDER. Not a tick, not a word:
	# the border is the same gold every other selected thing in this HUD uses, and it
	# survives being looked at by somebody who cannot tell two of the swatches apart.
	style.border_color = HudStyle.GOLD if is_current else Color(0.0, 0.0, 0.0, 0.6)
	style.set_border_width_all(3 if is_current else 1)
	button.add_theme_stylebox_override("normal", style)

	# Pressed and hovered inherit `normal`'s fill or the swatch flashes the theme's
	# default grey mid-press, which on a colour picker reads as picking the wrong one.
	var lit := style.duplicate() as StyleBoxFlat
	lit.bg_color = colour.lightened(0.15)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("pressed", lit)
	button.add_theme_stylebox_override("focus", style)

	# BLACK ON YELLOW, WHITE ON BLUE. The palette spans L* 36 to 100 by design
	# (colours.json's ladder), so one fixed font colour is illegible on one end of it
	# whichever end it is picked for.
	var ink := Color.BLACK if colour.get_luminance() > 0.5 else Color.WHITE
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)

	button.pressed.connect(_on_swatch_pressed.bind(index))
	return button


func _on_swatch_pressed(index: int) -> void:
	close()
	colour_chosen.emit(index)


func _on_cancel() -> void:
	close()
	cancelled.emit()
