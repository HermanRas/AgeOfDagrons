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

## ⛔ **THESE WERE SEVEN LITERAL COLOURS AND ARE NOW SEVEN ALIASES** (16.4f). They are kept as
## local names because the file reads them thirty-odd times and `UiChrome.TEXT` at every call site
## would be churn for nothing — but the VALUES now live in one place.
##
## 📝 **AND THIS REVERSES A NOTE THAT WAS RIGHT WHEN IT WAS WRITTEN.** `_DIM`'s old comment read:
## *"`Boot` and `ObjectPalette` both carry their own; a fourth copy of a grey is cheaper than a
## shared constant that has to live somewhere neither of them owns."* That was a fair trade for a
## grey. It stopped being one when the panels gained a plate: three files each deciding what
## "panel" and "text" mean is how one panel goes brown and the other two stay grey, each correct
## according to its own file. `UiChrome` is the somewhere.
const _BG := UiChrome.BG
const _PANEL := UiChrome.PANEL
const _TEXT := UiChrome.TEXT
const _GOOD := UiChrome.GOOD
const _BAD := UiChrome.BAD

## Saved, and worth reading anyway (16.4b). A third colour because there is a third outcome --
## see `save()`.
const _WARN := UiChrome.WARN

## Present but with nothing to say — the inspector with no selection (16.4).
const _DIM := UiChrome.DIM

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

## The File menu and Godot's stock dialogs (the owner's ruling on card #93, 2026-09-09).
##
## ⛔ **THESE REPLACED 16.4a's HAND-BUILT OVERLAY — THEY DO NOT SIT BESIDE IT.** The owner was
## offered "keep the rich list" and "keep both" and chose the fully-standard route, and a second
## Open path would be §5's *"the second rendering never gets looked at"* on the one screen that
## can overwrite shipped campaign content. `git show 2e1db33:MapMaker/src/editor.gd` has the
## overlay, its `ItemList` and its summary line.
##
## ⚠️ **A `FileDialog` AND A `PopupMenu` ARE `Window`s, AND 16.4a's OVERLAY WAS A `Control`
## DELIBERATELY** — *"half this tool's checks have no viewport (the suite drives `Editor` outside
## the tree), so a popup would answer nothing there."* That argument still holds for the tests, and
## `_dialog_open` is the answer: **the tool's own notion of "a dialog is up" is a bool**, and the
## `Window` is its presentation. So the suite can open and close the dialog outside a tree, the
## `Ctrl+Z` guard has something to read, and a click on the dialog's own X still updates the bool
## through `canceled`. Measured for the previews: an embedded subwindow DOES render into the
## parent viewport, so `preview_editor` can still photograph it.
var _file_menu: MenuButton = null
var _open_win: FileDialog = null
var _save_win: FileDialog = null
var _exit_win: ConfirmationDialog = null

## The line under the Open dialog's file list: where it looked, and what is unreadable there.
## **This is what carries 16.4a's third requirement across** — `MapSources` collects a sentence
## per folder holding a map pair it cannot parse, and a folder an author can see on disk and
## cannot see in the dialog is the one fault they cannot diagnose by looking.
var _open_hint: Label = null

## The Go to rows inside each dialog. Filled on open -- see _refresh_root_buttons().
var _open_roots: HBoxContainer = null
var _save_roots: HBoxContainer = null

## Is a modal up? See the note above on why this is a field and not `_open_win.visible`.
var _dialog_open := false

## What `refresh_open_list()` last found. **It no longer backs a list widget** — the `FileDialog`
## browses the filesystem itself — but it is still the answer to *"what could be opened"*, which
## `Boot`, `profile_editor` and `preview_editor` all report and which the dialog's hint line
## summarises. The `dir` is the identity; a label is not a path.
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
	# ⚠️ **THE WINDOW'S X MUST REACH `request_exit()` AND BY DEFAULT IT DOES NOT.** Without this,
	# Godot closes the window itself and `NOTIFICATION_WM_CLOSE_REQUEST` is a courtesy notice
	# rather than a question — so the unsaved-changes guard would exist on the menu item and be
	# absent from the gesture people actually use. It does NOT affect `get_tree().quit()`, which
	# is how the previews and the suite leave.
	if is_inside_tree():
		get_tree().set_auto_accept_quit(false)


