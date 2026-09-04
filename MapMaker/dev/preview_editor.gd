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
##       -- writes user://editor_fit.png, editor_zoomed.png, editor_start.png
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const UI_FRAMES := 8

var _editor: Control = null
var _frames := 0
var _step := 0
var _resume_at := 0


func _ready() -> void:
	var root := GameRoot.resolve()
	if root.path.is_empty() or not GameDataRegistry.load_from(root):
		printerr("cannot read the game's roster: %s"
				% "; ".join(PackedStringArray(root.problems)))
		get_tree().quit(1)
		return

	_editor = load("res://Editor.tscn").instantiate()
	# TRUE, because this preview is about the canvas rather than about the guard -- and the
	# guard has its own tests plus a verified failure path (16.1). Passing false here would
	# photograph a "SAVING DISABLED" banner and prove nothing about the drawing.
	_editor.setup(true)
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
			print("")
			print("OK — three shots written. Look at them: the arithmetic is tested, the"
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
