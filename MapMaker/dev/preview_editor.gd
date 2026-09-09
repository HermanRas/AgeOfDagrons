## Photograph the editor with a real map on the canvas (PLAN.md 16.2).
##
## ## THE CANVAS IS THE HALF OF 16.2 NO TEST CAN JUDGE
##
## `test_map_canvas` proves the arithmetic — screen→tile round-trips, the cull covers the
## viewport, the zoom floor fits the biggest map. **None of that says the map looks like a
## map.** Whether a river reads as a river, whether a 10x10 town centre is distinguishable
## from six villagers standing near it, whether a start marker is findable under the building
## it sits inside: those are questions for eyes, and the game's `preview_walls` exists for
## exactly the same reason — "which way does a wall face" has the same footprint, origin and
## hash either way.
##
## So this builds the same river map `dev/author_map.tscn` writes, hands it to the real
## editor through the real `show_document()`, and shoots it at three zooms.
##
## ⚠️ **IT PAINTS THROUGH `MapDocument`, NOT INTO `MapData`.** Same rule the authoring script
## follows: the point is to photograph what the editor's own mutation path produces, and a
## shortcut into the map would photograph something no button can make.
##
## Usage:
##   Godot --path MapMaker res://dev/preview_editor.tscn
##       -- writes user://editor_fit.png, editor_zoomed.png, editor_start.png,
##          editor_saved.png, editor_open.png, editor_reopened.png,
##          palette_buildings.png, palette_units.png, palette_resources.png,
##          palette_search.png, palette_terrain.png, palette_plates.png,
##          palette_placed.png, undo_ready.png, undo_undone.png
extends Node

## `Editor`'s script, for its `Tool` enum. `Editor.tscn`'s root has no `class_name`, so the
## enum is reached through the script rather than by writing the tool's index.
const EDITOR := preload("res://src/editor.gd")

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const UI_FRAMES := 8

## The name the Save shot writes under, and the prefix `_clean_up_the_saved_map()` requires
## before it will delete anything.
const SHOT_MAP_NAME := "Preview Shot"

var _editor: Control = null
var _frames := 0
var _step := 0
var _resume_at := 0