## Hand back the one piece of application-wide state this screen claims (16.4e).
##
## ⚠️ **`Input.set_custom_mouse_cursor` IS NOT SCOPED TO THIS SCREEN AND `mouse_default_cursor_shape`
## IS.** Half the pair goes away with the canvas; the other half is a texture the `DisplayServer`
## keeps holding. `GameScene` does exactly this for `emulate_mouse_from_touch`, and its note is
## the rule: state claimed by a screen has to be given back on **every** path out, or the leak is
## whatever the next screen inherits. Here it presented as a leaked GPU texture at process exit.
func _exit_tree() -> void:
	ToolCursors.release()


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
	# A DIALOG IS MODAL, and that has to include the keyboard. Undoing behind one would change the
	# map the author is about to replace with a different one -- or, worse, behind the
	# unsaved-changes question, whose whole subject is how much unsaved work there is.
	#
	# ⚠️ **ASKED OF `dialog_is_up()` AND NOT OF A WINDOW'S `visible`.** The dialogs are `Window`s
	# now (card #93) and the suite drives this screen outside a tree, where a `Window` can neither
	# be popped nor report itself visible. The bool is the tool's own notion of modality; see
	# `_dialog_open`.
	if dialog_is_up():
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
	_dialog_open = true
	if _open_win == null:
		return
	# THE HINT LINE IS REBUILT ON EVERY OPEN, not once at construction. It counts what is on disk
	# and a `FileDialog` shows folder NAMES only, so this is where the three roots and their
	# counts survive the move off the `ItemList` -- and the count genuinely changes while the tool
	# runs, because the other half of this repo writes maps.
	if _open_hint != null:
		_open_hint.text = "  " + _open_summary()
		_open_hint.add_theme_color_override("font_color",
				_WARN if not _sources.warnings.is_empty() else _DIM)
	_refresh_root_buttons(_open_roots)
	_start_in_the_maps_root(_open_win)
	if is_inside_tree():
		# ⚠️ **ONLY WITH A TREE.** `popup_centered_ratio` needs a parent viewport, and the suite
		# drives this screen outside one. `_dialog_open` is what a test and the `Ctrl+Z` guard
		# read, so both work either way -- see the field's note.
		_open_win.popup_centered_ratio(0.7)


func close_dialog() -> void:
	_dialog_open = false
	if _open_win != null and _open_win.visible:
		_open_win.hide()
	if _save_win != null and _save_win.visible:
		_save_win.hide()


## Is a modal up? What the `Ctrl+Z` guard asks, and the reason it is a bool — see `_dialog_open`.
func dialog_is_up() -> bool:
	return _dialog_open


## Which dialogs have already been given a starting directory, by their own name.
var _dir_initialised: Dictionary = {}


## Open a dialog in `maps/` the FIRST time, and leave it wherever the author left it after that.
##
## ⛔ **FOUND IN THE FIRST SCREENSHOT OF THIS DIALOG, AND NOTHING ELSE COULD HAVE FOUND IT.** A
## `FileDialog` with no `current_dir` starts in the **project directory**, so the first Open
## presented an author with `.godot`, `assets`, `dev`, `format`, `src`, `tests`, `Boot.tscn` and
## `project.godot` — the tool's own source, with not a map in sight, and `maps/` two levels up and
## sideways. Every test passed: there is nothing wrong with a dialog that opens somewhere.
##
## ⚠️ **ONCE, NOT EVERY TIME, AND THAT IS THE DECISION IN THIS FUNCTION.** Re-pointing it on every
## open would throw away wherever the author had browsed to — which is worse than the bug for
## anybody working outside `maps/`, and 16.10's whole job is re-authoring maps that live under
## `scenarios/`. So the default is set once and the dialog remembers after that, which is how every
## file dialog a person has used behaves. `jump_to_root()` is the deliberate way back.
func _start_in_the_maps_root(win: FileDialog) -> void:
	if win == null or _dir_initialised.has(win.get_instance_id()):
		return
	_dir_initialised[win.get_instance_id()] = true
	var dir := maps_dir()
	if DirAccess.dir_exists_absolute(dir):
		win.current_dir = dir


