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
##   - ~~**File ▸ Open is 16.4a.** This screen can create and save, and cannot read back — so a
##     map is authored in one sitting until that lands.~~ ✅ **LANDED** — Open, and the Save As
##     that had to come with it. See `_open_overlay()`.
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

## The Open overlay (16.4a) and its parts.
var _open_overlay_panel: Control = null
var _open_list: ItemList = null
var _open_problems: Label = null
var _open_confirm: Button = null

## What `refresh_open_list()` last found, parallel to `_open_list`'s rows. The rows carry a
## label; **this carries the `dir`, which is the identity** — an `ItemList` index is the only
## thing a selection gives back and a label is not a path.
var _listed: Array[Dictionary] = []

var _sources := MapSources.new()

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


# ── File ▸ Open (PLAN.md 16.4a) ─────────────────────────────────────────────

## Show the Open list, freshly read off disk.
##
## **RE-READ ON EVERY OPEN, NOT CACHED.** The other half of this repo is a second Godot
## project and a pair of dev scripts that write maps, so the folder genuinely changes while
## the tool is running — an author who saves from the game and comes back to a stale list has
## no way to tell that from the map not having been written.
func open_dialog() -> void:
	refresh_open_list()
	if _open_overlay_panel != null:
		_open_overlay_panel.visible = true


func close_dialog() -> void:
	if _open_overlay_panel != null:
		# HIDDEN RATHER THAN EMPTIED. A `Control` over the canvas hit-tests first -- §6's row
		# about the four corner buttons that ate every minimap tap -- and `visible = false` is
		# what takes it out of hit testing as well as out of the picture.
		_open_overlay_panel.visible = false


## Every map the dialog can offer, in the order it lists them. Public for the tests and for
## `dev/` scripts: the list is the half of this row that can be checked without a mouse.
func listed_maps() -> Array[Dictionary]:
	return _listed


## Re-read the roots and rebuild the rows.
##
## ⚠️ **THE WARNINGS GO ON SCREEN, WHICH IS THE WHOLE OF 16.4a's THIRD REQUIREMENT.**
## `MapSources` collects a sentence per folder that holds a map pair it cannot read — a corrupt
## sidecar, or one from a format this build does not know. **A folder the author can see on
## disk and cannot see in this list is the one fault they cannot diagnose by looking**, so the
## panel says so rather than the list quietly being shorter.
func refresh_open_list() -> void:
	_listed = _sources.discover(_startup.root if _startup != null else null)
	if _open_list == null:
		return
	_open_list.clear()
	for row in _listed:
		var size: Vector2i = row["size"]
		_open_list.add_item("%s   —   %s   (%dx%d, %d players, %s)"
				% [row["name"], row["label"], size.x, size.y, row["players"],
				MapSources.source_name(int(row["source"]))])
	# ⚠️ **TWO FACTS, COMPUTED SEPARATELY** -- §6's row about the server browser's JOIN, which
	# shipped ENABLED WITH NOTHING TO JOIN because its `disabled` was set from "is there a
	# sentence to print". Whether anything is selected and whether there is anything worth
	# saying are different questions, and only the first one is always answerable.
	_refresh_open_confirm()
	_open_problems.text = "  " + _open_summary()
	_open_problems.add_theme_color_override("font_color",
			_BAD if not _sources.warnings.is_empty() else _TEXT)


## What the panel says under the list: the complaints if there are any, else where it looked.
static func _open_summary_for(count: int, warnings: Array[String], roots: Array[String]) -> String:
	if not warnings.is_empty():
		return "%d unreadable: %s" % [warnings.size(), _summarised(warnings)]
	if count == 0:
		# NAMES THE DIRECTORIES. "No maps found" is a sentence an author cannot act on; the
		# paths are what tell them whether the tool is looking where they saved.
		return "no maps in %s" % " or ".join(PackedStringArray(roots))
	return "%d maps in %d places" % [count, roots.size()]