func _ready() -> void:
	# THROUGH `Startup`, and refused up front rather than photographed. A shot of a
	# "SAVING DISABLED" banner over an empty canvas proves nothing about the drawing, which is
	# this preview's whole job -- so a bad checkout is an exit code and a sentence.
	var startup := Startup.check()
	if not startup.can_save():
		printerr("cannot preview the editor: %s" % startup.reason)
		get_tree().quit(1)
		return

	_editor = load("res://Editor.tscn").instantiate()
	# NOTHING HANDED OVER ON PURPOSE. `Editor._ready()` checks for itself since the 2026-09-04
	# playtest, and a preview that skipped that path would not be photographing the editor the
	# main scene produces. The check above is what guarantees the shot is worth taking.
	add_child(_editor)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _resume_at:
		return
	match _step:
		0:
			if _frames < SETTLE_FRAMES:
				return
			_editor.show_document(_build_map())
			_hold(UI_FRAMES)
		1:
			_report("fit to view")
			_shoot("editor_fit")
		2:
			# ZOOMED IN ON THE RIVER, which is where the terrain kinds meet: at fit-to-view a
			# 96x96 map is ~5 px a tile and the sandy bank is a smear. The bank being
			# READABLE is the thing worth photographing.
			_zoom_to(Vector2i(48, 30), 2.0)
		3:
			_report("zoomed on the river bank")
			_shoot("editor_zoomed")
		4:
			_zoom_to(_editor.document().data.starts[0], 1.2)
		5:
			_report("player 1's start")
			_shoot("editor_start")
			_save_for_the_shot()
		6:
			# ⚠️ **THE ONE DEFECT ONLY A PICTURE CAN CHECK.** The owner's playtest said *"i
			# clicked save, not sure if it worked"* -- the confirmation went into the status
			# line, which `_refresh_status()` rewrites on every mouse move, so it was gone
			# before their hand left the button. No test can see a label that is overwritten a
			# frame later; this shot can.
			_report("after pressing Save")
			_shoot("editor_saved")
			# ⚠️ **AND THE 16.4a EQUIVALENT: IS THE DIALOG ACTUALLY ON TOP OF THE CANVAS?**
			# `test_map_open` proves what the list CONTAINS and nothing more. Whether the
			# overlay covers the map, whether a row's five figures fit on one line at 900 px,
			# and whether the dimmed canvas still shows through enough to be recognisable are
			# questions for eyes -- and §6's row about the `Control` that swallowed every
			# minimap tap is the same fault seen from underneath.
			_editor.open_dialog()
			_hold(UI_FRAMES)
		7:
			_report_open_list()
			_shoot("editor_open")
			_open_what_was_just_saved()
		8:
			_report("after opening the saved map")
			_shoot("editor_reopened")
			_clean_up_the_saved_map()
			# ⚠️ **THE PALETTE IS MOSTLY A PICTURE (16.3), so this is the half that matters.**
			# `test_object_palette` proves the lists, the search, the size class and the crop
			# arithmetic. **None of that says an icon is recognisable.** Whether a villager
			# cropped from a 1024x2048 page reads as a person at 88x78, whether a lettered
			# plate is legible on the colour `visuals.json` declares, and whether four tabs
			# and three dropdowns fit a 330 px column are questions for eyes.
			_show_palette(ObjectPalette.Category.BUILDING)
		9:
			_report_palette("buildings")
			_shoot("palette_buildings")
			_show_palette(ObjectPalette.Category.UNIT)
		10:
			_report_palette("units")
			_shoot("palette_units")
			# RESOURCES, because it is the one category with a size selector and the one the
			# original spec left out -- and because trees and mines are the icons an author
			# looks at most while laying out a map.
			_show_palette(ObjectPalette.Category.RESOURCE)
		11:
			_report_palette("resources")
			_shoot("palette_resources")
			_search_palette("mine")
		12:
			_report_palette("resources filtered by \"mine\"")
			_shoot("palette_search")
			# ⚠️ **THE ONE CATEGORY WHOSE CONTROL WAS REPLACED RATHER THAN ADDED.** 16.3 deleted
			# the toolbar's seven named terrain buttons, because two controls for one brush had
			# a one-way sync (`_tool_row()` carries the argument). So this tab is now the ONLY
			# way to choose a brush, and a shot of it is the check that the swatches are
			# tellable apart -- the toolbar's version had the terrain's name in its own colour.
			_show_palette(ObjectPalette.Category.TERRAIN)
		13:
			_report_palette("terrain")
			print("  brush armed: tool %d" % _editor._tool)
			_shoot("palette_terrain")
			_show_the_clean_clone()
		14:
			_report_palette("buildings with NO staged art")
			_shoot("palette_plates")
			_restore_the_art()
		15:
			_place_from_the_palette()
		16:
			_report("after placing from the palette")
			_shoot("palette_placed")
			# ⚠️ **UNDO'S OWN VISUAL QUESTION (16.2a): CAN AN AUTHOR TELL THERE IS UNDO, AND
			# TELL WHEN THERE IS NOT?** The tests prove the stack and both buttons' `disabled`
			# flags. What they cannot judge is whether a greyed Undo is distinguishable from a
			# live one at this theme's contrast -- and a shortcut nobody can see is a feature
			# nobody uses, which is the whole of what 16.2a is about.
			_drag_a_stroke()
		17:
			_report_history("after a drag along the bank")
			_shoot("undo_ready")
			_undo_once()
		18:
			_report_history("after pressing Undo")
			_shoot("undo_undone")
			# ⚠️ **16.4's CURSORS ARE ALMOST ENTIRELY A PICTURE, and one of them cannot be
			# checked any other way.** `test_cursors` proves the arithmetic — what a click
			# selects, what a move refuses, that the start follows its base. **None of that says
			# an author can SEE what is selected.** A cyan outline round a 10x10 town centre at
			# 0.19x, on a canvas that already draws orange start markers, straw buildings and a
			# white hover cursor, is a question for eyes.
			_select_a_town_centre()
		19:
			_report_selection("after clicking a town centre with Select")
			_shoot("cursor_selected")
			_drag_the_selection()
		20:
			_report_selection("after dragging it north, across its own resource ring")
			_shoot("cursor_moved")
			_edit_the_selection()
		21:
			_report_selection("after changing the owner in the inspector")
			_shoot("cursor_edited")
			_deselect()
		22:
			_report_selection("after clicking empty ground")
			_shoot("cursor_none")
			# ⚠️ **THE START AS A PALETTE ENTRY IS TWO PICTURES AND NOTHING ELSE** (owner's
			# ruling, 2026-09-08). The tests prove that picking `START_ID` and clicking lays a
			# real start down. **What they cannot judge:** whether the tile at the bottom of the
			# Building tab is recognisable as a start rather than as a building nobody baked, and
			# whether the toolbar still reads as a toolbar now that three controls have been
			# taken out of it and four placeholder glyphs put in.
			_place_a_start_from_the_palette()
		23:
			_report_start_row("after placing P3's start from the palette")
			_shoot("start_from_palette")
			_erase_that_start()
		24:
			_report_start_row("after erasing its base with the eraser")
			_shoot("start_erased")
			# ⚠️ **16.4c's WHOLE VISIBLE SURFACE IS THIS ONE SHOT.** The tests prove that the
			# `axis` key survives the file and that the world builds on it. **What they cannot
			# judge is whether an author can tell the two rows apart** — three lengths, a gate
			# and two directions is twenty-four wall rows in one tab, and the label is the only
			# thing that distinguishes a pair. If "Stone Wall (Short) NW-SE" clips to
			# "Stone Wall (Sho…" the feature is unusable and every test still passes.
			_show_the_wall_rows()
		25:
			_report_wall_rows()
			_shoot("palette_walls")
			_report_mouse_cursors()
			# ⚠️ **THE FILE MENU AND THE EXIT QUESTION ARE THE TWO NEW SURFACES WITH NO OTHER
			# CHECK** (card #93). The tests assert the menu's ids and the dialogs' configuration;
			# what they cannot judge is whether an embedded `PopupMenu` is readable over the
			# canvas, and whether the unsaved-changes question makes its three buttons' answers
			# obvious. The first render of the Open dialog is why this step exists at all: it came
			# out titled *"Open a Directory"* with a *"Select Current Folder"* button, opening in
			# the tool's own source tree, and **all three passed every test**.
			_show_file_menu()
		26:
			_shoot("file_menu")
			_provoke_the_exit_question()
		27:
			_report_exit_question()
			_shoot("exit_unsaved")
			print("")
			print("OK — twenty-four shots written. Look at them: the arithmetic is tested, the"
					+ " picture is not.")
			get_tree().quit(0)
			return
	_step += 1