## Point the Open dialog at one of `MapSources`' roots.
##
## ⚠️ **THIS IS WHAT THE `FileDialog` COSTS AND THIS IS THE REFUND.** 16.4a's list showed every
## map from **three** roots at once — repo-root `maps/`, the game's `user://maps/`, and
## `scenarios/<campaign>/<scenario>/` walked a level deeper. A `FileDialog` starts in ONE
## directory, so scenario 4's map — the thing 16.10 exists to re-author — went from a row in a
## list to four levels of browsing. Three buttons in the dialog's own box put it back.
func jump_to_root(source: int) -> bool:
	if _open_win == null:
		return false
	for entry in _sources.roots(_startup.root):
		if int(entry["source"]) != source:
			continue
		var path := str(entry["path"])
		if not DirAccess.dir_exists_absolute(path):
			return false
		_open_win.current_dir = path
		return true
	return false


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


## Open the map in `dir` if the dialog handed back a directory that holds one.
##
## ⚠️ **A `FileDialog` IN `FILE_MODE_OPEN_DIR` WILL HAND BACK ANY DIRECTORY AT ALL**, which is the
## other half of what the stock dialog costs: 16.4a's list could only offer folders `MapSources`
## had already parsed, so *"that is not a map"* was unreachable by construction. Now it is one
## click, and the message has to say which of the two it is — an empty folder and a folder holding
## a `map.json` this build cannot parse want different reactions from whoever reads it.
func _on_dir_chosen(dir: String) -> void:
	if not FileAccess.file_exists(dir.path_join("map.json")):
		# NAMES WHAT IT LOOKED FOR. "Not a map" sends an author hunting; "no map.json here" tells
		# them they are one level too high, which is the actual mistake nine times in ten.
		_notice("NOT A MAP — no map.json in %s" % dir, _BAD)
		return
	if open_map(dir).is_empty():
		close_dialog()


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
		# ⚠️ **THE DIALOG STAYS UP ON A FAILURE**, which is `_on_dir_chosen`'s doing rather than
		# this function's: it only closes on an empty problem list. An author who picked the wrong
		# folder is one click from the right one, and the reason is on the notice line where it
		# outlives the next mouse move.
		_notice("OPEN FAILED — %s" % "; ".join(PackedStringArray(problems)), _BAD)
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
	return save_as_into(maps_dir())


## Save As into a chosen parent directory. What the dialog's `dir_selected` reaches.
##
## ⚠️ **THE PARENT, NOT THE MAP FOLDER.** `MapDocument.save_as()` creates `<parent>/<slug>` from
## the name field, so handing it the map's own folder would nest a map inside a map — and the
## refusal that stops Save As replacing an existing map would not fire, because the new path is
## one nobody has taken. The dialog runs in `FILE_MODE_OPEN_DIR` for exactly this reason: what an
## author is choosing is **where a new folder goes**, and a save-file dialog would have asked them
## to name a file that does not exist.
func save_as_into(parent_dir: String) -> Array[String]:
	if _document == null:
		return ["nothing to save"] as Array[String]
	if not _startup.can_save():
		return [_startup.reason] as Array[String]
	_document.map_name = _name_field.text
	var problems := _document.save_as(parent_dir)
	_report_save(problems)
	return problems


## Ask where to put a new copy of this map.
##
## 📝 **IT DEFAULTS TO `maps/` AND THAT IS THE POINT OF STILL HAVING A DEFAULT.** Save As used to
## write there with no question asked; the dialog's gain is that an author can put a map somewhere
## else, not that they must decide every time.
func save_as_dialog() -> void:
	if _document == null:
		_notice("NOTHING TO SAVE — there is no map open", _WARN)
		return
	_dialog_open = true
	if _save_win == null:
		return
	# THE NAME FIELD IS THE FOLDER NAME AND THE DIALOG DOES NOT ASK FOR IT, so the notice has to
	# say what is about to be created -- otherwise "Save As" pops a directory browser and an
	# author has no idea the toolbar's Name box is what decides the folder.
	_save_win.title = "Save \"%s\" into which folder?" % _document.slug()
	_refresh_root_buttons(_save_roots)
	_start_in_the_maps_root(_save_win)
	if is_inside_tree():
		_save_win.popup_centered_ratio(0.7)


