## The editor screen (PLAN.md 16.2): a terrain brush, a start-placer, and Save.
##
## **THIS IS THE VERTICAL SLICE AND NOT THE FINISHED TOOL.** 16.2's job is to prove the format
## contract end to end — paint, save into repo-root `maps/`, then open it in the game through
## 16.0's picker and play it. Everything that makes it a comfortable editor is a later row and
## is deliberately absent:
##
##   - ~~**undo is 16.2a**, and the whole of this screen's mutation already funnels through
##     `MapDocument`, which is what makes that row a stack of inverted calls rather than an
##     archaeology exercise;~~
##     ✅ **LANDED 2026-09-08.** Two buttons on the tool row, `Ctrl+Z` / `Ctrl+Y`, and a drag
##     that counts as one step — see `_input()` for why the shortcut is here and not on the
##     canvas, and `MapDocument.begin_stroke()` for why a stroke is one step;
##   - ~~**the object palette is 16.3** — there is no way to place a house or a tree here, only
##     a start, and `StartLayout` explains why a start had to come with its base;~~
##     ✅ **LANDED 2026-09-08.** `ObjectPalette` down the left, and with it the PLACE and ERASE
##     tools — see `apply_tool()` on why single-click placement came with the palette rather
##     than waiting for 16.4;
##   - **select / move / edit cursors are 16.4**, and so is DRAG to place a run of walls. What
##     landed with the palette is one click, one thing;
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

## Present but with nothing to say — the inspector with no selection (16.4). `Boot` and
## `ObjectPalette` both carry their own; a fourth copy of a grey is cheaper than a shared
## constant that has to live somewhere neither of them owns.
const _DIM := Color(0.55, 0.55, 0.60)

## ⚠️ **NEVER COMPARE A TOOL AGAINST A LITERAL INT.** `_tool_buttons` is keyed by the enum's
## integer, so every member's value is load-bearing outside this file — and `Tool.START` was
## **removed** on 2026-09-08 (see below), which renumbered everything after it. Anything that
## had written `set_tool(4)` would have silently changed tool. The tests and
## `dev/preview_editor.gd` all name `EDITOR.Tool.X` for that reason.
##
## ⛔ **THERE IS NO `Tool.START` ANY MORE, AND THAT IS THE OWNER'S RULING** (2026-09-08:
## *"can we add the start location as a building option ... we can use the same select and erase
## as normal buildings and remove duplicates"*). The start is `ObjectPalette.START_ID`, placed
## with PLACE and cleared with ERASE, so the toolbar lost a tool button, a player dropdown and a
## `Clear start` button — **three controls that existed for one thing that now needs none of
## them**, because the palette already has an Owner picker and the map already has an eraser.
## `apply_tool` branches on the id; `MapDocument.place_start`/`remove_start` are untouched.
##
## 📝 **THERE IS NO `Tool.EDIT` EITHER, AND 16.4's "THREE CURSORS" IS STILL SATISFIED.** Editing
## an entity is not a gesture on the canvas: a third mode whose click did what SELECT's does is a
## mode an author cannot tell they are in, and the two would have to stay in step about what a
## click means. So select and move are cursors, and **the edit is the inspector row** —
## `_entity_row()`, which acts on whatever is selected and is reachable from either cursor.
enum Tool { PAINT, PLACE, ERASE, SELECT, MOVE }

var _canvas: MapCanvas = null
var _palette: ObjectPalette = null

## The icon reader, handed to the palette. Held here because it caches parsed atlases and
## decoded pages, and one per editor is one decode of each page rather than one per redraw.
var _icons := IconAtlas.new()
var _status: Label = null
var _notice_label: Label = null
var _name_field: LineEdit = null
var _width: SpinBox = null
var _height: SpinBox = null
var _tool_buttons: Dictionary = {}

## Undo and redo (16.2a). Held because their `disabled` and their tooltips both track the
## stack, and `_refresh_undo()` is the one place that does it.
var _undo_button: Button = null
var _redo_button: Button = null

## The inspector — 16.4's "edit" (see `Tool`). Its controls act on `_document.selected`.
var _entity_label: Label = null
var _entity_owner: OptionButton = null
var _entity_size: OptionButton = null
var _entity_size_label: Label = null

## True while the inspector is being filled FROM the selection, so the writes it makes to its
## own controls do not come back as edits.
##
## ⚠️ **WITHOUT THIS, SELECTING A GAIA TREE REASSIGNS IT.** Setting `OptionButton.selected`
## emits `item_selected`, so filling the owner picker from the entity fires the handler that
## writes the owner back — harmless when they agree and an actual edit when the control was
## showing something else, which it always is on the first click. 16.3's row records the mirror
## image of this trap (a picker showing Gaia while `selection()` said player 1); this is what it
## costs to fix that by assigning the control unconditionally.
var _filling_inspector := false

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
	# THE ROSTER IS ALREADY LOADED BY `Startup` -- this reads `visuals.json` and `colours.json`,
	# which nothing before 16.3 needed. **Its failure is never fatal**: a clean clone has no
	# staged atlases at all and the palette draws lettered plates, which is 16.3's own rule.
	_icons.load_from(_startup.root)
	_palette.setup(_icons)
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
	_refresh_inspector()                  # see `show_document()`
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
	# A DIFFERENT MAP HAS A DIFFERENT ENTITY LIST, so an inspector still describing the last
	# map's selection would be showing a thing that is not on screen. `MapDocument.selected`
	# starts at -1 on a created or opened document, so this reads that rather than clearing it.
	_refresh_inspector()
	_refresh_status()