## ── the File menu and the exit guard (card #93) ─────────────────────────────

## Drop the File menu open, the way a press on the `MenuButton` does.
##
## `MenuButton.show_popup()` rather than a synthetic click: the click path is Godot's and the
## thing worth photographing is the popup.
func _show_file_menu() -> void:
	var menu: PopupMenu = _editor._file_menu.get_popup()
	var labels: Array[String] = []
	for i in menu.item_count:
		labels.append("---" if menu.is_item_separator(i) else menu.get_item_text(i))
	print("")
	print("File menu: %s" % " | ".join(PackedStringArray(labels)))
	_editor._file_menu.show_popup()
	_hold(UI_FRAMES)


## Make the map dirty and ask to leave, so the unsaved-changes question is on screen.
##
## ⚠️ **IT DIRTIES THE MAP FIRST ON PURPOSE.** `request_exit()` on a clean document QUITS, and a
## preview that quit here would take its own screenshot away — and report success while doing it.
func _provoke_the_exit_question() -> void:
	_editor._file_menu.get_popup().hide()
	_editor.set_tool(EDITOR.Tool.PAINT)
	_editor.set_brush(SimMap.Terrain.ROCK)
	_editor.apply_tool(Vector2i(40, 40))
	if not _editor.document().dirty:
		printerr("  the map is not dirty, so Exit would simply quit and this shot is worthless")
		return
	_editor.request_exit()
	_hold(UI_FRAMES)


## What the three buttons say, printed beside the shot.
##
## **The wording IS the feature here.** A dialog whose buttons read OK and Cancel does not tell an
## author which one keeps their work, and this is the last thing standing between them and a lost
## afternoon of re-authoring — see `Editor.request_exit()`.
func _report_exit_question() -> void:
	var win: ConfirmationDialog = _editor._exit_win
	print("  exit question: \"%s\"" % win.dialog_text.replace("\n", " "))
	print("    ok:     %s" % win.ok_button_text)
	print("    cancel: %s" % win.get_cancel_button().text)
	print("    up:     %s" % win.visible)
	if not win.visible:
		printerr("  the exit question is NOT on screen -- the shot below shows nothing")


## ── the three cursors (16.4) ────────────────────────────────────────────────

## Zoom in on player 1's start and click their town centre with the SELECT tool.
##
## **THROUGH `apply_tool()`, which is what the canvas's `painted` signal reaches**, so this
## exercises the tool a press actually arms — `_place_from_the_palette`'s rule, for the same
## reason.
func _select_a_town_centre() -> void:
	# CLOSE ENOUGH TO SEE A TILE. At fit-to-view a tile is ~5 px and the whole question is
	# whether an outline is distinguishable from the things next to it.
	_zoom_to(_editor.document().data.starts[0], 1.1)
	_editor.set_tool(EDITOR.Tool.SELECT)
	_editor.apply_tool(_editor.document().data.starts[0])
	_hold(UI_FRAMES)