func _open_summary() -> String:
	var paths: Array[String] = []
	for entry in _sources.roots(_startup.root if _startup != null else null):
		paths.append(str(entry["path"]))
	return _open_summary_for(_listed.size(), _sources.warnings, paths)


func _refresh_open_confirm() -> void:
	if _open_confirm != null:
		_open_confirm.disabled = _open_list == null \
				or _open_list.get_selected_items().is_empty()


## Open whichever row is selected. Nothing happens with no selection — the button is off.
func open_selected() -> Array[String]:
	if _open_list == null or _open_list.get_selected_items().is_empty():
		return ["nothing selected"] as Array[String]
	var at: int = _open_list.get_selected_items()[0]
	if at < 0 or at >= _listed.size():
		return ["that row is no longer in the list"] as Array[String]
	return open_map(str(_listed[at]["dir"]))


## Read `dir` and put it on the canvas. Problems back as sentences; empty means opened.
##
## ⚠️ **THE CANVAS IS NOT TOUCHED UNTIL THERE IS A MAP TO PUT ON IT**, which is 16.4a's card
## in one line: *"a partial load that silently shows an empty canvas over somebody's authored
## map is how a file gets overwritten with nothing."* A failure leaves the document, the name
## field and the canvas exactly as they were, keeps the dialog open so the row can be seen,
## and puts the reason on the notice line — where it outlives the next mouse move.
func open_map(dir_path: String) -> Array[String]:
	var problems: Array[String] = []
	var doc := MapDocument.open(dir_path, problems)
	if doc == null:
		_notice("OPEN FAILED — %s" % "; ".join(PackedStringArray(problems)), _BAD)
		if _open_problems != null:
			_open_problems.text = "  " + "; ".join(PackedStringArray(problems))
			_open_problems.add_theme_color_override("font_color", _BAD)
		return problems
	show_document(doc)
	close_dialog()
	# ⚠️ **IT NAMES THE DIRECTORY, AND THAT IS THE WARNING AS WELL AS THE CONFIRMATION.**
	# `save()` writes back to wherever a map was opened from, so after opening the shipped
	# campaign's scenario 4 the Save button replaces campaign content. The path on screen is
	# what makes that visible before it happens rather than afterwards in `git status`.
	_notice("OPENED ← %s" % doc.dir, _GOOD)
	return problems


# ── Save As ─────────────────────────────────────────────────────────────────

## Write the current map to `maps/<name>` as a new map, leaving its origin alone.
##
## **Open then Save replaces; Save As creates.** See `MapDocument.save_as()` for why Open
## made a second button necessary, and why a name that is already taken is refused rather
## than replaced.
func save_as() -> Array[String]:
	if _document == null:
		return ["nothing to save"] as Array[String]
	if not _startup.can_save():
		return [_startup.reason] as Array[String]
	_document.map_name = _name_field.text
	var problems := _document.save_as(maps_dir())
	_report_save(problems)
	return problems


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
	_report_save(problems)
	return problems


## Put the outcome of a save on the notice line. Shared by Save and Save As, because the three
## outcomes below are the same three whichever button was pressed.
##
## ⚠️ **THE RESULT GOES ON ITS OWN LINE AND STAYS THERE.** It used to go into the status
## line, which `_refresh_status()` rewrites on **every mouse move** — so the confirmation
## was gone before the author's hand left the button. The owner's playtest report was
## exactly this: *"i clicked save, not sure if it worked"*. An action's outcome must
## outlive the next hover.
func _report_save(problems: Array[String]) -> void:
	if not problems.is_empty():
		_notice("SAVE FAILED — %s" % "; ".join(PackedStringArray(problems)), _BAD)
	elif _document.warnings.is_empty():
		_notice("SAVED → %s" % _document.dir, _GOOD)
	else:
		# ⚠️ **THREE OUTCOMES, NOT TWO** (16.4b). "Saved" and "failed" cannot express the case
		# that actually bit the owner: the file wrote perfectly and the map was unplayable.
		# AMBER and the word SAVED together, because both halves are true and burying either
		# one is how the first authored map reached a match with a player owning nine things.
		_notice("SAVED, BUT LOOK — %s" % _summarised(_document.warnings), _WARN)
	_refresh_status()