# ── undo (PLAN.md 16.2a) ────────────────────────────────────────────────────

## `Ctrl+Z`, `Ctrl+Y` and `Ctrl+Shift+Z`.
##
## ⚠️ **`_input` ON THE SCREEN — NOT `_gui_input` ON THE CANVAS, NOT `_shortcut_input`, NOT
## `Button.shortcut`.** 16.2a's card names the trap (*"the palette's search `LineEdit` takes
## focus and swallows it"*) and Godot's input order is the reason none of the other three work:
## `Node._input` runs FIRST, before the GUI pass; `Control._gui_input` is the GUI pass; and
## `_shortcut_input` — which is what a `Button.shortcut` is dispatched from — runs after it.
## `LineEdit` handles `Ctrl+Z` itself as its own text undo, so anything at or after the GUI
## pass gets nothing at all while that field has focus. Same shape as the HUD `Control` that
## ate three build buttons (PLAN.md §8): the handler was fine and never ran.
##
## ⚠️ **AND THEN IT HANDS `Ctrl+Z` BACK when a text field really does have focus**, which is
## the other half of being right rather than merely winning. The name field holds the map's
## name and the size boxes hold numbers; an author mid-word in one of them means *undo my
## typing*, and stealing it would make those fields feel broken while the map jumped behind
## them. Clicking the canvas grabs focus (`MapCanvas._ready()` sets `FOCUS_CLICK`), so touching
## the map is what gives the shortcut back to the map — there is no extra rule to remember.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	# ECHOES DROPPED: a held Ctrl+Z would otherwise unwind the whole stack in a second, which
	# is a keyboard repeat rate deciding how much work comes back.
	if key == null or not key.pressed or key.echo or not key.ctrl_pressed:
		return
	# THE OPEN DIALOG IS MODAL, and that has to include the keyboard. Undoing behind a dialog
	# would change the map the author is about to replace with a different one.
	if _open_overlay_panel != null and _open_overlay_panel.visible:
		return
	if _typing():
		return
	match key.keycode:
		KEY_Z:
			# CTRL+SHIFT+Z IS REDO, the convention Ctrl+Y is the other half of. Both, because
			# which one a person reaches for depends on what else they use.
			if key.shift_pressed:
				redo()
			else:
				undo()
		KEY_Y:
			redo()
		_:
			return
	if is_inside_tree():
		# CONSUMED, so the keystroke does not also reach anything behind this screen.
		get_viewport().set_input_as_handled()


## Whether a text field has the keyboard.
##
## A `SpinBox` holds a `LineEdit` as a child and that child is what takes focus, so this one
## test covers the name field, the palette's search box and both size boxes.
func _typing() -> bool:
	if not is_inside_tree():
		return false
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## Take the last act back.
func undo() -> void:
	if _document == null:
		return
	var what := _document.undo()
	if what.is_empty():
		# ⚠️ **A KEYSTROKE THAT DOES NOTHING LOOKS LIKE A BROKEN TOOL**, and the bottom of the
		# stack is exactly where an author presses hardest. Same argument as the `WILL NOT FIT`
		# notice on a refused placement.
		_notice("NOTHING TO UNDO", _TEXT)
		return
	_after_history("UNDID", what)


func redo() -> void:
	if _document == null:
		return
	var what := _document.redo()
	if what.is_empty():
		_notice("NOTHING TO REDO", _TEXT)
		return
	_after_history("REDID", what)


## Everything on screen that an undo can have changed.
##
## 📝 **THIS USED TO REFRESH THE PLAYER PICKER TOO, and the note is worth keeping because the
## fault it describes is still live.** Undoing a `place_start` takes the start off the map, and
## the dropdown's ✓ marks were the only place an author could see which players had one — so a
## redraw without them showed P1 ticked over a map with no P1 start. The dropdown went with the
## owner's 2026-09-08 ruling and **the information moved to the status line**, which
## `_refresh_status()` below rewrites unconditionally, so the same staleness cannot occur: there
## is no cached copy left to forget.
func _after_history(verb: String, what: String) -> void:
	_canvas.queue_redraw()
	# ⚠️ **AND THE INSPECTOR, because `MapDocument.undo()` CLEARS THE SELECTION** — a step
	# replaces the entity list from a snapshot and an index into the old one names something
	# else. Without this refresh the panel goes on describing an entity the author can no longer
	# see outlined, and its owner dropdown would be live over nothing.
	_canvas.redraw_overlay()
	_refresh_inspector()
	_notice("%s — %s" % [verb, what], _GOOD)
	_refresh_status()


## The two buttons, from the two stacks.
##
## ⚠️ **CALLED FROM `_refresh_status()` RATHER THAN FROM EACH MUTATION SITE**, deliberately.
## There are nine places that change the stack — four tools, Clear start, New, Open, Save,
## and undo itself — and the tenth would be the one that got forgotten, leaving a button
## enabled with nothing behind it. That is §6's row about the server browser's JOIN, and the
## fix that actually holds is one refresh point on the path everything already goes through.
## `BaseButton.set_disabled` ignores a write that changes nothing, so the hover path pays
## almost nothing for it.
func _refresh_undo() -> void:
	if _undo_button == null or _redo_button == null:
		return
	var history: UndoStack = _document.history if _document != null else null
	# ⚠️ **`disabled` COMES FROM `can_undo()` AND THE TOOLTIP FROM THE LABEL — never one from
	# the other.** Setting the button's state from "is there a sentence to print" is verbatim
	# how the server browser's JOIN shipped enabled with nothing to join (§6). The two happen
	# to agree today, and the point is that the button does not depend on their agreeing.
	_undo_button.disabled = history == null or not history.can_undo()
	_redo_button.disabled = history == null or not history.can_redo()
	_undo_button.tooltip_text = _shortcut_hint("Ctrl+Z", "undo",
			history.undo_label() if history != null else "")
	_redo_button.tooltip_text = _shortcut_hint("Ctrl+Y", "redo",
			history.redo_label() if history != null else "")


