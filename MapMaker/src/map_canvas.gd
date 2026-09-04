## The iso canvas: draws the map, and turns a mouse position into a tile (PLAN.md 16.2).
##
## ## IT USES THE GAME'S OWN `Iso`, WHICH IS THE WHOLE REASON `format/` EXISTS
##
## Every tile-to-screen conversion here goes through `Iso.tile_to_world()` and every
## screen-to-tile through `Iso.tile_at()` — a **verbatim, hash-checked copy** of the file the
## game draws with. So a diamond drawn here is the diamond the game draws, at the same
## proportions, and an author judging whether a river cuts a map in two is looking at the
## same geometry the player will. Re-deriving the projection with a local `TILE_SIZE` would
## have been four lines and would have made the canvas a lie that nothing could detect.
##
## ## ONLY VISIBLE TILES ARE DRAWN, AND THAT IS NOT AN OPTIMISATION
##
## A 192x192 map is 36,864 tiles. Drawing all of them as filled polygons every frame is
## seconds per frame, so the tool would be unusable at exactly the size the game's own
## generator produces. `_visible_tile_bounds()` inverts the four screen corners back into
## tile space and draws the enclosing range, which is ~1,500 diamonds at 1600x900 — flat
## whatever the map's size.
##
## ⚠️ **THE INVERSE OF AN ISO PROJECTION IS A ROTATED RECTANGLE, NOT A RECTANGLE.** The four
## screen corners map to four tile-space corners that are not axis-aligned, so the bounds are
## taken as the min/max over all four and then padded. Getting this wrong does not look like
## a performance bug — it looks like tiles missing from two edges of the screen while panning,
## which reads as a drawing fault.
##
## ## TERRAIN COLOURS HERE ARE PRESENTATIONAL AND ARE NOT THE FILE'S
##
## `MapFile` writes the terrain KIND into the PNG's red channel and a cosmetic tint into
## green and blue; its class comment is emphatic that a loader must never read the tint.
## These colours are a third thing again — what the author sees — and nothing reads them
## back. They are chosen to be told apart at a glance rather than to match the game's art.
class_name MapCanvas
extends Control

## Presentational only. See the class comment.
const TERRAIN_COLOURS := {
	SimMap.Terrain.GRASS: Color(0.36, 0.55, 0.28),
	SimMap.Terrain.DIRT: Color(0.45, 0.36, 0.24),
	SimMap.Terrain.SAND: Color(0.78, 0.71, 0.48),
	SimMap.Terrain.WATER_SHALLOW: Color(0.35, 0.60, 0.72),
	SimMap.Terrain.WATER_DEEP: Color(0.18, 0.35, 0.55),
	SimMap.Terrain.ROCK: Color(0.45, 0.45, 0.48),
	SimMap.Terrain.FOREST: Color(0.20, 0.34, 0.20),
}

const _GRID := Color(0, 0, 0, 0.10)
const _CURSOR := Color(1, 1, 1, 0.85)
const _BUILDING := Color(0.90, 0.85, 0.55)
const _UNIT := Color(0.95, 0.95, 0.95)
const _GAIA := Color(0.55, 0.75, 0.45)
const _START := Color(1.0, 0.45, 0.35)
const _OUT_OF_BOUNDS := Color(0.07, 0.07, 0.09)

## ⚠️ **THE FLOOR IS DERIVED FROM THE BIGGEST MAP, NOT CHOSEN — AND THE FIRST VALUE WAS WRONG.**
##
## It was 0.25 on the reasoning that below it a tile is unreadably small, and a test caught
## that this **cannot fit a map the game's own generator produces**: a 96x96 map projects to
## 6144 x 3072 px, so fitting it in a 1600-wide window needs 0.24 — already under the floor —
## and `MapDocument.MAX_SIZE` at 256 needs about 0.098. The tool would have opened every real
## map clamped, showing a corner of it, which reads as a broken canvas rather than as a
## clamped zoom.
##
## So: `1600 / ((256 + 256) * 32)` rounded down, which fits the largest allowed map in the
## narrowest window this tool is configured for, with room to spare. A tile is ~5 px across
## there — unreadable, and correct, because that view's job is "does the river cut the map in
## two" and not "which tile is this".
##
## **If `MapDocument.MAX_SIZE` ever grows, this has to come down with it**, which is why the
## arithmetic is written out rather than the answer.
const MIN_ZOOM := 0.08

