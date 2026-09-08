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
			print("")
			print("OK — fifteen shots written. Look at them: the arithmetic is tested, the"
					+ " picture is not.")
			get_tree().quit(0)
			return
	_step += 1


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
		(_editor._open_list as ItemList).select(at)
		var problems: Array = _editor.open_selected()
		if problems.is_empty():
			print("  reopened %s — %d entities, seats %d" % [_editor.document().dir.get_file(),
					_editor.document().data.entities.size(), _editor.document().seats()])
		else:
			printerr("  could not reopen it: %s" % "; ".join(PackedStringArray(problems)))
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
		if not _editor._icons.crop_for(id, 0, _palette().tint()).is_empty():
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