static func _shortcut_hint(keys: String, verb: String, what: String) -> String:
	if what.is_empty():
		return "%s — nothing to %s" % [keys, verb]
	return "%s — %s %s" % [keys, verb, what]


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


## The terrain the PAINT tool writes.
##
## Still a public seam with the toolbar's buttons gone, and for two reasons: the palette's
## Terrain tab calls it, and `dev/author_map.tscn` and the tests drive the brush without a
## mouse. What it no longer does is light a row of buttons — see `_tool_row()`.
func set_brush(kind: int) -> void:
	_brush = kind


## The palette's Terrain tab chose a kind: take it as the brush AND arm the brush tool.
##
## **BOTH, because a tab that arms nothing reads as broken.** An author who clicks Terrain and
## then Water has said what they want twice; making them also find the Brush button is a third
## click for a decision already made.
func _on_terrain_picked(kind: int) -> void:
	set_brush(kind)
	set_tool(Tool.PAINT)


## Something was chosen off the palette's grid: arm PLACE.
##
## ⚠️ **ONLY FROM `entry_picked`, NEVER FROM `selection_changed`.** The palette's header has
## the argument: the second signal also fires when the owner, tint or size class moves, so
## arming a tool from it would silently swap the tool out from under an author who had pressed
## `Place start` and then changed the owner.
func _on_entry_picked(_def_id: StringName) -> void:
	set_tool(Tool.PLACE)


func set_tool(t: Tool) -> void:
	_tool = t
	for key in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = (int(key) == int(t))
	_refresh_status()


## Apply the current tool to `tile`. What the canvas's `painted` signal reaches.
##
## ## WHY PLACE AND ERASE CAME WITH THE PALETTE RATHER THAN WITH 16.4
##
## PLAN.md 16.4 owns *"select / move / edit, click to place, drag to place walls"*, and three
## of those four are still 16.4's. **The one click that puts one thing down came here because
## without it 16.3 delivers a panel that cannot do anything** — `selection()` would have had no
## consumer, and 16.4 would have had to build `MapDocument.add_entity` anyway to acquire one.
## An author handed a palette that only highlights things has been handed a picture of a tool.
##
## What is deliberately NOT here, so 16.4 is still a row: no drag (a stroke of walls needs
## `WallPlan`'s axis rule), no select, no move, no per-entity edit.
func apply_tool(tile: Vector2i) -> void:
	if _document == null:
		return
	var changed := false
	match _tool:
		Tool.PAINT:
			changed = _document.paint(tile, _brush)
		Tool.PLACE:
			var pick := _palette.selection()
			if pick.is_empty():
				# NOTHING SELECTED IS NOT A FAILURE TO REPORT ON EVERY CLICK. The status line
				# already says "nothing selected"; a notice per click would bury whatever the
				# author last actually did.
				return
			# THE START IS A PALETTE ENTRY AND NOT A DEF (owner, 2026-09-08). `ObjectPalette.START_ID`
			# says why the branch is here rather than inside `add_entity`: placing a start runs
			# `StartLayout` and writes a field the entity list does not have.
			if StringName(pick["def_id"]) == ObjectPalette.START_ID:
				changed = _place_start_from_palette(int(pick["player"]), tile)
			else:
				# THE AXIS RIDES WITH THE SELECTION (16.4c). `ObjectPalette.selection()` has
				# already split the variant suffix off, so `def_id` is a real def and `axis` is
				# `MapData.AXIS_NONE` for everything that has no orientation.
				changed = _document.add_entity(pick["def_id"], int(pick["player"]), tile,
						int(pick["size_class"]), int(pick.get("axis", MapData.AXIS_NONE)))
			if not changed and StringName(pick["def_id"]) != ObjectPalette.START_ID:
				# ⚠️ **THE REFUSAL IS SAID OUT LOUD, because a click that does nothing looks
				# like a broken tool.** `add_entity` refuses two things and the author can see
				# neither: a footprint running off the map (the origin tile is plainly on it)
				# and an overlap with a footprint that may be ten tiles wide.
				_notice("WILL NOT FIT — %s needs clear ground at %d,%d"
						% [GameDataRegistry.display_name(pick["def_id"]), tile.x, tile.y], _WARN)
		Tool.ERASE:
			# ⚠️ **A START IS CHECKED FOR FIRST, because `remove_entity_at()` REFUSES its
			# cluster** — deliberately, so an author cannot pick one villager out of a start and
			# leave a `StartLayout.ORIGIN_KEY` tag describing something that is no longer there.
			# So without this branch, erasing a base would do nothing at all, and the owner's
			# ruling retired the `Clear start` button that used to be the only way.
			var whose := _document.start_owner_at(tile)
			if whose > 0:
				_document.remove_start(whose)
				# **THE WHOLE START GOES, AND IT IS SAID LOUDLY.** A click that deletes a town
				# centre, five villagers, a scout and a ring of resources is not a click whose
				# result should have to be inferred from the entity count.
				_notice("CLEARED P%d's START — the base and its opening went with it"
						% whose, _WARN)
				changed = true
			else:
				changed = _document.remove_entity_at(tile) > 0
		Tool.SELECT:
			# NOT A CHANGE TO THE MAP, so it does not go down the `changed` path: the expensive
			# layer is not invalidated, `dirty` is untouched, and Ctrl+Z reaches past it to the
			# last real act. Only the cheap overlay and the inspector are refreshed.
			if _document.select_at(tile):
				_after_selection_changed()
		Tool.MOVE:
			changed = _move_to(tile)
	if changed:
		# REDRAWN AND RE-REPORTED ONLY ON A REAL CHANGE, which is why `paint()` returns a
		# bool: a drag delivers the same tile dozens of times and repainting the canvas on
		# every one of them would make a stroke stutter on a big map.
		_canvas.queue_redraw()
		# ⚠️ **AND THE OVERLAY AND THE INSPECTOR, because two of these tools change the
		# SELECTION as a side effect.** A move edits the selected entity's tile, so its outline
		# has to follow; an erase makes `MapDocument` clear the selection outright, so the panel
		# has to stop describing something that is gone. Refreshed on the `changed` path rather
		# than in each branch, for `_refresh_undo()`'s reason: nine mutation sites and the tenth
		# is the one that gets forgotten.
		_canvas.redraw_overlay()
		_refresh_inspector()
		_refresh_status()


