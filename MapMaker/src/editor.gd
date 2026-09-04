## The editor screen (PLAN.md 16.2): a terrain brush, a start-placer, and Save.
##
## **THIS IS THE VERTICAL SLICE AND NOT THE FINISHED TOOL.** 16.2's job is to prove the format
## contract end to end — paint, save into repo-root `maps/`, then open it in the game through
## 16.0's picker and play it. Everything that makes it a comfortable editor is a later row and
## is deliberately absent:
##
##   - **undo is 16.2a**, and the whole of this screen's mutation already funnels through
##     `MapDocument`, which is what makes that row a stack of inverted calls rather than an
##     archaeology exercise;
##   - **the object palette is 16.3** — there is no way to place a house or a tree here, only
##     a start, and `StartLayout` explains why a start had to come with its base;
##   - **select / move / edit cursors are 16.4**. The only gesture is paint;
##   - **File ▸ Open is 16.4a.** This screen can create and save, and cannot read back — so a
##     map is authored in one sitting until that lands.
##
## Built in code rather than authored into a `.tscn`, on `CampaignScreen`'s and `HelpScreen`'s
## precedent: the brush row is one button per `SimMap.Terrain`, which is **data**, so a scene
## file could not hold the list even in principle without going stale the day an eighth
## terrain kind appears.
extends Control

## Where authored maps go. PLAN.md §16 decision 4: repo-root `maps/`, never inside `game/`
## (that is `res://`, read-only once exported) and never `user://` (installing content is the
## game's job).
const MAPS_SUBDIR := "../maps"

const _BG := Color(0.09, 0.09, 0.11)
const _PANEL := Color(0.13, 0.13, 0.16)
const _TEXT := Color(0.82, 0.82, 0.86)
const _GOOD := Color(0.55, 0.80, 0.55)
const _BAD := Color(0.95, 0.45, 0.40)

## Saved, and worth reading anyway (16.4b). A third colour because there is a third outcome --
## see `save()`.
const _WARN := Color(0.95, 0.78, 0.35)

enum Tool { PAINT, START }

var _canvas: MapCanvas = null
var _status: Label = null
var _notice_label: Label = null
var _name_field: LineEdit = null
var _width: SpinBox = null
var _height: SpinBox = null
var _player_picker: OptionButton = null
var _brush_buttons: Array[Button] = []
var _tool_buttons: Dictionary = {}

var _document: MapDocument = null
var _brush: int = SimMap.Terrain.GRASS
var _tool: Tool = Tool.PAINT

## What the tool needs before it can save. **Never null after `_ready()`** — see `_ready()`.
var _startup: Startup = null


## Hand over a `Startup` the boot screen has already computed, so the work is not repeated.
##
## ⚠️ **AN OPTIMISATION, NOT A PRECONDITION, AND IT USED TO BE THE OTHER WAY ROUND.** 16.2
## shipped requiring this call, the owner pointed `run/main_scene` at `Editor.tscn` — the
## obvious thing to do, because the editor is the tool — and the editor came up with no
## roster and Save refusing. `_ready()` now checks for itself if nobody has. See `Startup`.
func setup(startup: Startup) -> void:
	_startup = startup


func _ready() -> void:
	_build_ui()
	# SELF-SUFFICIENT. Launched from `Boot.tscn` this is already filled in; launched directly
	# -- as the main scene, from a preview, or from an exported build -- it is not, and doing
	# the work here is what makes both routes behave the same.
	if _startup == null:
		_startup = Startup.check()
	_new_map()


func document() -> MapDocument:
	return _document


func maps_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join(MAPS_SUBDIR).simplify_path()


# ── actions (public so a test can drive them without a mouse) ───────────────

## Start a new map at the size and player count in the toolbar.
func new_map() -> void:
	_new_map()


func _new_map() -> void:
	var wanted := Vector2i(int(_width.value), int(_height.value))
	_document = MapDocument.create(wanted, _name_field.text)
	_canvas.show_document(_document)
	_refresh_players()
	_refresh_status()


## Put an existing document on screen.
##
## The seam **16.4a (File ▸ Open) will use**, and the reason it exists now is that the canvas
## is the half of 16.2 no test can judge -- `dev/preview_editor.tscn` builds a map and hands
## it over so there is a screenshot to look at. Adding it later would have meant either a
## preview that could not show a real map or a private field poked from outside.
func show_document(doc: MapDocument) -> void:
	_document = doc
	_name_field.text = doc.map_name
	_width.set_value_no_signal(doc.data.size.x)
	_height.set_value_no_signal(doc.data.size.y)
	_canvas.show_document(doc)
	_refresh_players()
	_refresh_status()


func set_brush(kind: int) -> void:
	_brush = kind
	for i in _brush_buttons.size():
		_brush_buttons[i].button_pressed = (i == kind)


func set_tool(t: Tool) -> void:
	_tool = t
	for key in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = (int(key) == int(t))
	_refresh_status()