## Drag it, the way the mouse does: a stroke, a run of samples, a release.
##
## ⚠️ **THROUGH THE CANVAS'S OWN STROKE SIGNALS**, `_drag_a_stroke()`'s rule: those are the
## seam a real press and release use, so this is the only check that the editor is listening to
## them for MOVE as well as for PAINT. A preview that called `begin_stroke()` itself would
## photograph a coalesced step whether or not a drag produces one.
func _drag_the_selection() -> void:
	var doc: MapDocument = _editor.document()
	var from: Vector2i = doc.data.starts[0]
	var was: Vector2i = doc.selected_entity().get("tile", Vector2i.ZERO)
	var before: int = doc.history.depth()
	# ⚠️ **FRAMED SO BOTH ENDS OF THE DRAG ARE ON SCREEN, and the first version was not.** At
	# 1.1x the destination is twenty-seven rows off the top of the canvas, so the shot showed an
	# empty field while the status line correctly reported a building at 14,25 — a picture of
	# nothing, taken to prove a move. The camera does not follow an entity (nor should it: a real
	# drag keeps the pointer on screen, so the building cannot leave it).
	_zoom_to(from + Vector2i(0, -14), 0.55)
	_editor.set_tool(EDITOR.Tool.MOVE)
	(_editor._canvas as MapCanvas).stroke_began.emit()
	# THE FIRST SAMPLE IS THE GRAB and moves nothing -- see `Editor._move_to`. So the run has to
	# start on the entity and then go somewhere.
	#
	# ⚠️ **IT DRAGS ACROSS ITS OWN START'S VILLAGERS, WHICH IS THE CASE THAT FOUND
	# `_grab_intent`.** The first version of this stopped after two tiles: every intermediate
	# sample was refused by the units standing round the town centre, and the clear ground beyond
	# them was unreachable. So the path deliberately crosses them.
	# ⚠️ **NORTH, AND THE DIRECTION IS MEASURED RATHER THAN CHOSEN.** A diagonal drag ended two
	# tiles from where it started and looked like the retry not working: the destination was
	# inside the start's own resource ring, which reaches about twelve tiles out, so it was
	# refused for a perfectly good reason and proved nothing. Straight up clears the ring and
	# lands on open grass short of the rock patch at y 6..14.
	for step in range(0, 28):
		_editor.apply_tool(from + Vector2i(0, -step))
	(_editor._canvas as MapCanvas).stroke_ended.emit()
	# THE DELTA AND NOT THE DEPTH. The stack already has the placement and the sand stroke on it,
	# so an absolute figure says nothing about what the drag added -- which is the one number
	# 16.2a's rule is about.
	print("  the drag added %d step(s) to the stack" % (doc.history.depth() - before))
	print("  origin %s -> %s" % [was, doc.selected_entity().get("tile", Vector2i.ZERO)])
	_hold(UI_FRAMES)


## Change the owner through the inspector's own control, not through the document.
##
## The point is the CONTROL: `_filling_inspector` exists because assigning an `OptionButton`
## emits `item_selected`, and the failure that guard prevents — selecting a thing silently
## reassigning it — is only reachable by driving the widget.
func _edit_the_selection() -> void:
	var picker: OptionButton = _editor._entity_owner
	if picker.disabled:
		printerr("  the inspector is disabled with something selected")
		_hold(UI_FRAMES)
		return
	# P4, chosen because it is neither the current owner (P1) nor Gaia (item 0) -- so a shot
	# that shows P1 or Gaia is a shot of the bug rather than of the feature.
	var at := picker.get_item_index(4)
	picker.select(at)
	# `select()` DOES NOT EMIT. Assigning the control is what `_refresh_inspector` does, so a
	# preview that only assigned it would photograph a panel the document never heard about --
	# the signal is emitted by hand for that reason, which is what a real click does.
	picker.item_selected.emit(at)
	_hold(UI_FRAMES)


func _deselect() -> void:
	_editor.set_tool(EDITOR.Tool.SELECT)
	# A CORNER OF THE MAP NOTHING IS STANDING ON.
	_editor.apply_tool(Vector2i(1, 1))
	_hold(UI_FRAMES)


## What the tool thinks is selected, and what the inspector is showing.
##
## ⚠️ **BOTH, BECAUSE THEY ARE THE PAIR THAT CAN DISAGREE** — 16.3's row records that exact
## fault three times in one file (*"a control's value and the field behind it are one fact"*),
## where an `OptionButton` nobody had assigned showed item 0, which is Gaia, over a selection
## that said player 1. A screenshot shows the panel; only this print shows both.
func _report_selection(what: String) -> void:
	var doc: MapDocument = _editor.document()
	var e := doc.selected_entity()
	if e.is_empty():
		print("%s: nothing selected — inspector says \"%s\""
				% [what, _editor._entity_label.text.strip_edges()])
	else:
		var tile: Vector2i = e.get("tile", Vector2i.ZERO)
		print("%s: %s (P%d) at %d,%d — inspector says \"%s\", owner picker P%d"
				% [what, e.get("def_id", &""), int(e.get("player", 0)), tile.x, tile.y,
				_editor._entity_label.text.strip_edges(),
				_editor._entity_owner.get_item_id(_editor._entity_owner.selected)])
		if _editor._entity_owner.get_item_id(_editor._entity_owner.selected) \
				!= int(e.get("player", 0)):
			printerr("  the panel and the entity disagree about who owns it")
	# THE START, because a town centre is the one entity that carries one and a marker left
	# behind by its own base is 16.0's `can_start()` rule 7 authored by accident.
	print("  P1's start is at %s" % [doc.data.starts[0]])
	_hold(UI_FRAMES)


## ── the start as a palette entry (owner's ruling, 2026-09-08) ───────────────