## Place a start for the palette's current owner. True when one landed.
##
## ⚠️ **GAIA IS A LEGITIMATE OWNER IN THAT PICKER AND IS NOT A PLAYER.** The palette defaults to
## Gaia on the Resource tab and every node on every map is gaia's — so an author who places a
## forest and then picks the start tile arrives here with owner 0, `place_start()` refuses it
## (`player < 1`), and without this sentence the click would do nothing with no explanation.
## **That is the most likely way to meet this feature for the first time**, which is why it gets
## the loudest message rather than a shrug.
func _place_start_from_palette(player: int, tile: Vector2i) -> bool:
	if player < 1:
		_notice("A START NEEDS A PLAYER — pick P1..P8 in the palette's Owner box, not Gaia",
				_WARN)
		return false
	if not _document.place_start(player, tile):
		_notice("WILL NOT PLACE P%d's START at %d,%d — the base needs room there"
				% [player, tile.x, tile.y], _WARN)
		return false
	# ⚠️ **RE-PLACING A START MOVES IT RATHER THAN DOUBLING IT** — `place_start()` clears whatever
	# the player had first, which is what made `StartLayout.ORIGIN_KEY` necessary. Worth saying,
	# because the alternative reading of a second click is "now I have two bases".
	_notice("PLACED P%d's START — town centre, villagers, scout and an opening ring"
			% player, _GOOD)
	return true


# ── the move drag (PLAN.md 16.4) ────────────────────────────────────────────

## Where the pointer was when the MOVE gesture began, and the offset from it to the grabbed
## entity's origin. `_grab_offset` is the whole reason a big building does not jump.
##
## ⚠️ **WITHOUT THE OFFSET, GRABBING A 10x10 TOWN CENTRE BY ITS MIDDLE TELEPORTS IT.** The
## entity's `tile` is its footprint's ORIGIN, so moving it to the tile under the pointer puts
## the corner where the finger is — the building leaps five tiles up-left on the first pixel of
## the drag. That is also the shape of the note the owner left on this row (*"it places the
## building using top right not centre"*) met from the other side, and it is worth seeing that
## the two are the same fact: the origin is not where the author is pointing.
var _grab_offset := Vector2i.ZERO

## True once a MOVE press has grabbed something, so the tiles that follow are a drag and not a
## fresh grab. Cleared on release.
var _grabbing := false

## The origin the pointer last ASKED for, whether or not the entity could go there.
##
## ⚠️ **WITHOUT THIS A DRAG COLLIDES WITH ITS OWN PATH INSTEAD OF WITH ITS DESTINATION**, and
## `dev/preview_editor.tscn` is what found it: a nine-tile drag of a town centre advanced **two
## tiles** and stopped, because the villagers of its own start were in the way — every
## intermediate sample was refused, and the perfectly clear ground beyond them was unreachable.
## An author would read that as the tool refusing a move that is plainly legal.
##
## So the intent is remembered and **retried once when the button comes up** (`_finish_move()`).
## Live feedback keeps working — the building follows the pointer as far as it legally can — and
## the destination is judged on its own merits. It is still one undo step, because the retry
## happens before the stroke closes.
var _grab_intent := Vector2i(-1, -1)


## One sample of a MOVE gesture. True when the map changed.
##
## **THE FIRST SAMPLE GRABS AND THE REST DRAG.** `MapCanvas` reports a press and then a tile per
## motion sample (interpolated, so a fast drag is continuous), and none of them says which was
## the press — `_grabbing` is what distinguishes them, cleared by `stroke_ended`.
##
## ⚠️ **A GRAB ALSO SELECTS**, which is not a convenience: MOVE with nothing selected would be a
## tool that does nothing on its first click, and an author cannot tell that from a broken tool.
## Pressing empty ground clears the selection, the same as SELECT.
func _move_to(tile: Vector2i) -> bool:
	if not _grabbing:
		_grabbing = true
		var changed_selection := _document.select_at(tile)
		var e := _document.selected_entity()
		# THE OFFSET FROM THE POINTER TO THE ORIGIN, measured once at the press. Re-measuring it
		# per sample would make it zero after the first move and the building would slide out
		# from under the pointer.
		_grab_offset = Vector2i.ZERO if e.is_empty() \
				else (e.get("tile", Vector2i.ZERO) as Vector2i) - tile
		if changed_selection:
			_after_selection_changed()
		# NOTHING MOVES ON THE PRESS ITSELF. A click without a drag should select, not nudge.
		return false
	if _document.selected < 0:
		return false
	# REMEMBERED WHETHER OR NOT IT WORKS -- see `_grab_intent`: this is the tile `_finish_move()`
	# retries, and it is the whole reason a drag can cross an obstacle.
	_grab_intent = tile + _grab_offset
	return _try_move(_grab_intent)