## Apply the current tool to `tile`. What the canvas's `painted` signal reaches.
func apply_tool(tile: Vector2i) -> void:
	if _document == null:
		return
	var changed := false
	match _tool:
		Tool.PAINT:
			changed = _document.paint(tile, _brush)
		Tool.START:
			changed = _document.place_start(_player_picker.get_selected_id(), tile)
			if changed:
				_refresh_players()
	if changed:
		# REDRAWN AND RE-REPORTED ONLY ON A REAL CHANGE, which is why `paint()` returns a
		# bool: a drag delivers the same tile dozens of times and repainting the canvas on
		# every one of them would make a stroke stutter on a big map.
		_canvas.queue_redraw()
		_refresh_status()


func save() -> Array[String]:
	if _document == null:
		return ["nothing to save"] as Array[String]
	if not _startup.can_save():
		# DECISION 3, ENFORCED AT THE ONE PLACE IT MATTERS. The guard's whole promise is that
		# a stale tool cannot WRITE -- refusing at the button rather than at startup means
		# the author can still look at a map while whatever is wrong is put right.
		#
		# ⚠️ **IT REPORTS THE REASON THAT ACTUALLY FIRED.** This used to say "the format
		# copies have drifted" whatever the fault, so a missing game project -- the thing
		# that really happened in the 2026-09-04 playtest -- was reported as a corrupt tool.
		return [_startup.reason] as Array[String]
	_document.map_name = _name_field.text
	var problems := _document.save(maps_dir())
	# ⚠️ **THE RESULT GOES ON ITS OWN LINE AND STAYS THERE.** It used to go into the status
	# line, which `_refresh_status()` rewrites on **every mouse move** — so the confirmation
	# was gone before the author's hand left the button. The owner's playtest report was
	# exactly this: *"i clicked save, not sure if it worked"*. An action's outcome must
	# outlive the next hover.
	if not problems.is_empty():
		_notice("SAVE FAILED — %s" % "; ".join(PackedStringArray(problems)), _BAD)
	elif _document.warnings.is_empty():
		_notice("SAVED → %s" % _document.dir, _GOOD)
	else:
		# ⚠️ **THREE OUTCOMES, NOT TWO** (16.4b). "Saved" and "failed" cannot express the case
		# that actually bit the owner: the file wrote perfectly and the map was unplayable.
		# AMBER and the word SAVED together, because both halves are true and burying either
		# one is how the first authored map reached a match with a player owning nine things.
		_notice("SAVED, BUT LOOK — %s" % "; ".join(PackedStringArray(_document.warnings)),
				_WARN)
	_refresh_status()
	return problems


## Say what just happened, and keep saying it until something else happens.
func _notice(text: String, colour: Color) -> void:
	if _notice_label == null:
		return
	_notice_label.text = "  " + text
	_notice_label.add_theme_color_override("font_color", colour)


# ── ui ──────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = _BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)

	rows.add_child(_file_row())
	rows.add_child(_tool_row())

	_canvas = MapCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.hovered.connect(_on_hovered)
	_canvas.painted.connect(apply_tool)
	# A wheel moves neither the pointer's tile nor the map, so without this the zoom in the
	# status line stays at whatever it was the last time something else refreshed it. Found
	# by reading a screenshot that said 0.23x while the canvas was at 1.20x.
	_canvas.view_changed.connect(func() -> void: _refresh_status())
	rows.add_child(_canvas)

	_status = Label.new()
	_status.add_theme_color_override("font_color", _TEXT)
	rows.add_child(_status)

	# THE ACTION LINE, below the live status. Two lines rather than one because they have
	# different lifetimes: the status describes the map *now* and is rewritten constantly,
	# while this holds the last thing the author DID until they do something else.
	_notice_label = Label.new()
	_notice_label.add_theme_color_override("font_color", _TEXT)
	rows.add_child(_notice_label)


func _file_row() -> Control:
	var box := _panel()
	var row := box.get_child(0) as HBoxContainer

	row.add_child(_label("Name"))
	_name_field = LineEdit.new()
	_name_field.text = "New Map"
	_name_field.custom_minimum_size = Vector2(220, 0)
	row.add_child(_name_field)

	row.add_child(_label("Size"))
	_width = _spin(MapDocument.MIN_SIZE, MapDocument.MAX_SIZE, 96)
	row.add_child(_width)
	row.add_child(_label("x"))
	_height = _spin(MapDocument.MIN_SIZE, MapDocument.MAX_SIZE, 96)
	row.add_child(_height)

	# NEW IS NOT A FILE DIALOG AND SAVE IS NOT EITHER. A tool for one person with one output
	# directory does not need a browser; the name becomes the folder (`MapDocument.slug()`)
	# and 16.4a adds Open, which is the row that genuinely needs a list.
	row.add_child(_button("New", func() -> void: _new_map()))
	row.add_child(_button("Fit", func() -> void: _canvas.fit_to_view()))
	row.add_child(_button("Save", func() -> void: save()))
	return box