## Scroll the Building tab to the start tile, pick it, and place P3's start with PLACE.
##
## **Through the palette and the PLACE tool**, which is the whole point of the change: there is
## no `Place start` button, no player dropdown and no `Clear start` in the toolbar any more, so
## if any part of this needs a control that is gone the preview cannot reach it either.
func _place_a_start_from_the_palette() -> void:
	_show_palette(ObjectPalette.Category.BUILDING)
	# **P3, NOT P1 OR P2** -- the demo map already has starts for those two, and re-placing one
	# would photograph a MOVED start rather than a new one. P3 also proves the status line names
	# the right player rather than counting.
	_palette().set_player(3)
	_palette().pick(ObjectPalette.START_ID)
	# ⚠️ **SEARCHED FOR RATHER THAN SCROLLED TO.** The start is the last of 33 rows in a
	# scrolling grid, so it is off-screen at rest and a shot of the palette would not contain the
	# tile this step exists to photograph. Typing "start" is also what an author does.
	_palette().set_search("start")
	_editor.set_tool(EDITOR.Tool.PLACE)
	_zoom_to(Vector2i(70, 70), 0.7)
	_editor.apply_tool(Vector2i(70, 70))
	_hold(UI_FRAMES)


## Erase it again, with the ordinary eraser, by clicking the middle of its base.
func _erase_that_start() -> void:
	_editor.set_tool(EDITOR.Tool.ERASE)
	_editor.apply_tool(Vector2i(70, 70))
	_hold(UI_FRAMES)


## What the map thinks the starts are, and what the status line says about them.
##
## ⚠️ **BOTH, BECAUSE THE STATUS LINE IS NOW THE ONLY DISPLAY OF IT.** The retired player
## dropdown carried ✓ marks for which players had a start; that moved here, and a line that
## disagrees with `MapData.starts` is the same class of fault as the owner picker that said Gaia
## over a selection that said player 1 (16.3).
func _report_start_row(what: String) -> void:
	var doc: MapDocument = _editor.document()
	print("%s: starts %s, seats %d, %d entities"
			% [what, doc.data.starts, doc.seats(), doc.data.entities.size()])
	print("  status line: %s" % _editor._status.text.strip_edges())
	print("  notice line: %s" % _editor._notice_label.text.strip_edges())
	_hold(UI_FRAMES)


## ── the wall rows, one per axis (16.4c) ─────────────────────────────────────

func _show_the_wall_rows() -> void:
	_show_palette(ObjectPalette.Category.BUILDING)
	# "STONE" RATHER THAN "WALL": searching wall brings back twenty-four rows and the tile grid
	# scrolls, so the shot would show the top of a list rather than a pair. One tier is eight
	# rows -- three lengths and a gate, twice -- which fits.
	_palette().set_search("stone wall")
	_hold(UI_FRAMES)


## Every wall row, its label, and what it would place.
##
## ⚠️ **THE LABEL AND THE `selection()` ARE PRINTED TOGETHER, because they are the pair that can
## disagree** and the whole feature is the claim that they do not: a row saying NE-SW that places
## `axis 0` is a tool that lies about the one thing an author cannot see until they play the map.
func _report_wall_rows() -> void:
	var palette := _palette()
	var ids := palette.listed_ids()
	print("the Stone Wall rows: %d" % ids.size())
	for id in ids:
		palette.pick(id)
		var pick := palette.selection()
		var axis := int(pick["axis"])
		print("  %-28s label %-34s places %s axis %d (%s)" % [
				String(id).replace("building.", ""), "\"%s\"" % palette._label_for(id),
				String(pick["def_id"]).replace("building.", ""), axis,
				str(ObjectPalette.AXIS_LABELS.get(axis, "none"))])
		# THE ROW'S NAME AND THE AXIS IT PLACES MUST AGREE, checked rather than eyeballed: the
		# label is the only place the direction is stated and the key is the only place it is
		# recorded.
		if axis != MapData.AXIS_NONE \
				and not palette._label_for(id).ends_with(str(ObjectPalette.AXIS_LABELS[axis])):
			printerr("    the label and the axis it places disagree")
	_hold(UI_FRAMES)