## The warnings as one line, trimmed to what will actually fit on one.
##
## ⚠️ **CAPPED SINCE 16.4b's SECOND HALF, and the cap is not tidiness.** The audit produces one
## sentence per start; `MapValidator` produces one per *problem* per player, so an
## eight-player map that has been cut in half can hand this a dozen of them. `_notice_label`
## is a single unwrapped Label in a 1600 px window — past about 200 characters the text is
## simply not on screen, and **the sentence that gets clipped is not the one the author
## chooses.** Two and a count is legible; twelve is a blank end to a line.
##
## THE COUNT IS THE POINT of the tail, not decoration: "and 9 more" tells an author this is a
## broken map rather than a map with a rough edge, which is the difference between fixing it
## now and shipping it. The full list stays on `MapDocument.warnings` for anything that wants
## it — a log, a panel, or 16.4c.
static func _summarised(warnings: Array[String], keep := 2) -> String:
	var shown := warnings.slice(0, keep)
	var line := "; ".join(PackedStringArray(shown))
	if warnings.size() > shown.size():
		line += " (and %d more)" % (warnings.size() - shown.size())
	return line


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

	# ADDED LAST, SO IT IS ON TOP. A sibling later in the child order draws over the ones
	# before it, and this one has to cover the canvas rather than be laid out beside it --
	# hence a direct child of the screen and not a row in `rows`.
	add_child(_open_overlay())


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
	# directory does not need a browser; the name becomes the folder (`MapDocument.slug()`).
	# **OPEN IS THE ONE THAT GENUINELY NEEDS A LIST** and `MapSources`' header says why a
	# `FileDialog` is the wrong shape for it: a map is a directory of two files.
	row.add_child(_button("New", func() -> void: _new_map()))
	row.add_child(_button("Open", func() -> void: open_dialog()))
	row.add_child(_button("Fit", func() -> void: _canvas.fit_to_view()))
	row.add_child(_button("Save", func() -> void: save()))
	# **THE SECOND BUTTON OPEN MADE NECESSARY.** Save writes back to wherever a map came from,
	# which is what re-authoring means; this is the way out for an author who opened somebody
	# else's map. `MapDocument.save_as()` carries the argument.
	row.add_child(_button("Save As", func() -> void: save_as()))
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
		# ⚠️ **"FILE", NOT "SAVED TO", AND THE FOLDER'S PARENT WHEN IT IS NOT OURS.** Since
		# 16.4a a document's directory can be one this tool never wrote -- a scenario's, most
		# of all -- so "saved to" would claim something untrue of a map that was merely opened,
		# and the bare leaf `scenario_4` would not say which campaign's. This is the line that
		# tells an author what the Save button is about to replace.
		bits.append("file %s" % _short_file(_document.dir))
	if _document.dirty:
		bits.append("UNSAVED")
	if not _startup.can_save():
		# THE REASON, not a generic banner. Three different faults with three different
		# fixes, and the playtest that found this had the one message blaming the wrong one.
		bits.append("SAVING DISABLED — %s" % _startup.reason)
	_status.text = "  " + "   ".join(PackedStringArray(bits))
	_status.add_theme_color_override("font_color",
			_BAD if (not _startup.can_save() or seats < 2) else _GOOD)


## A document's directory, short enough for a status line and long enough to be unambiguous:
## the folder alone when it is one of ours in `maps/`, otherwise the folder and its parent.
func _short_file(dir_path: String) -> String:
	if dir_path.get_base_dir() == maps_dir():
		return dir_path.get_file()
	return "%s/%s" % [dir_path.get_base_dir().get_file(), dir_path.get_file()]