# ── Exit (the owner's card #93) ─────────────────────────────────────────────

## Leave, but not over unsaved work.
##
## ⛔ **THERE WAS NO GUARD AT ALL BEFORE THIS, AND `dirty` HAD BEEN CORRECT AND UNREAD FOR A DAY.**
## 16.2a computes it properly — `UndoStack._clean_at`, with both of the cases that otherwise go on
## claiming "saved" (a save point in a discarded redo branch, and one that falls off the front of a
## full stack) tested by name — and the **only** thing reading it was the status line's UNSAVED
## word. So the window's X was the cheapest way to lose work in this project, and since 16.4a made
## Save replace shipped campaign content in place, the same gesture could lose an afternoon of
## re-authoring.
##
## ⚠️ **THE MENU ITEM AND THE WINDOW'S X GO THROUGH THE SAME FUNCTION.** Guarding only the menu
## item would be a guard on the route nobody takes — the exact shape of
## `if Net.host() != null and <rule>`, which shipped three dead refusals in the game because solo
## play never takes the branch that matters. `_ready()` turns off `auto_accept_quit` and
## `_notification` routes the close request here.
func request_exit() -> void:
	if _document == null or not _document.dirty:
		_quit_now()
		return
	if _exit_win == null or not is_inside_tree():
		# NO DIALOG TO ASK WITH: refuse rather than quit. **The safe direction for a guard is the
		# one that keeps the work**, and this branch is only reachable from a test or a headless
		# run, neither of which has anything to lose by staying.
		_notice("UNSAVED CHANGES — save first, or discard them from the File menu", _WARN)
		return
	_exit_win.dialog_text = "\"%s\" has unsaved changes.\n\nLeave without saving?" \
			% _document.map_name
	_dialog_open = true
	_exit_win.popup_centered()
	# ⚠️ **FOCUS ON `Keep editing`, AND THIS LINE IS WHY THE COMMENT IN `_build_dialogs()` IS TRUE.**
	# An `AcceptDialog` focuses its OK button, so Enter discarded the map — and `_build_dialogs()`
	# claimed the opposite in a comment for about ten minutes, which is worse than not saying it:
	# a sentence in the code that gets believed and is wrong. **Found in `exit_unsaved.png`**, by
	# the focus ring sitting on "Discard and exit". Nothing headless can see a focus ring, and
	# `grab_focus()` needs the window up — so it is here and not in the builder.
	_exit_win.get_cancel_button().grab_focus()


func _quit_now() -> void:
	if is_inside_tree():
		get_tree().quit(0)