## Above 4x there is no detail left to reveal: nothing here is drawn from art yet (icons are
## 16.3), so a tile is a flat diamond however close you get.
const MAX_ZOOM := 4.0

## Emitted with the tile under the pointer, or (-1, -1) when it is off the map.
signal hovered(tile: Vector2i)

## A left-press or left-drag over `tile`. The editor decides what the current tool does with
## it; the canvas has no opinion and holds no tool state.
signal painted(tile: Vector2i)

## The pan or zoom moved.
##
## ⚠️ **THIS EXISTS BECAUSE THE STATUS LINE WAS LYING, and a screenshot is what caught it.**
## The editor reports the zoom by asking `zoom()`, but it only *asked* when something else
## called `_refresh_status()` — a hover or a paint. A mouse wheel moves neither the pointer's
## tile nor the map, so scrolling changed the view and left the readout showing the old
## figure indefinitely. A number on screen that is quietly stale is worse than no number,
## because it gets believed.
signal view_changed

var document: MapDocument = null

var _zoom := 1.0
var _pan := Vector2.ZERO
var _hover := Vector2i(-1, -1)
var _panning := false
var _painting := false

## The cursor's own layer. See `_ready()`: this is what stops a mouse-move repainting 9,216
## tiles.
var _overlay: Control = null

## Where the last paint sample landed, so a fast drag can be filled in. -1 between strokes.
##
## ⚠️ **WITHOUT THIS A DRAG LEAVES GAPS.** `InputEventMouseMotion` arrives once a frame at
## best, so a quick stroke jumps several tiles between samples and paints a dotted line --
## which the owner's playtest reported as *"some tiles did not place due to lag"*. It was not
## lag dropping them; nothing had ever been asked to paint them.
var _last_painted := Vector2i(-1, -1)


func _ready() -> void:
	# THE CANVAS TAKES PRESSES. Every other Control in this tool is a button or a field, so
	# this is the one place the default `MOUSE_FILTER_STOP` is what we want.
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	# ⚠️ **THE MAP DREW OVER THE TOOLBAR WITHOUT THIS** (owner's playtest, 2026-09-04). A
	# `Control` does not clip its own `_draw` to its rect, and this one draws a whole map
	# projected from an arbitrary pan -- so at any zoom that put tiles above y=0 they landed
	# on top of the buttons. It reads as a layering bug and is one line.
	clip_contents = true
	resized.connect(_on_resized)

	# THE HOVER CURSOR LIVES ON ITS OWN LAYER, AND THAT IS THE PERFORMANCE FIX.
	#
	# The owner's playtest: *"the tool is very slow ... some tiles did not place due to
	# lag"*. The cause was not the tile count as such -- it was that the CURSOR was drawn in
	# the same `_draw` as the terrain, so every mouse-move called `queue_redraw()` on the
	# whole map. At fit-to-view a 96x96 map is 9,216 tiles and the cull covers all of them,
	# so a single drag re-issued ~18,000 draw calls per motion event.
	#
	# Godot redraws a `CanvasItem` only when that item is invalidated, so putting the cursor
	# on a child means moving the mouse repaints four line segments and the terrain is left
	# alone. The terrain now redraws only when the MAP or the VIEW changes, which is what a
	# `_draw` is for.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## The cull depends on the rect, so a resize is a view change.