func _tool_row() -> Control:
	var box := _panel()
	var row := box.get_child(0) as HBoxContainer

	row.add_child(_label("Paint"))
	# ONE BUTTON PER `SimMap.Terrain`, FROM THE ENUM. `sim_map.gd` is the authority on its own
	# terrain kinds and it is a hash-checked copy, so an eighth kind appears here with no
	# edit -- and a written-out list would be the drift `FormatGuard` exists to prevent.
	for kind in SimMap.Terrain.values():
		var b := Button.new()
		b.text = str(SimMap.Terrain.keys()[kind]).capitalize()
		b.toggle_mode = true
		b.add_theme_color_override("font_color",
				MapCanvas.TERRAIN_COLOURS.get(kind, Color.WHITE))
		b.pressed.connect(func() -> void: set_brush(kind))
		_brush_buttons.append(b)
		row.add_child(b)

	row.add_child(_separator())
	var start_button := Button.new()
	start_button.text = "Place start"
	start_button.toggle_mode = true
	start_button.pressed.connect(func() -> void: set_tool(Tool.START))
	_tool_buttons[int(Tool.START)] = start_button
	row.add_child(start_button)

	var paint_button := Button.new()
	paint_button.text = "Brush"
	paint_button.toggle_mode = true
	paint_button.pressed.connect(func() -> void: set_tool(Tool.PAINT))
	_tool_buttons[int(Tool.PAINT)] = paint_button
	row.add_child(paint_button)

	_player_picker = OptionButton.new()
	# EIGHT, matching the lobby's maximum. A ninth start is a map the game cannot seat.
	for p in range(1, 9):
		_player_picker.add_item("P%d" % p, p)
	row.add_child(_player_picker)
	row.add_child(_button("Clear start", func() -> void: _clear_selected_start()))

	set_brush(SimMap.Terrain.GRASS)
	set_tool(Tool.PAINT)
	return box


func _clear_selected_start() -> void:
	if _document == null:
		return
	_document.remove_start(_player_picker.get_selected_id())
	_refresh_players()
	_canvas.queue_redraw()
	_refresh_status()


func _refresh_players() -> void:
	if _document == null:
		return
	for i in _player_picker.item_count:
		var p := _player_picker.get_item_id(i)
		var placed := p <= _document.data.starts.size() \
				and _document.data.starts[p - 1].x >= 0
		# A TICK RATHER THAN A DISABLED ROW: which players already have a start is the thing
		# an author is checking, and a picker that hid the answer would need a second widget
		# to show it.
		_player_picker.set_item_text(i, "P%d%s" % [p, " ✓" if placed else ""])


func _on_hovered(_tile: Vector2i) -> void:
	_refresh_status()


func _refresh_status(problems: Array[String] = [] as Array[String]) -> void:
	if _status == null:
		return
	if not problems.is_empty():
		_status.text = "  " + "; ".join(PackedStringArray(problems))
		_status.add_theme_color_override("font_color", _BAD)
		return
	if _document == null:
		_status.text = "  no map"
		return
	# THERE IS NOT ALWAYS A POINTER TO ASK ABOUT. `get_local_mouse_position()` needs a
	# viewport, and this screen is built and driven outside a tree by the suite -- which
	# printed an engine error per test until this was guarded. Off-map is the honest answer.
	var hover := Vector2i(-1, -1)
	if _canvas.is_inside_tree():
		hover = _canvas.tile_at(_canvas.get_local_mouse_position())
	var seats := _document.seats()
	var bits: Array[String] = [
		"%d x %d" % [_document.data.size.x, _document.data.size.y],
		"%d entities" % _document.data.entities.size(),
		# SEATS, NOT STARTS. This is the number 16.0's `can_start()` enforces, and a map
		# showing "4 starts" that the lobby will only seat two players on is a map whose
		# author finds out in the game.
		"seats %d" % seats,
		"zoom %.2fx" % _canvas.zoom(),
	]
	if hover.x >= 0:
		bits.append("tile %d,%d — %s" % [hover.x, hover.y,
				str(SimMap.Terrain.keys()[_document.data.terrain_at(hover)]).capitalize()])
	if _tool == Tool.START:
		bits.append("click to place P%d's start" % _player_picker.get_selected_id())
	if not _document.dir.is_empty():
		bits.append("saved to %s" % _document.dir.get_file())
	if _document.dirty:
		bits.append("UNSAVED")
	if not _startup.can_save():
		# THE REASON, not a generic banner. Three different faults with three different
		# fixes, and the playtest that found this had the one message blaming the wrong one.
		bits.append("SAVING DISABLED — %s" % _startup.reason)
	_status.text = "  " + "   ".join(PackedStringArray(bits))
	_status.add_theme_color_override("font_color",
			_BAD if (not _startup.can_save() or seats < 2) else _GOOD)


# ── small builders ──────────────────────────────────────────────────────────

func _panel() -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	return box


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _TEXT)
	return l


func _spin(from: int, to: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = from
	s.max_value = to
	s.value = value
	# STEP OF 8, because a map's size is not a number anybody wants to arrive at one tile at
	# a time, and every size the game's own generator produces is a multiple of it.
	s.step = 8
	return s


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _separator() -> Control:
	var s := VSeparator.new()
	return s