## Apply one move and report it. True when the map changed.
func _try_move(origin: Vector2i) -> bool:
	if not _document.move_selected(origin):
		return false
	_notice("MOVED — %s to %d,%d" % [
			GameDataRegistry.display_name(_document.selected_entity().get("def_id", &"")),
			origin.x, origin.y], _GOOD)
	return true


## The release: one last attempt at wherever the pointer actually ended up.
##
## ⚠️ **CALLED BEFORE `MapDocument.end_stroke()`, WHICH IS THE ONLY ORDER THAT WORKS.**
## `end_stroke()` seals the gesture's undo step, so a move applied after it would land on the
## stack as a SECOND step — and taking the drag back would then need two Ctrl+Z presses, which
## is 16.2a's whole complaint. See `_grab_intent` for why the retry exists at all.
func _finish_move() -> void:
	if not _grabbing or _document == null or _document.selected < 0:
		return
	if _grab_intent.x < 0:
		return
	var e := _document.selected_entity()
	if not e.is_empty() and e.get("tile", Vector2i.ZERO) != _grab_intent:
		if not _try_move(_grab_intent):
			# ⚠️ **SAID OUT LOUD.** The entity is sitting somewhere along the path rather than
			# where the author let go, and a building that stops short with no explanation is
			# `apply_tool`'s refused placement seen mid-gesture.
			_notice("WILL NOT FIT — %s cannot go to %d,%d" % [
					GameDataRegistry.display_name(e.get("def_id", &"")),
					_grab_intent.x, _grab_intent.y], _WARN)
		_canvas.queue_redraw()
		_canvas.redraw_overlay()
		_refresh_inspector()
	_grab_intent = Vector2i(-1, -1)


## Everything on screen that a change of selection affects.
##
## The overlay and the inspector, and **not** the map layer: see `apply_tool`'s SELECT branch.
func _after_selection_changed() -> void:
	_canvas.redraw_overlay()
	_refresh_inspector()
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
	rows.add_child(_entity_row())

	# THE PALETTE AND THE CANVAS SHARE A ROW (16.3). The canvas expands and the palette does
	# not, so the map takes every pixel the panel does not want -- and `MapCanvas` already sets
	# `clip_contents`, which is what stops a panned map painting over the panel the way it once
	# painted over the toolbar.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	rows.add_child(body)

	_palette = ObjectPalette.new()
	_palette.terrain_picked.connect(_on_terrain_picked)
	_palette.entry_picked.connect(_on_entry_picked)
	# THE LABEL ONLY. Arming a tool from this would mean changing the owner re-armed PLACE
	# over whatever the author had actually pressed -- the palette's own header on why there
	# are two signals.
	_palette.selection_changed.connect(func() -> void: _refresh_status())
	body.add_child(_palette)

	_canvas = MapCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.hovered.connect(_on_hovered)
	_canvas.painted.connect(apply_tool)
	# A DRAG IS ONE UNDO STEP (16.2a). `MapDocument.begin_stroke()` carries the argument; the
	# canvas reports the two ends of the gesture and nothing about what it meant.
	_canvas.stroke_began.connect(func() -> void:
			if _document != null:
				_document.begin_stroke())
	_canvas.stroke_ended.connect(func() -> void:
			# ⚠️ **BEFORE `end_stroke()`, WHICH SEALS THE UNDO STEP.** `_finish_move()` retries
			# the destination the pointer ended on, and a move applied after the seal would be a
			# second step -- two Ctrl+Z presses for one drag.
			if _tool == Tool.MOVE:
				_finish_move()
			if _document != null:
				_document.end_stroke()
			# ⚠️ **THE GRAB IS RELEASED HERE AND NOWHERE ELSE.** `MapCanvas._button` guarantees
			# this fires even when the pointer has left the control -- the viewport keeps
			# sending to whoever took the press -- so a drag that ends off the map still lets
			# go. A `_grabbing` left true would make the author's next click a DRAG of the old
			# entity instead of a grab of a new one.
			_grabbing = false
			# THE BUTTONS ONLY COME ALIVE HERE for a drag, because nothing is on the stack until
			# the stroke closes -- so without this refresh Undo stays greyed out until the next
			# hover happens to run `_refresh_status()`.
			_refresh_status())
	# A wheel moves neither the pointer's tile nor the map, so without this the zoom in the
	# status line stays at whatever it was the last time something else refreshed it. Found
	# by reading a screenshot that said 0.23x while the canvas was at 1.20x.
	_canvas.view_changed.connect(func() -> void: _refresh_status())
	body.add_child(_canvas)

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

	# ⚠️ **THE ROW OF SEVEN TERRAIN BUTTONS THAT USED TO BE HERE IS GONE, AND IT WAS DELETED
	# RATHER THAN KEPT ALONGSIDE THE PALETTE.** 16.3's row makes Terrain a palette category, so
	# for about an hour there were two controls for one fact — and the sync was ONE WAY: the
	# palette's terrain tab called `set_brush()` and lit the toolbar, while a toolbar press
	# changed the brush and left the palette highlighting something else. That is §6's row
	# about two rows built from the same constants ("mirroring a layout is not sharing one")
	# with a selection instead of a width, and the cheap version of the fix is to have one
	# control. `set_brush` survives as the seam both the palette and the tests drive.
	#
	# What was lost is worth naming: the toolbar's buttons were NAMED and colour-coded and
	# always visible, where the palette's are swatches behind a tab. The palette's tiles carry
	# the same name and the same `MapCanvas.TERRAIN_COLOURS` swatch, so nothing about the
	# information went — only the always-visible part, and a tab is one click.

	# ⚠️ **BUTTONS AS WELL AS A SHORTCUT, and the buttons are the half that matters more.** A
	# `Ctrl+Z` with nothing on screen is undiscoverable -- an author who does not know the tool
	# has undo behaves like an author who has none, which is the whole failure 16.2a is about --
	# and a disabled button is also the only *visible* statement that there is nothing to take
	# back. They carry the shortcut in their tooltip rather than in their label, so the row
	# does not grow by forty pixels of parenthesis.
	_undo_button = _button("Undo", func() -> void: undo())
	_redo_button = _button("Redo", func() -> void: redo())
	row.add_child(_undo_button)
	row.add_child(_redo_button)
	row.add_child(_separator())

	# ONE BUTTON PER TOOL, from the enum's own members, so a fifth tool cannot be added
	# without a button appearing -- the same argument as the brush row above, which builds
	# itself from `SimMap.Terrain`.
	for entry in [
		{"tool": Tool.PAINT, "label": "Brush"},
		{"tool": Tool.PLACE, "label": "Place"},
		{"tool": Tool.ERASE, "label": "Erase"},
		# 16.4's two cursors. **Select before Move**, because that is the order they are used in
		# and a toolbar is read left to right.
		{"tool": Tool.SELECT, "label": "Select"},
		{"tool": Tool.MOVE, "label": "Move"},
	]:
		var b := Button.new()
		b.text = str(entry["label"])
		# ⚠️ **THE ICON IS BESIDE THE WORD AND DOES NOT REPLACE IT.** The owner supplied four
		# placeholder glyphs; an icon-only toolbar would be prettier and less usable, which is
		# 16.2a's own argument about `Ctrl+Z` — *"a shortcut nobody can see is a feature nobody
		# uses"* — applied to a picture instead of a keystroke. `ToolIcons` draws them.
		b.icon = ToolIcons.for_tool(int(entry["tool"]))
		b.toggle_mode = true
		var t: int = int(entry["tool"])
		b.pressed.connect(func() -> void: set_tool(t as Tool))
		_tool_buttons[t] = b
		row.add_child(b)

	# ⛔ **THE PLAYER DROPDOWN AND `Clear start` USED TO BE HERE AND ARE GONE** (owner,
	# 2026-09-08). They existed solely for `Tool.START`: the picker said whose start the next
	# click would place, and the button was the only way to take one back. The start is now
	# `ObjectPalette.START_ID`, so the palette's **Owner** box says whose and the **eraser** takes
	# it back — which is the deduplication the owner asked for. §6's rule about two controls for
	# one fact, met for the third time in this tool: the toolbar's seven terrain buttons went the
	# same way when Terrain became a palette tab.
	#
	# ⚠️ **WHAT THE PICKER ALSO CARRIED WAS THE ✓ MARKS — which players already have a start —
	# and that is real information the dropdown was the only home for.** It is now on the status
	# line (`_starts_sentence()`), where it is visible without opening anything rather than
	# visible only while the dropdown is down.

	set_brush(SimMap.Terrain.GRASS)
	set_tool(Tool.PAINT)
	return box