##
## The overlay is not resized here: it is anchored `PRESET_FULL_RECT`, so the layout pass
## follows the canvas on its own. Assigning `size` as well fought the anchors and Godot said
## so ("If you want to set size, change the anchors").
func _on_resized() -> void:
	_view_moved()


## The pan or zoom changed: redraw both layers and tell the editor.
##
## ⚠️ **THE OVERLAY HAS TO BE INVALIDATED TOO, and that is the trap in splitting the layers.**
## The cursor diamond is drawn from `_hover` through the CURRENT pan and zoom, so a mouse-wheel
## zoom -- which moves the view without producing a motion event -- would leave the diamond
## sitting at its old screen position over completely different tiles until the pointer next
## moved. Every write to `_zoom` or `_pan` goes through here for that reason.
func _view_moved() -> void:
	queue_redraw()
	# NULL UNTIL `_ready()`, and that is a supported state rather than an oversight: the
	# projection maths (`tile_at`, `_zoom_at`, `fit_to_view`) is pure and the tests drive it on
	# a canvas that never enters the tree, which is what makes it testable without a window.
	if _overlay != null:
		_overlay.queue_redraw()
	view_changed.emit()


## Point the canvas at a document and frame the whole map.
func show_document(doc: MapDocument) -> void:
	document = doc
	fit_to_view()


## Centre the map and pick a zoom that fits it, with a margin.
##
## Called on every new or opened map, because the alternative -- opening at 1:1 in a corner --
## makes a 192x192 map look like an empty green wedge, which is indistinguishable from a
## broken canvas.
func fit_to_view() -> void:
	if document == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var bounds := Iso.map_bounds(document.data.size)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var margin := 0.92
	_zoom = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y) * margin,
			MIN_ZOOM, MAX_ZOOM)
	_pan = size * 0.5 - bounds.get_center() * _zoom
	_view_moved()


func zoom() -> float:
	return _zoom


## Put `tile` in the middle of the canvas at `at_zoom`.
##
## Public so a preview can frame a particular thing without reaching for `_zoom` and `_pan`
## directly -- which would skip `view_changed` and leave the status line stale, the very bug
## that signal was added for. 16.4a will want this too, to open a map looking at its starts.
func center_on(tile: Vector2i, at_zoom: float) -> void:
	_zoom = clampf(at_zoom, MIN_ZOOM, MAX_ZOOM)
	_pan = size * 0.5 - Iso.tile_centre_to_world(tile) * _zoom
	_view_moved()


## The tile under a position in this control's local space, or (-1, -1) off the map.
func tile_at(local: Vector2) -> Vector2i:
	if document == null:
		return Vector2i(-1, -1)
	var t := Iso.tile_at((local - _pan) / _zoom)
	return t if document.data.in_bounds(t) else Vector2i(-1, -1)


# ── input ───────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_motion(event as InputEventMouseMotion)


func _button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			_painting = e.pressed
			# A NEW STROKE STARTS FRESH. Carrying the last sample across a release would
			# bridge two separate clicks with a painted line between them.
			_last_painted = Vector2i(-1, -1)
			if e.pressed:
				# Focus needs a tree; the suite drives presses on a canvas without one.
				if is_inside_tree():
					grab_focus()
				_emit_paint(e.position)
		MOUSE_BUTTON_MIDDLE:
			# MIDDLE-DRAG PANS, not left-drag: left is the tool, and a canvas where the
			# paint gesture and the pan gesture are the same one cannot do both.
			_panning = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.1)


func _motion(e: InputEventMouseMotion) -> void:
	if _panning:
		_pan += e.relative
		_view_moved()
	var t := tile_at(e.position)
	if t != _hover:
		_hover = t
		hovered.emit(t)
		# THE OVERLAY ONLY. The terrain has not changed and neither has the view, so
		# repainting the map here is the whole of what made a drag stutter. Null before
		# `_ready()` -- see `_view_moved()` for why that is a supported state.
		if _overlay != null:
			_overlay.queue_redraw()
	if _painting:
		_emit_paint(e.position)