## The Open dialog: a dimmed screen, a list of maps, what is wrong with the ones missing
## from it, and two buttons (PLAN.md 16.4a).
##
## ## AN OVERLAY `Control` AND NOT A `Window` OR A `Popup`
##
## Three reasons, in the order they mattered:
##
##   - **a `Window` needs a real viewport, and half this tool's checks have none.** The suite
##     drives `Editor` outside the tree (`add_child` does not require one) and asserts
##     structure; a popup would answer nothing there, and `preview_editor` would be
##     photographing a second window the screenshot does not contain. §3's rule about a
##     `RefCounted` harness having no tree is the same rule one level up.
##   - **it is the shape the rest of the tool is built in** — every control here is code, on
##     `CampaignScreen`'s precedent, because the lists are data.
##   - **a popup steals focus and hands it back where it likes.** There is nothing to focus
##     here yet; there will be the day 16.3's search field exists, and 16.2a's card already
##     names that collision (`Ctrl+Z` swallowed by a focused `LineEdit`).
##
## ⚠️ **IT IS INVISIBLE UNTIL ASKED FOR, AND THAT IS A HIT-TEST FACT AS WELL AS A VISUAL ONE.**
## §6: a `Control` laid over the minimap swallowed every tap while looking absent, and the
## four corner buttons it hid were reported as unimplemented features. `visible = false` takes
## this out of hit testing too; a transparent backdrop would not.
func _open_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	# STOP, so a click meant for the dialog cannot land on the canvas behind it and paint a
	# tile the author never meant to touch. That is what makes this modal without a `Popup`.
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_open_overlay_panel = overlay

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", style)
	# CENTRED BY ANCHORS AND SIZED BY A MINIMUM, never by assigning `size`: §6's row about
	# `PRESET_FULL_RECT` applies to every non-equal-anchor Control, and an assigned size here
	# would be overridden after `_ready()` with a runtime warning and no visible cause.
	frame.set_anchors_preset(Control.PRESET_CENTER)
	# ⚠️ **THE WIDTH IS MEASURED OFF THE LONGEST REAL ROW, NOT CHOSEN.** At 900 the first shot
	# of this dialog clipped scenario 5 to `(112x112, 2 players, cam…` -- and an `ItemList`
	# clips rather than wrapping or scrolling sideways, so the part that goes is the tail,
	# which is where the figures are. The longest row on the machine today is scenario 5's
	# 53-character name plus its label and figures, ~115 characters at ~9 px in the fallback
	# font. 1200 fits it inside a 1600 px window with room for a longer name.
	#
	# **If a map with a much longer name clips again, this is the number to move** -- the
	# alternative, `clip_text` or a shorter format, is what §6's row about the server
	# browser's headings warns against: clipping is unconditional, not "shrink if crowded".
	frame.custom_minimum_size = Vector2(1200, 480)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var title := _label("Open a map")
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	_open_list = ItemList.new()
	_open_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open_list.allow_reselect = true
	_open_list.item_selected.connect(func(_at: int) -> void: _refresh_open_confirm())
	# DOUBLE-CLICK OPENS, because a list is a thing people double-click and a row that did
	# nothing would read as a broken list rather than as a missing shortcut.
	_open_list.item_activated.connect(func(_at: int) -> void: open_selected())
	column.add_child(_open_list)

	# UNDER THE LIST, NOT INSTEAD OF IT. The complaints are about folders that are NOT rows,
	# so they cannot be shown as rows -- 16.4a's third requirement is that they be shown at
	# all, and the list going quietly shorter is exactly what it is against.
	_open_problems = Label.new()
	_open_problems.add_theme_color_override("font_color", _TEXT)
	_open_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_open_problems)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_open_confirm = _button("Open", func() -> void: open_selected())
	# OFF UNTIL SOMETHING IS SELECTED, and that is the only thing it is off for -- see
	# `refresh_open_list()` on the two facts.
	_open_confirm.disabled = true
	buttons.add_child(_open_confirm)
	buttons.add_child(_button("Cancel", func() -> void: close_dialog()))
	column.add_child(buttons)
	return overlay


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