## The inspector: 16.4's "edit", acting on whatever is selected.
##
## ## IT IS ALWAYS PRESENT AND SAYS SO WHEN THERE IS NOTHING
##
## The obvious design is a row that appears when something is selected, and it is worse for two
## reasons. **A row that appears resizes the canvas**, so the map jumps and re-culls on every
## first click — and an author who has never selected anything would never see that the tool can
## edit an entity at all. So it holds a sentence instead, and the controls are disabled.
##
## ## WHAT IT CAN EDIT IS EXACTLY WHAT THE FORMAT HOLDS, AND NOT ONE FIELD MORE
##
## ⚠️ An entity is `{def_id, player, tile, size_class}`. So: the owner, and the size class. **A
## name, hit points, attack or speed are 16.7's** — *"the expensive row, and the only one with
## real sim cost"* — and offering them here would let an author type a hero's name into a field
## `MapFile` silently drops. That is 16.3's Area-tab argument applied to a panel instead of a
## tab: *work lost behind a successful save* is the worst of the available failures.
##
## The tile is shown and is not editable here: dragging is what moves a thing, and a pair of
## spin boxes for x and y would be a second way to do it that has to agree with the first.
func _entity_row() -> Control:
	var box := _panel()
	var row := box.get_child(0) as HBoxContainer

	_entity_label = Label.new()
	_entity_label.add_theme_color_override("font_color", _TEXT)
	# ⚠️ **A FIXED MINIMUM WIDTH, because this label's TEXT is what changes width.** Without it
	# every control to the right slides as the selection changes — "nothing selected" is shorter
	# than "Town Center at 41,38" — and a dropdown that moves under the pointer between clicks is
	# §6's row about two controls for one fact seen as a moving target.
	_entity_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(_entity_label)

	row.add_child(_label("Owner"))
	_entity_owner = OptionButton.new()
	# GAIA FIRST AND AS AN ID OF ITS OWN. Every resource node, the dragon and her nest are
	# gaia's, so 0 is a real owner here rather than "none" -- `MapDocument.set_selected_owner()`
	# says the same thing from the other end.
	#
	# ⚠️ **IDS ARE THE PLAYER NUMBER, WHICH IS SAFE ONLY BECAUSE GAIA IS 0 AND NOT -1.** 16.3's
	# palette had to store colour + 1 for exactly this reason: `add_item(text, -1)` means "use
	# the index as the id", so an id of -1 is never stored and `get_item_index(-1)` finds
	# nothing. Nothing here needs a negative id, so nothing here needs the offset.
	_entity_owner.add_item("Gaia", 0)
	for p in range(1, 9):
		_entity_owner.add_item("P%d" % p, p)
	_entity_owner.item_selected.connect(_on_inspector_owner_chosen)
	row.add_child(_entity_owner)

	# SIZE IS THE RESOURCE AXIS AND ONLY THE RESOURCE AXIS (16.3's row): a small gold mine and a
	# large one are one def at two sizes. The label is hidden with the control so a disabled box
	# does not sit beside a live caption.
	_entity_size_label = _label("Size")
	row.add_child(_entity_size_label)
	_entity_size = OptionButton.new()
	# ⚠️ **`ObjectPalette.SIZE_LABELS` AND NOT A SPIN BOX OF 0..2.** The palette already names
	# these three Small/Medium/Large, and a panel that called the same field by its index would
	# be two vocabularies for one fact -- §6's "mirroring a layout is not sharing one" with a
	# label instead of a width. The constant was made public for this; there is one list.
	for i in ObjectPalette.SIZE_LABELS.size():
		_entity_size.add_item(str(ObjectPalette.SIZE_LABELS[i]), i)
	_entity_size.item_selected.connect(_on_inspector_size_chosen)
	row.add_child(_entity_size)

	_refresh_inspector()
	return box