func _emit_paint(local: Vector2) -> void:
	var t := tile_at(local)
	if t.x < 0:
		# Off the map: the stroke is broken rather than bridged, so dragging out over the
		# void and back does not paint a line across everything in between.
		_last_painted = Vector2i(-1, -1)
		return
	# FILL IN FROM THE LAST SAMPLE. See `_last_painted`: motion events are far apart at
	# speed, and a stroke has to be continuous or the author is painting dots.
	if _last_painted.x >= 0 and _last_painted != t:
		for step in _tiles_between(_last_painted, t):
			painted.emit(step)
	else:
		painted.emit(t)
	_last_painted = t


## The tiles on the straight line from `from` to `to`, excluding `from`.
##
## Bresenham on the tile grid rather than interpolating screen positions and re-inverting
## each one: the projection is not linear in tile space per pixel, so a screen-space walk
## across a long jump lands unevenly and can still skip a tile. Tile space is where the
## stroke has to be continuous, so that is where the line is drawn.
static func _tiles_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (to - from).abs()
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var err := d.x - d.y
	var at := from
	# BOUNDED, because a bad `from` would otherwise loop forever. The longest legitimate
	# stroke is the map's diagonal, and MAX_SIZE bounds that.
	var guard := d.x + d.y + 2
	while at != to and guard > 0:
		guard -= 1
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			at.x += step.x
		if e2 < d.x:
			err += d.x
			at.y += step.y
		out.append(at)
	return out


## Zoom about the pointer, so the tile under the cursor stays under it.
##
## Zooming about the CENTRE was the first version and it is subtly awful: the thing you are
## looking at slides away as you zoom in on it, so you chase it with the pan. Keeping the
## anchor fixed is two lines and is the difference between a usable canvas and an annoying one.
func _zoom_at(anchor: Vector2, factor: float) -> void:
	var before := (anchor - _pan) / _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_pan = anchor - before * _zoom
	_view_moved()


# ── drawing ─────────────────────────────────────────────────────────────────

## The map: terrain, entities and starts.
##
## **REDRAWN ONLY WHEN THE MAP OR THE VIEW CHANGES.** The cursor is `_draw_overlay`'s, on a
## child item, so a mouse-move does not come through here -- see `_ready()`.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _OUT_OF_BOUNDS)
	if document == null:
		return
	var range_rect := _visible_tile_bounds()
	_draw_terrain(range_rect)
	_draw_entities()
	_draw_starts()


## The hover cursor, and nothing else. Cheap on purpose: this is what repaints on every
## mouse-move.
func _draw_overlay() -> void:
	if document == null or _hover.x < 0:
		return
	var poly := _diamond(_hover)
	_overlay.draw_polyline(poly + PackedVector2Array([poly[0]]), _CURSOR, 2.0)


func _draw_terrain(range_rect: Rect2i) -> void:
	var data := document.data
	var show_grid := _zoom >= 0.5          # below this the outlines are all you would see
	for y in range(range_rect.position.y, range_rect.end.y):
		for x in range(range_rect.position.x, range_rect.end.x):
			var t := Vector2i(x, y)
			if not data.in_bounds(t):
				continue
			var poly := _diamond(t)
			draw_colored_polygon(poly, TERRAIN_COLOURS.get(data.terrain_at(t), Color.MAGENTA))
			if show_grid:
				# Closed explicitly: `draw_polyline` does not close a loop, so without the
				# repeated first point every diamond is missing one of its four edges --
				# which reads as a grid with holes in it rather than as an unclosed path.
				draw_polyline(poly + PackedVector2Array([poly[0]]), _GRID, 1.0)