## ⚠️ **16.4e's CURSORS CANNOT BE PHOTOGRAPHED AND THIS IS THE NEXT BEST THING.**
##
## A custom mouse cursor is drawn by the WINDOWING SYSTEM, not into the viewport, so it is absent
## from every `get_texture().get_image()` capture this file takes — `_shoot()` is structurally
## blind to it. That is the same class of gap as `preview_lan_discovery`'s
## `set_broadcast_enabled(true)`: **one line the suite cannot reach and no screenshot can show.**
##
## So this arms all five tools in a WINDOWED process — the suite is headless and `ToolCursors.arm`
## returns early there — and prints the three facts that decide whether the cursor is right:
##
##   - **did `Input` take it**, which is what `arm()` returning true means. False for all five is
##     a missing `--import`; false for one is a missing file;
##   - **the drawn size**, because Godot draws a hardware cursor at the texture's own pixel size
##     and the source art is 100 px — three times too big, and it would not be obviously wrong on
##     a large monitor;
##   - **the hotspot**, next to the fraction it came from, so the one fault a picture cannot show
##     is at least written down beside the tool that owns it.
##
## **What is still the owner's to judge:** whether each cursor aims where its tip appears to, and
## whether the keyline holds over pale sand. That wants a hand on the mouse.
func _report_mouse_cursors() -> void:
	print("")
	print("mouse cursors (16.4e) — armed in a windowed process, which the headless suite cannot do")
	print("  registered against shape %d (Input.CURSOR_CROSS), which only MapCanvas asks for"
			% int(ToolCursors.SHAPE))
	var refused: Array[String] = []
	for entry in [
		{"tool": EDITOR.Tool.PAINT, "label": "Brush"},
		{"tool": EDITOR.Tool.PLACE, "label": "Place"},
		{"tool": EDITOR.Tool.ERASE, "label": "Erase"},
		{"tool": EDITOR.Tool.SELECT, "label": "Select"},
		{"tool": EDITOR.Tool.MOVE, "label": "Move"},
	]:
		var tool_value := int(entry["tool"])
		# THROUGH `Editor.set_tool()` AND NOT `ToolCursors.arm()` DIRECTLY, so this exercises the
		# route a button press takes. Arming the cursor from the press handler instead of from
		# `set_tool` is the mistake this would catch: every other caller — the tests, `dev/`, a
		# future keyboard shortcut — would leave the pointer on the last tool that was clicked.
		_editor.set_tool(tool_value)
		var armed := ToolCursors.arm(tool_value)
		var id := ToolCursors.for_tool(tool_value)
		var tex := ToolCursors.texture(id)
		var size := "no texture" if tex == null else "%dx%d" % [tex.get_width(), tex.get_height()]
		print("  %-7s %-11s %-9s hotspot %-9s %s" % [
				entry["label"], id, size, ToolCursors.hotspot(id),
				"armed" if armed else "REFUSED — falls back to the system crosshair"])
		if not armed:
			refused.append(str(entry["label"]))
	if not refused.is_empty():
		printerr("  %d of 5 cursors did not arm: %s" % [refused.size(), ", ".join(refused)])
		printerr("  run: godot --headless --path MapMaker --import")
	# LEFT ON THE BRUSH, because that is what the tool opens with and a preview should not leave
	# the editor in whatever state its last loop iteration happened to reach.
	_editor.set_tool(EDITOR.Tool.PAINT)
	_hold(UI_FRAMES)


## The same map `dev/author_map.tscn` writes, painted through the same document API.
func _build_map() -> MapDocument:
	var doc := MapDocument.create(Vector2i(96, 96), "River Demo")
	var side := doc.data.size.x
	var mid := side / 2
	for y in range(doc.data.size.y):
		var drift := int(round(sin(float(y) / 9.0) * 5.0))
		var centre := mid + drift
		for x in range(side):
			var d := absi(x - centre)
			if d <= 2:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_DEEP)
			elif d <= 4:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_SHALLOW)
			elif d <= 6:
				doc.paint(Vector2i(x, y), SimMap.Terrain.SAND)
	for y in range(6, 14):
		for x in range(6, mid - 10):
			doc.paint(Vector2i(x, y), SimMap.Terrain.ROCK)
	for y in range(side - 20, side - 6):
		for x in range(mid + 12, side - 6):
			doc.paint(Vector2i(x, y), SimMap.Terrain.FOREST)
	doc.place_start(1, Vector2i(side / 5, side * 3 / 5))
	doc.place_start(2, Vector2i(side * 4 / 5, side * 2 / 5))
	return doc


## Centre the canvas on a tile at a given zoom, so a shot frames something in particular.
##
## Through the canvas's own `center_on()` rather than by setting `_zoom` and `_pan`: the first
## version poked both directly, which skipped `view_changed` and produced a screenshot whose
## status line read 0.23x while the canvas was at 1.20x. **A preview that reaches past the
## public seam photographs a state no button can produce**, which is the opposite of its job.
func _zoom_to(tile: Vector2i, zoom: float) -> void:
	(_editor._canvas as MapCanvas).center_on(tile, zoom)
	_hold(UI_FRAMES)


## Press Save the way the button does, then hold a few frames so the notice is on screen.
##
## Named `SHOT_MAP_NAME` and **deleted again afterwards**: this writes into repo-root `maps/`,
## which is a tracked directory, and a preview that leaves a folder behind turns `git status`
## into noise. Anything but the real `Editor.save()` would photograph a label nothing sets.
func _save_for_the_shot() -> void:
	_editor._name_field.text = SHOT_MAP_NAME
	var problems: Array = _editor.save()
	if problems.is_empty():
		print("saved to %s" % _editor.document().dir)
	else:
		printerr("save failed: %s" % "; ".join(PackedStringArray(problems)))
	_hold(UI_FRAMES)


## What the Open dialog is offering, and where it looked (16.4a).
##
## **PRINTED AS WELL AS PHOTOGRAPHED**, because the two answer different questions: the shot
## says whether a row is legible, and this says whether the row is the right map. A screenshot
## of a list cannot be checked against a path.
func _report_open_list() -> void:
	var rows: Array = _editor.listed_maps()
	print("open dialog: %d maps" % rows.size())
	for row in rows:
		print("  %-28s \"%s\"  %s  %d players  (%s)" % [row["label"], row["name"],
				row["size"], int(row["players"]), MapSources.source_name(int(row["source"]))])