## Fill the inspector from the selection.
##
## ⚠️ **THE CONTROLS ARE ASSIGNED UNCONDITIONALLY, NOT ONLY WHEN THE VALUE CHANGES** — 16.3's
## row states the general form after it came apart three times in one file: *"a control's value
## and the field behind it are one fact."* An `OptionButton` nobody has assigned shows item 0,
## which here is **Gaia**, so a panel that skipped the write would claim a villager belongs to
## gaia. `_filling_inspector` is what stops the write coming back as an edit.
func _refresh_inspector() -> void:
	if _entity_label == null:
		return
	var e: Dictionary = _document.selected_entity() if _document != null else {}
	_filling_inspector = true
	if e.is_empty():
		_entity_label.text = "  nothing selected — pick something with Select"
		_entity_label.add_theme_color_override("font_color", _DIM)
		_entity_owner.disabled = true
		_entity_size.disabled = true
		_entity_size_label.visible = false
		_entity_size.visible = false
	else:
		var tile: Vector2i = e.get("tile", Vector2i.ZERO)
		_entity_label.text = "  %s at %d,%d" % [
				GameDataRegistry.display_name(e.get("def_id", &"")), tile.x, tile.y]
		_entity_label.add_theme_color_override("font_color", _TEXT)
		_entity_owner.disabled = false
		_entity_owner.select(_entity_owner.get_item_index(int(e.get("player", 0))))
		# THE SIZE BOX IS ONLY THERE FOR A RESOURCE. Asking the registry rather than testing the
		# id's prefix: `res.` is a naming convention and `resource_def()` is the answer.
		var is_resource := GameDataRegistry.resource_def(e.get("def_id", &"")) != null
		_entity_size_label.visible = is_resource
		_entity_size.visible = is_resource
		_entity_size.disabled = not is_resource
		# CLAMPED, because `size_class` comes off a FILE. A map written by something else -- or by
		# hand -- can name a class the roster does not have, and `OptionButton.select()` with an
		# out-of-range index deselects the control and draws it blank, which reads as the panel
		# being broken rather than as the map being odd.
		_entity_size.select(clampi(int(e.get("size_class", 0)), 0,
				ObjectPalette.SIZE_LABELS.size() - 1))
	_filling_inspector = false


func _on_inspector_owner_chosen(at: int) -> void:
	if _filling_inspector or _document == null:
		return
	if _document.set_selected_owner(_entity_owner.get_item_id(at)):
		_after_entity_edited("OWNER")
	else:
		# ⚠️ **SAID OUT LOUD, `apply_tool`'s rule for a refused placement.** The only way this
		# fails with something selected is a value the document rejects, and a dropdown that
		# snapped back with no explanation is indistinguishable from a broken control.
		_refresh_inspector()


func _on_inspector_size_chosen(at: int) -> void:
	if _filling_inspector or _document == null:
		return
	var value: int = _entity_size.get_item_id(at)
	if _document.set_selected_size_class(value):
		_after_entity_edited("SIZE")
		return
	# ⚠️ **A REFUSED SIZE IS THE ONE THAT REALLY NEEDS A SENTENCE.** `set_selected_size_class`
	# refuses when the bigger footprint would run off the map or into a neighbour, and the box
	# has already moved to the value the author typed -- so without the notice AND the refill,
	# the panel shows a size the map does not have.
	_notice("WILL NOT FIT — %s cannot be %s there" % [
			GameDataRegistry.display_name(_document.selected_entity().get("def_id", &"")),
			str(ObjectPalette.SIZE_LABELS[clampi(value, 0,
					ObjectPalette.SIZE_LABELS.size() - 1)]).to_lower()], _WARN)
	_refresh_inspector()