## The window's X. Routed to `request_exit()` — see its note on why both routes are one function.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_exit()


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
	# THE MOUSE CURSOR FOLLOWS THE TOOL (16.4e), and it is armed HERE rather than in
	# `_tool_row()`'s press handler because this function is the one door -- the tests, `dev/` and
	# the keyboard all come through it, so a tool set any other way would leave the pointer
	# showing the last tool that happened to be *clicked*. `ToolCursors` is a no-op headless.
	ToolCursors.arm(int(t))
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
	# THE TOOL'S TEXT COLOUR, IN ONE ASSIGNMENT (16.4f). A `Control`'s theme propagates to every
	# descendant, so this reaches the palette, the dialog and every control built below without
	# any of them asking. ⚠️ **It carries font colours ONLY** — `gui/theme/custom_font` changes
	# the face and not the colour, so `Button`s and `LineEdit`s were coming out in the engine
	# default's cold grey beside cream `Label`s. Invisible on the old flat greys; on a brown plate
	# it reads as two different families. `UiChrome.theme()` has the measurement.
	theme = UiChrome.theme()
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
	# ⚠️ **THIS ONE LINE IS WHAT KEEPS THE TOOL CURSORS OFF THE TOOLBAR** (16.4e).
	# `Input.set_custom_mouse_cursor` is application-wide state keyed on a built-in SHAPE, so the
	# art is registered against `CURSOR_CROSS` and only the control that asks for that shape gets
	# it. Registering against `CURSOR_ARROW` instead would put a paintbrush over the Save button.
	# `ToolCursors`' header carries the whole argument, including why the no-art fallback -- a
	# system crosshair over the map -- is the right one.
	_canvas.mouse_default_cursor_shape = ToolCursors.CANVAS_SHAPE
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
	# THE DIALOGS ARE `Window`s, so they are children rather than siblings in `rows` and their
	# stacking is the viewport's business rather than the child order's. Built last only because
	# `_add_root_buttons` reads `_startup`.
	_build_dialogs()


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

	# ⛔ **FOUR BUTTONS BECAME ONE MENU** (owner's card #93 with a mock of it, 2026-09-09). New,
	# Open, Save and Save As were four toolbar buttons and are five menu items, because a File
	# menu is where a person looks for them and because **Exit had nowhere to live**: see
	# `request_exit()` on why that mattered more than the tidiness.
	#
	# 📝 **THE OWNER'S MOCK SHOWED FOUR ITEMS — Open, Save, SaveAs, Exit — AND `New` IS HERE
	# ANYWAY**, which is a departure worth naming rather than slipping in. Dropping it would leave
	# **no way to start a map at all**; it was a toolbar button until this change. If the menu
	# should be exactly the mock, `New` is the line to delete and the button to put back.
	#
	# **`Fit` STAYS A BUTTON.** It is a view command, not a file command — filing it under File
	# would be the sort of menu nobody can predict.
	_file_menu = MenuButton.new()
	_file_menu.text = "File"
	_file_menu.flat = false
	var menu := _file_menu.get_popup()
	menu.add_item("New", FileAction.NEW)
	menu.add_item("Open…", FileAction.OPEN)
	menu.add_item("Save", FileAction.SAVE)
	menu.add_item("Save As…", FileAction.SAVE_AS)
	# A SEPARATOR BEFORE EXIT, because it is the one item that cannot be undone by another item.
	menu.add_separator()
	menu.add_item("Exit", FileAction.EXIT)
	menu.id_pressed.connect(_on_file_action)
	row.add_child(_file_menu)
	row.add_child(_button("Fit", func() -> void: _canvas.fit_to_view()))
	return box


## What the File menu's items mean.
##
## ⚠️ **IDS, NOT INDEXES.** `add_item`'s id is what `id_pressed` carries, and a separator occupies
## an INDEX while carrying no id — so anything keyed on position would shift the moment the menu
## grows a divider. Same hazard as `Tool.START`'s removal renumbering every tool after it, with a
## menu instead of an enum.
enum FileAction { NEW, OPEN, SAVE, SAVE_AS, EXIT }


func _on_file_action(id: int) -> void:
	match id:
		FileAction.NEW:
			_new_map()
		FileAction.OPEN:
			open_dialog()
		FileAction.SAVE:
			save()
		FileAction.SAVE_AS:
			save_as_dialog()
		FileAction.EXIT:
			request_exit()


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
	# THE TWO TOOLBAR ACTIONS THAT ARE NOT TOOLS, so they ask by id rather than through
	# `for_tool()`. ⚠️ **A DISABLED BUTTON DIMS ITS ICON THROUGH `icon_disabled_color`**, which is
	# a separate theme entry from the one `_paint_icon` sets — left alone deliberately: greying is
	# exactly what these two should do when there is nothing to take back.
	_paint_icon(_undo_button, ToolIcons.texture(ToolIcons.UNDO))
	_paint_icon(_redo_button, ToolIcons.texture(ToolIcons.REDO))
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
		# ⚠️ **THE ICON IS BESIDE THE WORD AND DOES NOT REPLACE IT.** An icon-only toolbar would be
		# prettier and less usable, which is 16.2a's own argument about `Ctrl+Z` — *"a shortcut
		# nobody can see is a feature nobody uses"* — applied to a picture instead of a keystroke.
		# It held for the drawn placeholders and it holds harder for these: `mm_select` and
		# `mm_move` are a marquee and a four-way arrow, which are the two glyphs every editor
		# draws slightly differently.
		_paint_icon(b, ToolIcons.for_tool(int(entry["tool"])))
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