## Buildings as their footprint, units and resources as a small diamond.
##
## ⚠️ **THE FOOTPRINT COMES FROM `MapData.footprint_rect_of()`**, which asks the roster --
## the same function the generator and the validator use. Drawing a building as one tile, or
## as a size this file decided, would make the canvas disagree with what the map actually
## claims, and overlap would be invisible until the game refused to build the world.
func _draw_entities() -> void:
	for e in document.data.entities:
		var tiles := MapData.footprint_rect_of(e)
		var player := int(e.get("player", 0))
		var is_building := GameDataRegistry.building(e.get("def_id", &"")) != null
		var colour := _GAIA if player == 0 else (_BUILDING if is_building else _UNIT)
		if tiles.size() > 1:
			for t in tiles:
				draw_colored_polygon(_diamond(t), Color(colour, 0.55))
			_outline(tiles[0], colour, 1.0)
		else:
			draw_colored_polygon(_diamond_scaled(tiles[0], 0.55), colour)


## A start marker, with the player's number beside it.
##
## Drawn ON TOP of everything, including the town centre it sits inside, because "where does
## player N begin" is the question an author is asking when they look for it -- and a marker
## hidden under a 10x10 building answers nothing.
func _draw_starts() -> void:
	var font := ThemeDB.fallback_font
	for i in document.data.starts.size():
		var s: Vector2i = document.data.starts[i]
		if s.x < 0:
			continue
		_outline(s, _START, 3.0)
		# The label ABOVE the marker, clear of it. Drawn at the tile's top corner rather than
		# its centre plus an offset: at low zoom a centre-relative nudge lands inside the
		# diamond and the text sits on top of the outline it is labelling.
		var at := _to_screen_f(Vector2(s))
		draw_string(font, at + Vector2(4.0, -6.0), "P%d" % (i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _START)


func _outline(t: Vector2i, colour: Color, width: float) -> void:
	var poly := _diamond(t)
	draw_polyline(poly + PackedVector2Array([poly[0]]), colour, width)


func _diamond(t: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		_to_screen_f(Vector2(t)),
		_to_screen_f(Vector2(t) + Vector2(1, 0)),
		_to_screen_f(Vector2(t) + Vector2(1, 1)),
		_to_screen_f(Vector2(t) + Vector2(0, 1)),
	])


## A diamond shrunk about the tile's centre, for a marker that should read as "on" a tile
## rather than "being" the tile.
func _diamond_scaled(t: Vector2i, factor: float) -> PackedVector2Array:
	var centre := Vector2(t) + Vector2(0.5, 0.5)
	var half := factor * 0.5
	return PackedVector2Array([
		_to_screen_f(centre + Vector2(-half, -half)),
		_to_screen_f(centre + Vector2(half, -half)),
		_to_screen_f(centre + Vector2(half, half)),
		_to_screen_f(centre + Vector2(-half, half)),
	])


func _to_screen_f(tile_frac: Vector2) -> Vector2:
	return Iso.tile_to_world_f(tile_frac) * _zoom + _pan


## The tile range that could possibly be on screen.
##
## See the class comment: the inverse of the projection is a ROTATED rectangle, so this takes
## the min/max over all four screen corners rather than two, and pads by one tile so a
## diamond straddling an edge is not clipped away.
func _visible_tile_bounds() -> Rect2i:
	var corners := [
		Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size,
	]
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for c in corners:
		var t := Iso.world_to_tile_f((c - _pan) / _zoom)
		lo = lo.min(t)
		hi = hi.max(t)
	var pad := Vector2i.ONE * 2
	var from := Vector2i(floori(lo.x), floori(lo.y)) - pad
	var to := Vector2i(ceili(hi.x), ceili(hi.y)) + pad
	# CLAMPED TO THE MAP, so a map panned far off screen costs an empty loop rather than
	# iterating a range the size of the pan.
	from = from.clamp(Vector2i.ZERO, document.data.size)
	to = to.clamp(Vector2i.ZERO, document.data.size)
	return Rect2i(from, to - from)