## After an edit that came from the inspector rather than from the canvas.
##
## The MAP layer is redrawn here, unlike a change of selection: an owner change repaints the
## footprint (gaia green against a player's straw) and a size change resizes it.
func _after_entity_edited(what: String) -> void:
	var e := _document.selected_entity()
	_notice("%s — %s" % [what, GameDataRegistry.display_name(e.get("def_id", &""))], _GOOD)
	_canvas.queue_redraw()
	_canvas.redraw_overlay()
	_refresh_inspector()
	_refresh_status()


## Which players have a start, for the status line.
##
## ⚠️ **THIS IS THE ✓ MARKS' NEW HOME, and it is the one piece of information the retired player
## dropdown was carrying that nothing else showed.** *"Which players already have a start"* is
## what an author checks constantly while laying out a map — it is the difference between a
## two-player map and a two-player map with one seat — and `seats N` beside it is not the same
## fact: `seats()` is `min(starts, highest owner)`, so a start with no base contributes to this
## and not to that.
##
## **Named rather than ticked, because a status line has no rows.** The dropdown could show
## `P3 ✓`; a line has to say `starts P1,P3`, which is shorter to read and does not need opening.
func _starts_sentence() -> String:
	var placed: Array[String] = []
	for i in _document.data.starts.size():
		if _document.data.starts[i].x >= 0:
			placed.append("P%d" % (i + 1))
	return "starts %s" % ", ".join(PackedStringArray(placed)) if not placed.is_empty() \
			else "no starts yet"


## What the selection is, for the status line, or `fallback` when there is none.
##
## **THE DEF ID AND NOT THE PRETTY NAME**, unlike the inspector's caption: the status line is
## where an author checks *which* thing they picked when two look alike at 0.19x, and
## `res.gold_mine` beside "Gold Mine" in the panel is the pair that answers it. The palette's
## tooltips make the same choice for the same reason.
func _selection_sentence(fallback: String) -> String:
	var e: Dictionary = _document.selected_entity() if _document != null else {}
	if e.is_empty():
		return fallback
	var tile: Vector2i = e.get("tile", Vector2i.ZERO)
	var player := int(e.get("player", 0))
	# GAIA BY NAME. "P0" is not a player and reads as an off-by-one in the numbering rather than
	# as the owner every resource node on every map actually has.
	return "selected: %s (%s) at %d,%d" % [e.get("def_id", &""),
			"Gaia" if player == 0 else "P%d" % player, tile.x, tile.y]


func _on_hovered(_tile: Vector2i) -> void:
	_refresh_status()


func _refresh_status(problems: Array[String] = [] as Array[String]) -> void:
	# BEFORE THE EARLY RETURNS, so the buttons are right even in the states this function has
	# nothing to say about -- see `_refresh_undo()` on why the refresh lives here at all.
	_refresh_undo()
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
		# WHICH PLAYERS HAVE ONE, which used to be the ✓ marks in a dropdown that no longer
		# exists. `_starts_sentence()` explains why it is not the same fact as `seats`.
		_starts_sentence(),
		"zoom %.2fx" % _canvas.zoom(),
	]
	if hover.x >= 0:
		# THE NAME COMES FROM `MapDocument.terrain_name()`, which is also what labels an undo
		# step -- so "tile 40,12 — Water Deep" and "undo paint Water Deep" cannot disagree.
		bits.append("tile %d,%d — %s" % [hover.x, hover.y,
				MapDocument.terrain_name(_document.data.terrain_at(hover))])
	# ⚠️ **WHAT THE NEXT CLICK WILL DO, IN THE TOOL'S OWN WORDS.** With four tools and a
	# palette, "click" means five different things and the toolbar shows only which button is
	# down. `_document.entities.size()` going up by one is not something an author watching a
	# 96x96 map at 0.22x can see, so the sentence is how a placement is confirmed at all.
	match _tool:
		Tool.PLACE:
			bits.append(_palette.describe())
		Tool.ERASE:
			# ⚠️ **THIS SENTENCE NAMED A BUTTON THAT NO LONGER EXISTS** — it read *"starts are
			# cleared with Clear start"* for about an hour after the owner's ruling deleted that
			# button, which is worse than saying nothing: it sends an author looking round the
			# toolbar for a control that is not there. Found by a preview print. The eraser IS
			# the way now, and a click on a base takes the whole opening, so it says both.
			bits.append("click to erase — a base clears that player's whole start")
		Tool.SELECT:
			# WHAT IS SELECTED, or how to select something. The alternative -- saying nothing when
			# nothing is picked -- leaves the one tool whose whole job is invisible with no
			# feedback at all.
			bits.append(_selection_sentence("click something to select it"))
		Tool.MOVE:
			bits.append(_selection_sentence("press something and drag it"))
		Tool.PAINT:
			# ⚠️ **THE BRUSH, NOT THE PALETTE'S SELECTION — AND IT USED TO BE THE OTHER WAY.**
			# This read `_palette.describe()`, which only says "brush: …" while the palette is on
			# its Terrain tab. So an author who picked a building and then pressed `Brush` was
			# told the next click would *"place: Town Center (P1)"* when it would paint grass.
			# Found in `undo_ready.png`, which armed the two independently for the first time.
			# The palette does not drive this tool, so it does not get to describe it.
			bits.append("brush: %s" % MapDocument.terrain_name(_brush))
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
	elif _startup.guard != null and not _startup.guard.presentation_ok():
		# ⚠️ **A NOTE AND NOT A REFUSAL, which is the whole point of `PRESENTATION`.** A
		# drifted icon reader writes a byte-identical map file; what it costs is a wrong
		# picture in the palette. Saving stays on. `FormatGuard.PRESENTATION` has the argument.
		bits.append(_startup.guard.presentation_note())
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