## Pick the map Save just wrote and open it through the real button.
##
## ⚠️ **IT IS THE SHOT BEFORE THIS ONE'S OUTPUT, AND THAT IS THE POINT.** The list is re-read
## on every Open (`Editor.open_dialog`), so a map written seconds ago by the Save button must
## appear in it — a cached list would show every map on the machine except the one the author
## just made, which is the single most confusing thing a picker can do. Nothing but a preview
## can check that: a test writes into `user://` and never into the root the dialog reads.
func _open_what_was_just_saved() -> void:
	var want: String = _editor.document().dir
	var rows: Array = _editor.listed_maps()
	for at in rows.size():
		if str(rows[at]["dir"]) != want:
			continue
		# ⚠️ **THROUGH `_on_dir_chosen()`, WHICH IS WHAT THE `FileDialog` EMITS INTO** (card #93).
		# This used to `select()` a row in the tool's own `ItemList` and press its Open button;
		# there is no list any more, and the dialog's `dir_selected` carries a PATH. Driving
		# `open_map()` directly would skip the "is there a `map.json` in here" check that is now
		# the only thing between an author and a folder that is not a map.
		_editor._on_dir_chosen(want)
		if _editor.document().dir == want:
			print("  reopened %s — %d entities, seats %d" % [_editor.document().dir.get_file(),
					_editor.document().data.entities.size(), _editor.document().seats()])
		else:
			printerr("  could not reopen it — the document is still %s"
					% _editor.document().dir)
		_hold(UI_FRAMES)
		return
	printerr("  the map Save just wrote is NOT in the Open list: %s" % want)
	_hold(UI_FRAMES)


## ── the palette (16.3) ──────────────────────────────────────────────────────

func _palette() -> ObjectPalette:
	return _editor._palette as ObjectPalette


func _show_palette(category: int) -> void:
	_palette().set_search("")
	_palette().set_category(category as ObjectPalette.Category)
	_hold(UI_FRAMES)


func _search_palette(needle: String) -> void:
	_palette().set_search(needle)
	_hold(UI_FRAMES)


## What the palette is showing, and **how many of those got a real picture rather than a
## plate**.
##
## ⚠️ **THE PLATE COUNT IS THE NUMBER WORTH PRINTING, and a screenshot cannot supply it.** A
## plate and a very dark sprite look similar at 88x78, so a category where the crop silently
## failed for half its entries would photograph as *"some of the art is dark"*. On the owner's
## machine, with all 139 atlases staged, anything above zero is a visual id whose `idle` clip
## did not resolve — which is a finding, not a rendering detail.
func _report_palette(what: String) -> void:
	var ids := _palette().listed_ids()
	if _palette().category() == ObjectPalette.Category.TERRAIN:
		# ⚠️ **TERRAIN DRAWS SWATCHES, NOT CROPS OR PLATES**, so counting crops here reported
		# "7 lettered plates" for a tab that has none — a number that would send somebody
		# hunting for missing art. A tile is a flat diamond on the canvas too (`MapCanvas`'s
		# header is emphatic that those colours are presentational), so a swatch in the same
		# colours IS the honest picture and there is nothing to count.
		print("palette %s: %d swatches in MapCanvas.TERRAIN_COLOURS" % [what, ids.size()])
		return
	var with_art := 0
	for id in ids:
		# ⚠️ **THE VARIANT SUFFIX HAS TO COME OFF HERE TOO, and forgetting it made this line
		# LIE about the tool.** 16.4c splits a wall into two palette rows (`...@axis0` /
		# `...@axis1`), and `crop_for` on a suffixed id resolves no visual at all — so this
		# reported *"20 with a cropped icon, 25 lettered plates"* for a palette that was
		# rendering all 24 wall rows from real art. **A checker that is wrong in the same way
		# the code might be is worse than no checker**: it sent me looking for a regression in
		# `_picture_for` that was not there.
		var def_id: StringName = ObjectPalette.split_variant(id)[0]
		if not _editor._icons.crop_for(def_id, 0, _palette().tint()).is_empty():
			with_art += 1
	print("palette %s: %d shown, %d with a cropped icon, %d lettered plates"
			% [what, ids.size(), with_art, ids.size() - with_art])
	if not ids.is_empty():
		print("  first three: %s" % ", ".join(PackedStringArray([
				String(ids[0]),
				String(ids[1]) if ids.size() > 1 else "",
				String(ids[2]) if ids.size() > 2 else ""])))