## Godot's three stock dialogs: Open, Save As, and the unsaved-changes question (card #93).
##
## ⛔ **THIS REPLACED A 95-LINE HAND-BUILT OVERLAY, ON THE OWNER'S RULING.** 16.4a's dialog was an
## `ItemList` of every map from three roots, each row carrying its size, player count and source,
## with the width **measured off the longest real row** (1200, after scenario 5 clipped at 900).
## `git show 2e1db33:MapMaker/src/editor.gd` has it. What the stock dialog trades:
##
## | lost | how it is paid for |
## |---|---|
## | a row's size / players / source | `_open_hint` summarises the roots and their counts; the notice line names the map on open |
## | three roots visible at once | `jump_to_root()` — three buttons in the dialog's own box |
## | "that folder is not a map" being unreachable | `_on_dir_chosen()` checks for `map.json` and says which level is wrong |
## | Save As refusing a taken name | still `MapDocument.save_as()`'s refusal — the dialog chooses the PARENT, so the refusal is untouched |
##
## ⚠️ **AND WHAT IT BUYS IS THE THING 16.4a's LIST COULD NOT DO: reach a map in a folder
## `MapSources` does not walk.** Every root is hard-coded in `MapSources.roots()`, so a map
## anywhere else was unopenable — by construction, with no error.
func _build_dialogs() -> void:
	# ── Open ──
	_open_win = FileDialog.new()
	# ⚠️ **`FILE_MODE_OPEN_DIR`, BECAUSE A MAP IS A DIRECTORY OF TWO FILES** (`map.json` and
	# `map.png`). A file-mode dialog filtered to `*.json` would have an author picking the
	# `map.json` INSIDE the folder, and `MapDocument.open()` takes the folder — so every pick
	# would need its path trimming, and a `map.json` that is not a map's would look openable.
	_open_win.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	# ⚠️ **THE TITLE AND THE OK BUTTON ARE SET *AFTER* THE MODE, AND THE FIRST SCREENSHOT IS WHY.**
	# Assigning `file_mode` **overwrites both** with Godot's generic wording for that mode, so a
	# title set beforehand is silently replaced: the dialog came out headed *"Open a Directory"*
	# with a button reading *"Select Current Folder"*, which describes the widget rather than the
	# job. Every test passed — there is nothing wrong with a `FileDialog` titled by its mode.
	_open_win.title = "Open a map"
	_open_win.ok_button_text = "Open this map"
	# ⚠️ **`ACCESS_FILESYSTEM` AND NOT `ACCESS_RESOURCES`.** The maps this tool exists to open are
	# **outside `res://`** — repo-root `maps/`, `scenarios/`, and the GAME's `user://maps/`, which
	# is a different directory from this project's `user://` (16.4a's third root). A resource-mode
	# dialog can see none of them.
	_open_win.access = FileDialog.ACCESS_FILESYSTEM
	_open_win.use_native_dialog = false
	_open_win.dir_selected.connect(_on_dir_chosen)
	_open_win.canceled.connect(close_dialog)
	_open_roots = _add_root_buttons(_open_win)
	_open_hint = Label.new()
	_open_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_open_win.get_vbox().add_child(_open_hint)
	add_child(_open_win)

	# ── Save As ──
	_save_win = FileDialog.new()
	# OPEN_DIR HERE TOO, and `save_as_into()`'s note says why: what an author picks is the PARENT
	# a new folder goes into, not a file to name. The folder's name comes from the toolbar's Name
	# field, which is why `save_as_dialog()` puts the slug in the title.
	_save_win.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_win.access = FileDialog.ACCESS_FILESYSTEM
	_save_win.use_native_dialog = false
	# AFTER THE MODE — see the Open dialog's note. `save_as_dialog()` rewrites the title per save
	# (it names the folder about to be created); this is the button, which does not change.
	_save_win.ok_button_text = "Save here"
	_save_win.dir_selected.connect(func(dir: String) -> void:
			# CLOSED FIRST, then saved. `_report_save` writes the notice line, and a dialog still
			# up over it would hide the one sentence that says whether the save worked -- which is
			# the owner's *"i clicked save, not sure if it worked"* with a modal on top of it.
			close_dialog()
			save_as_into(dir))
	_save_win.canceled.connect(close_dialog)
	_save_roots = _add_root_buttons(_save_win)
	add_child(_save_win)

	# ── the unsaved-changes question ──
	#
	# ⚠️ **THE DEFAULT BUTTON IS CANCEL, NOT OK.** A `ConfirmationDialog`'s OK takes Enter, and the
	# whole point of this dialog is that somebody reached it by accident; "leave without saving"
	# is not the answer to give a stray keystroke. `Save and exit` is the third button because the
	# two-button form makes an author cancel, save, and then find Exit again.
	_exit_win = ConfirmationDialog.new()
	_exit_win.title = "Unsaved changes"
	_exit_win.ok_button_text = "Discard and exit"
	_exit_win.get_cancel_button().text = "Keep editing"
	var save_and_go := _exit_win.add_button("Save and exit", true, "save_and_exit")
	save_and_go.pressed.connect(func() -> void:
			_exit_win.hide()
			_dialog_open = false
			# ⚠️ **ONLY QUITS IF THE SAVE WORKED.** `save()` refuses when the format copies have
			# drifted or a map has no name, and quitting anyway would throw away the work this
			# dialog exists to protect *while the author was choosing to keep it*.
			if save().is_empty():
				_quit_now())
	_exit_win.confirmed.connect(func() -> void:
			_dialog_open = false
			_quit_now())
	_exit_win.canceled.connect(close_dialog)
	add_child(_exit_win)