## Photograph the palette as a CLEAN CLONE sees it: no staged art, every tile a lettered plate.
##
## ⚠️ **THIS IS THE ONE SHOT ON THIS MACHINE THAT SHOWS A REQUIREMENT RATHER THAN A FEATURE.**
## 16.3's row insists a palette with no atlases must draw plates and carry on, because
## `game/assets/atlases/` is gitignored and absent from a fresh checkout. The owner has all 139
## staged — so **the view every other developer gets first is the only one nobody here can
## see**, and §5's rule is that a check blind to a fault ends the investigation. The plate
## arithmetic has tests; whether a two-letter monogram is centred and legible on the colour
## `visuals.json` declares for each subject is a question for eyes.
func _show_the_clean_clone() -> void:
	(_editor._icons as IconAtlas).ignore_atlases = true
	_show_palette(ObjectPalette.Category.BUILDING)


## And put it back, so the shot after this one is not photographing a crippled tool.
func _restore_the_art() -> void:
	(_editor._icons as IconAtlas).ignore_atlases = false
	_show_palette(ObjectPalette.Category.BUILDING)


## Pick a town centre off the palette and place it through the real click path.
##
## **Through `apply_tool()`, which is what the canvas's `painted` signal reaches**, so this
## exercises the tool the palette arms rather than calling `MapDocument.add_entity` directly.
## The second press on the SAME tile is the point: it must be refused and the refusal must be
## on screen, because a click that does nothing is indistinguishable from a broken tool.
func _place_from_the_palette() -> void:
	_show_palette(ObjectPalette.Category.BUILDING)
	_palette().pick(StartLayout.TOWN_CENTRE)
	var before: int = _editor.document().data.entities.size()
	var tile := Vector2i(70, 70)
	_editor.apply_tool(tile)
	var after: int = _editor.document().data.entities.size()
	print("placed %s at %d,%d: %d -> %d entities"
			% [StartLayout.TOWN_CENTRE, tile.x, tile.y, before, after])
	if after == before:
		printerr("  the palette's selection did not reach the map")
	# AND AGAIN, ON THE SAME GROUND. `_notice` is what the shot is for.
	_editor.apply_tool(tile)
	if _editor.document().data.entities.size() != after:
		printerr("  an overlapping placement was ACCEPTED")
	_hold(UI_FRAMES)


## ── undo (16.2a) ────────────────────────────────────────────────────────────

## Paint a run of sand along the river's east bank as ONE gesture.
##
## ⚠️ **THROUGH THE CANVAS'S OWN STROKE SIGNALS**, not by calling `begin_stroke()` on the
## document. Those signals are the seam the mouse press and release actually use, so this is
## the only check that the editor is listening to them at all — a preview that opened the
## stroke itself would photograph a coalesced step whether or not a real drag produces one.
func _drag_a_stroke() -> void:
	_editor.set_brush(SimMap.Terrain.SAND)
	_editor.set_tool(EDITOR.Tool.PAINT)
	var before: int = _editor.document().history.depth()
	(_editor._canvas as MapCanvas).stroke_began.emit()
	for y in range(24, 60):
		_editor.apply_tool(Vector2i(58, y))
	(_editor._canvas as MapCanvas).stroke_ended.emit()
	var after: int = _editor.document().history.depth()
	if after != before + 1:
		printerr("  a 36-tile drag became %d undo steps, not one" % (after - before))
	_hold(UI_FRAMES)


## Press Undo the way the button does.
func _undo_once() -> void:
	_editor.undo()
	_hold(UI_FRAMES)


## The stack, and both buttons' state.
##
## **PRINTED AS WELL AS PHOTOGRAPHED**, for the same reason the Open list is: the shot says
## whether a disabled button LOOKS disabled, and this says whether it IS. Neither answers the
## other's question, and the pair is what caught the palette's inert-but-blank tint dropdown in
## 16.3 — where the blankness hid the inertness.
func _report_history(what: String) -> void:
	var history: UndoStack = _editor.document().history
	print("%s: %d steps deep, %d redoable" % [what, history.depth(), history.redo_depth()])
	print("  undo button: %s — \"%s\"" % [
			"OFF" if (_editor._undo_button as Button).disabled else "live",
			history.undo_label()])
	print("  redo button: %s — \"%s\"" % [
			"OFF" if (_editor._redo_button as Button).disabled else "live",
			history.redo_label()])


func _clean_up_the_saved_map() -> void:
	var dir: String = _editor.document().dir
	if dir.is_empty() or not dir.get_file().begins_with("preview_"):
		# GUARDED BY THE NAME, so a future edit that renames the document cannot make this
		# delete an author's real map.
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.open(dir.get_base_dir()).remove(dir.get_file())
	print("  cleaned up %s" % dir)


func _report(what: String) -> void:
	var doc: MapDocument = _editor.document()
	var canvas: MapCanvas = _editor._canvas
	var bounds := canvas._visible_tile_bounds()
	print("%s: zoom %.2fx, drawing %d x %d tiles of %d x %d, seats %d"
			% [what, canvas.zoom(), bounds.size.x, bounds.size.y,
			doc.data.size.x, doc.data.size.y, doc.seats()])


func _hold(frames: int) -> void:
	_resume_at = _frames + frames


func _shoot(shot_name: String) -> void:
	var path := SHOT_DIR + shot_name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("  wrote ", ProjectSettings.globalize_path(path))