## The row the root buttons live in. Empty until a dialog is opened — see `_refresh_root_buttons`.
func _add_root_buttons(win: FileDialog) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	win.get_vbox().add_child(row)
	return row


## Fill a dialog's root buttons, from the roots as they are NOW.
##
## ⚠️ **CALLED ON OPEN AND NOT AT CONSTRUCTION, WHICH IS AN ORDERING BUG AVOIDED RATHER THAN
## FIXED.** `_ready()` runs `_build_ui()` **before** `_startup` is resolved — deliberately, so a
## screen opened directly still builds — and `MapSources.roots()` needs `_startup.root` to derive
## the GAME's `user://maps/` (16.4a's third root, found by reading `config/name` out of the game's
## `project.godot`). Building these buttons in `_build_dialogs()` would have asked for the roots
## with a null root and produced a permanently disabled button for the one root that is hardest to
## reach by browsing. **Rebuilt each time**, because a root can appear while the tool is running:
## the game's `user://maps/` does not exist until somebody saves a map from a match.
func _refresh_root_buttons(row: HBoxContainer) -> void:
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
		row.remove_child(child)
	row.add_child(_label("Go to"))
	for entry in _sources.roots(_startup.root if _startup != null else null):
		var source := int(entry["source"])
		var b := _button(MapSources.source_name(source), func() -> void: jump_to_root(source))
		# ⚠️ **DISABLED WHEN THE ROOT IS NOT THERE, AND THE TOOLTIP IS WHY.** The game's
		# `user://maps/` does not exist until a player saves a map from a match, and `scenarios/`
		# is absent from an export's neighbourhood. A button that silently does nothing is §6's
		# server-browser JOIN; a disabled one with the path in its tooltip is an answer.
		b.disabled = not DirAccess.dir_exists_absolute(str(entry["path"]))
		b.tooltip_text = str(entry["path"])
		row.add_child(b)


# ── small builders ──────────────────────────────────────────────────────────

## One toolbar row: the `panel_hud` plate with a row inside it (16.4f).
##
## THE THREE TOOLBAR ROWS ARE ALL THIS FUNCTION, which is why the owner's *"the same panel_hud for
## all the panels"* was one edit here and one in the palette rather than a sweep. The gutter is
## `UiChrome`'s default; the plate's 12 px moulding is added to it there, because content has to
## clear the border before it starts having padding.
func _panel() -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiChrome.panel_style())
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


## Put one of `ToolIcons`' pictures on a button. A thin call, kept as a name because three of the
## four call sites read better for it — the tint rule itself lives in `ToolIcons.apply()`, which
## is where a second caller (the palette's tabs) can not forget it.
func _paint_icon(b: Button, tex: Texture2D) -> void:
	ToolIcons.apply(b, tex)


func _separator() -> Control:
	var s := VSeparator.new()
	return s
