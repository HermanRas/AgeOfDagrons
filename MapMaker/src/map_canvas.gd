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
## ## THE WHOLE MAP IS ONE DRAW COMMAND, AND THAT IS MEASURED RATHER THAN ASSUMED
##
## ⚠️ **9,216 `draw_colored_polygon` CALLS COST 439 ms AND THE SAME 9,216 DIAMONDS COST 54 ms
## TO WORK OUT.** Measured by `dev/profile_editor.tscn` on `maps/sample_duel` at fit-to-view,
## 2026-09-08, after the owner reported *"3 sec between click and place of buildings"*: the
## projection was 12% of the redraw and the **draw commands were the other 88%**, at ~42
## microseconds each. The renderer here is the OpenGL compatibility backend on an Intel Iris
## Xe, where a filled polygon is its own batch.
##
## So the terrain is assembled into ONE triangle array and issued as **one command**
## (`RenderingServer.canvas_item_add_triangle_array`), the grid as **one** `draw_multiline`,
## and the entity footprints as **one** more. Click-to-drawn on that map went from ~1,400 ms to
## the figure `dev/profile_editor.tscn` prints today.
##
## ⚠️ **AND THE HALF THAT IS NOT ABOUT CLICKING.** A `CanvasItem`'s commands are re-rendered
## **every frame**, not once per `_draw` — so nine thousand of them made the tool run at 22 fps
## sitting still, with nothing happening and no redraw in flight. That is why the owner's report
## opens with *"the tool is very very slow"* and only then names one operation: every click,
## drag and keystroke was waiting behind the same command list.
##
## ⚠️ **THE PROJECTION IS STILL `Iso`'s — THE BASIS IS READ OUT OF IT, NEVER WRITTEN DOWN.**
## Batching means the four corners of tile (x, y) are computed as `o + ex * x + ey * y` rather
## than by four calls, and the temptation is to write `ex = Vector2(32, 16)` and be done. That
## is exactly the *"lie that nothing could detect"* this file's header warns about one section
## up. Instead `o`, `ex` and `ey` are **differences of `Iso` projections** — which is exact,
## because `Iso._project` is linear — so the geometry still comes from the game's own file, and
## `test_map_canvas` compares the batched corners against `Iso.tile_to_world_f()` tile by tile
## so a drift in either direction fails the suite.
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
const START_COLOUR := Color(1.0, 0.45, 0.35)
const _OUT_OF_BOUNDS := Color(0.07, 0.07, 0.09)

## The selected entity's outline (PLAN.md 16.4).
##
## ⚠️ **CYAN, WHICH IS THE ONE HUE NOTHING ELSE ON THIS CANVAS USES.** `START_COLOUR` is orange-red,
## buildings are straw, units white, gaia green and the hover cursor white — so a selection in
## any of those would be a highlight an author has to work out rather than see. It is also drawn
## **thicker than the hover cursor and on the overlay**, so it survives being under a start
## marker and does not disappear the instant the pointer moves off it.
const _SELECTED := Color(0.35, 0.90, 0.95)

## A named region's outline and its fill (PLAN.md 16.5).
##
## ⚠️ **MAGENTA, WHICH IS THE LAST FREE HUE ON THIS CANVAS AND IS NOT THE GAME'S MAGENTA.** Every
## other colour here is taken: terrain is green/brown/blue/grey, buildings straw, units white,
## gaia green, a start orange-red, a selection cyan. A region has to be tellable from all of them
## **while drawn over them**, which is stricter than the selection's requirement — a selection is
## one outline and a region can cover a quarter of the map. Worth naming that this is *not* the
## game's `PlaceholderSpec.UNKNOWN_COLOR`: there, magenta means *"this is a bug"*; here it means a
## deliberate authoring overlay, and the two never appear in the same window.
##
## **THE FILL IS DELIBERATELY FAINT (0.10) AND THE EDGE IS NOT.** A region is drawn over ground an
## author still has to read — the whole point of it is to say something about what is standing
## there — so a wash that obscured the terrain would make regions and map editing exclusive. At
## 0.10 an overlap of two regions is still visibly darker than one, which is how an author sees
## that they have two.
const AREA_COLOUR := Color(0.95, 0.35, 0.85)
const _AREA_FILL := Color(0.95, 0.35, 0.85, 0.10)

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

## The left button went down, and came up again (PLAN.md 16.2a).
##
## ⚠️ **THE CANVAS IS THE ONLY THING THAT KNOWS WHERE A GESTURE BEGINS AND ENDS**, which is why
## undo needed two more signals rather than being able to work it out downstream. `painted`
## arrives per tile and a stroke across a coastline is hundreds of them — indistinguishable,
## from the editor's side, from hundreds of separate clicks. So the pair of presses is reported
## as such and `MapDocument.begin_stroke()` turns the run into one undo step.
##
## **STILL NO TOOL STATE HERE.** These say what the mouse did, not what it meant; the editor
## goes on being the only thing that knows a tool is armed.
signal stroke_began
signal stroke_ended

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

## The rectangle an AREA drag is currently describing, drawn on the overlay (PLAN.md 16.5).
## An empty rect means no drag is running.
##
## ⚠️ **THE EDITOR OWNS THE GESTURE AND THIS CANVAS ONLY DRAWS IT**, which is why this is a
## field rather than the canvas working the rectangle out for itself. `MapCanvas` reports tiles
## and knows nothing about tools — the same division that keeps `painted` from having to say
## whether a sample was a press. `MapDocument.selected` is read the same way, and
## `redraw_overlay()`'s note explains why both live on the cheap layer.
var pending_area := Rect2i()

## What the last `_draw()` cost, in microseconds, split by phase, plus how many tiles the cull
## covered. Written on every redraw and read by `dev/profile_editor.gd`.
##
## ⚠️ **THIS IS INSTRUMENTATION IN PRODUCTION CODE AND IT IS DELIBERATE.** Two slowness reports
## have now come off the owner's machine (2026-09-04, *"the tool is very slow"*; 2026-09-08,
## *"3 sec between click and place"*) and **neither could be answered by reading this file** —
## every candidate is cheap on paper at these sizes, and the first diagnosis that sounded right
## was wrong about which item was being invalidated. The project has also paid for optimising
## without a number: reordering two checks in `SimMap.is_terrain_passable` blew the tick budget
## in three tests to fix one domain.
##
## So the cost of a redraw is a **reading the tool takes of itself**, not an inference. It is
## four `Time.get_ticks_usec()` calls and two integer stores per redraw, against ~9,000
## `draw_colored_polygon` calls in the same function — unmeasurable next to the thing it
## measures, and the reason a third report can be answered in one command.
##
## **Nothing draws from these and nothing branches on them.** A counter the tool reacted to
## would be a second, invisible input to what an author sees.
var last_draw_usec := 0
var last_terrain_usec := 0
var last_entities_usec := 0
var last_tiles_culled := 0

## How many times `_draw()` has run. **A COUNT IS THE HALF A DURATION CANNOT REPORT:** ten cheap
## redraws for one click is a different fault from one expensive one, wants a different fix, and
## looks identical from the outside.
var draws := 0

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
				# ⚠️ **BEFORE THE FIRST TILE, so the step is open when it arrives.** The press
				# paints immediately (that is what makes a single click place a single thing),
				# so a stroke announced afterwards would leave the first tile of every gesture
				# in an undo step of its own -- and undoing a drag would leave one tile painted.
				stroke_began.emit()
				_emit_paint(e.position)
			else:
				# ⚠️ **A RELEASE REACHES THIS CONTROL EVEN WHEN THE POINTER HAS LEFT IT**, because
				# the viewport keeps sending to whichever Control took the press until the button
				# comes up. That is what makes closing the step here reliable -- and
				# `MapDocument.begin_stroke()` still closes any stale one, for the cases the
				# viewport cannot cover (a window losing focus mid-drag).
				stroke_ended.emit()
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
	var t0 := Time.get_ticks_usec()
	draws += 1
	draw_rect(Rect2(Vector2.ZERO, size), _OUT_OF_BOUNDS)
	if document == null:
		return
	var range_rect := _visible_tile_bounds()
	last_tiles_culled = range_rect.size.x * range_rect.size.y
	_draw_terrain(range_rect)
	var t1 := Time.get_ticks_usec()
	_draw_entities()
	var t2 := Time.get_ticks_usec()
	# AREAS BETWEEN THE ENTITIES AND THE STARTS, and the order is the whole design of the
	# overlay: a region is drawn OVER the things it describes (so an author can see that the
	# villagers are inside it) and UNDER the start markers, which `_draw_starts()` explains must
	# stay on top of everything. Not folded into `_draw_entities`' phase timer either -- it is a
	# handful of quads against that function's hundreds, and a figure that lumped them would hide
	# which half a slow redraw was in.
	_draw_areas()
	_draw_starts()
	# THE PHASES, so a slow redraw says WHICH half is slow. Terrain scales with the cull and
	# entities with the map's contents, and the two want opposite fixes.
	last_terrain_usec = t1 - t0
	last_entities_usec = t2 - t1
	last_draw_usec = Time.get_ticks_usec() - t0


## The hover cursor, and nothing else. Cheap on purpose: this is what repaints on every
## mouse-move.
func _draw_overlay() -> void:
	if document == null:
		return
	# ⚠️ **THE SELECTION IS ON THIS LAYER AND NOT IN `_draw()`, WHICH IS NOT WHERE IT WANTS TO
	# BE.** It belongs with the entities it outlines — except that a MOVE drag changes it many
	# times a second, and this file's whole performance story (16.x-slow-place) is that the map
	# layer must be invalidated only when the MAP changes. Selecting is not a change to the map.
	# So the cheap layer draws it, and `MapDocument.selected` is read here rather than cached,
	# because a cached copy is the third thing that would need invalidating.
	if document.selected >= 0 and document.selected < document.data.entities.size():
		for t in MapData.footprint_rect_of(document.data.entities[document.selected]):
			var sel := _diamond(t)
			_overlay.draw_polyline(sel + PackedVector2Array([sel[0]]), _SELECTED, 2.5)
	# THE AREA DRAG'S LIVE RECTANGLE (16.5). On this layer for the selection's reason — it moves
	# many times a second and nothing about the map has changed — and drawn as the same
	# parallelogram `_draw_areas()` produces, so what an author sees while dragging is what they
	# get on release rather than an approximation of it.
	if pending_area.size.x > 0 and pending_area.size.y > 0:
		var box := _area_quad(pending_area)
		_overlay.draw_colored_polygon(box, _AREA_FILL)
		_overlay.draw_polyline(box + PackedVector2Array([box[0]]), AREA_COLOUR, 2.0)
	if _hover.x < 0:
		return
	var poly := _diamond(_hover)
	_overlay.draw_polyline(poly + PackedVector2Array([poly[0]]), _CURSOR, 2.0)


## Redraw the cursor layer, which is where the selection is drawn.
##
## Public because the EDITOR is what changes the selection and the canvas cannot see it happen —
## `document.selected` is a field, not a signal. Named rather than exposing `_overlay` so a
## caller cannot invalidate the expensive layer by accident, which is the mistake this file's
## header is about.
func redraw_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


## Every visible tile, as ONE triangle array and ONE multiline.
##
## See the class comment for the measurement that made this batched rather than a call per
## tile. The arrays are sized once and written by index — `push_back` per corner is a
## reallocation check per corner, and there are four corners a tile.
func _draw_terrain(range_rect: Rect2i) -> void:
	var data := document.data
	var show_grid := _zoom >= 0.5          # below this the outlines are all you would see
	var basis := projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]

	# EVERY TILE IN THE RANGE IS IN BOUNDS -- `_visible_tile_bounds()` clamps to the map -- so
	# the arrays are sized exactly and the loop never has to grow them. The `in_bounds` guard
	# below stays anyway, and `used` is what gets kept: a range that ever stopped being clamped
	# would draw fewer tiles rather than read off the end of the arrays.
	var tiles := range_rect.size.x * range_rect.size.y
	if tiles <= 0:
		return
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	points.resize(tiles * 4)
	colours.resize(tiles * 4)
	indices.resize(tiles * 6)
	var lines := PackedVector2Array()
	if show_grid:
		lines.resize(tiles * 8)
	var used := 0

	for y in range(range_rect.position.y, range_rect.end.y):
		for x in range(range_rect.position.x, range_rect.end.x):
			var t := Vector2i(x, y)
			if not data.in_bounds(t):
				continue
			# THE FOUR CORNERS, from the basis rather than from four `Iso` calls. Multiplied
			# rather than accumulated along the row: an accumulation drifts, and drift in a
			# projection shows up as tiles that do not meet.
			var a := o + ex * float(x) + ey * float(y)
			var b := a + ex
			var c := b + ey
			var d := a + ey
			var v := used * 4
			points[v] = a
			points[v + 1] = b
			points[v + 2] = c
			points[v + 3] = d
			var colour: Color = TERRAIN_COLOURS.get(data.terrain_at(t), Color.MAGENTA)
			colours[v] = colour
			colours[v + 1] = colour
			colours[v + 2] = colour
			colours[v + 3] = colour
			# TWO TRIANGLES, wound the same way for every tile. A diamond is convex, so any
			# fan works and this is the cheapest one to write.
			var i := used * 6
			indices[i] = v
			indices[i + 1] = v + 1
			indices[i + 2] = v + 2
			indices[i + 3] = v
			indices[i + 4] = v + 2
			indices[i + 5] = v + 3
			if show_grid:
				# ALL FOUR EDGES PER TILE, which draws the shared ones twice and is still one
				# command. `draw_multiline` takes point PAIRS, so there is no closing-point
				# problem here -- unlike `draw_polyline`, which left every diamond missing an
				# edge until the first point was repeated.
				var l := used * 8
				lines[l] = a
				lines[l + 1] = b
				lines[l + 2] = b
				lines[l + 3] = c
				lines[l + 4] = c
				lines[l + 5] = d
				lines[l + 6] = d
				lines[l + 7] = a
			used += 1

	if used < tiles:
		points.resize(used * 4)
		colours.resize(used * 4)
		indices.resize(used * 6)
		if show_grid:
			lines.resize(used * 8)
	if used == 0:
		return
	# ONE COMMAND FOR THE WHOLE MAP. `RenderingServer` rather than a `CanvasItem` method because
	# there is no `draw_triangle_array` -- `draw_colored_polygon` is the per-polygon call this
	# exists to stop making. The item is this control's own, so clipping and the canvas
	# transform apply exactly as they did.
	RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), indices, points, colours)
	if show_grid:
		draw_multiline(lines, _GRID, 1.0)


## The iso projection as an origin and two edge vectors, in this control's local space.
##
## ⚠️ **DIFFERENCES OF `Iso` PROJECTIONS, NEVER A WRITTEN-DOWN BASIS.** `Iso._project` is
## linear, so `f(x, y) == f(0,0) + x*(f(1,0) - f(0,0)) + y*(f(0,1) - f(0,0))` is exact rather
## than approximate — and taking it this way means the batched draw is still using the game's
## own projection, at the current zoom and pan, with no second copy of `TILE_SIZE` anywhere.
## The class comment explains why that mattered enough to be a named function.
##
## Public so `test_map_canvas` can compare it against `Iso.tile_to_world_f()` tile by tile,
## which is the check that makes the batching safe to have done at all.
func projection_basis() -> Array:
	var o := _to_screen_f(Vector2.ZERO)
	return [o, _to_screen_f(Vector2(1.0, 0.0)) - o, _to_screen_f(Vector2(0.0, 1.0)) - o]


## Buildings as their footprint, units and resources as a small diamond.
##
## ⚠️ **THE FOOTPRINT COMES FROM `MapData.footprint_rect_of()`**, which asks the roster --
## the same function the generator and the validator use. Drawing a building as one tile, or
## as a size this file decided, would make the canvas disagree with what the map actually
## claims, and overlap would be invisible until the game refused to build the world.
## ⚠️ **ONE COMMAND FOR EVERY FOOTPRINT ON THE MAP, for the same measured reason the terrain is
## batched — and this half is worse per entity than it looks.** A 10x10 town centre is a hundred
## filled diamonds, so `sample_duel`'s 154 entities were ~400 polygon calls and 30 ms of the
## redraw. The outlines stay individual `draw_polyline` calls: there is one per *multi-tile*
## entity, which is tens rather than thousands, and batching those would mean a colour per line
## segment for no measurable gain.
## ⚠️ **THE QUADS ARE COLLECTED FIRST AND WRITTEN INTO THE PACKED ARRAYS IN ONE PLACE, and that
## shape is not stylistic.** The obvious version is an `_add_quad(points, colours, indices, …)`
## helper called from both branches — and it would be **silently wrong**: a `PackedVector2Array`
## argument is a copy-on-write value, so appends inside the helper land on the callee's copy and
## the caller's array stays empty. Nothing errors; the entities simply do not draw. That is the
## same trap `MapEdit._write_terrain()` is written around, met from the argument side rather
## than the assignment side, so the arrays are only ever touched by the function that owns them.
func _draw_entities() -> void:
	var basis := projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	# Each entry is `[a, b, c, d, colour]` in screen space. The outlines cannot share the fills'
	# array and have to be drawn after it, so they are collected separately.
	var quads: Array = []
	var outlines: Array = []

	for e in document.data.entities:
		var tiles := MapData.footprint_rect_of(e)
		var player := int(e.get("player", 0))
		var is_building := GameDataRegistry.building(e.get("def_id", &"")) != null
		var colour := _GAIA if player == 0 else (_BUILDING if is_building else _UNIT)
		if tiles.size() > 1:
			var faded := Color(colour, 0.55)
			for t in tiles:
				var a := o + ex * float(t.x) + ey * float(t.y)
				quads.append([a, a + ex, a + ex + ey, a + ey, faded])
			outlines.append([tiles[0], colour])
		else:
			# THE SMALL MARKER, shrunk about the tile's CENTRE -- `_diamond_scaled()`'s
			# arithmetic, reproduced from the basis so a unit and the terrain under it are
			# projected by the same three vectors. 0.275 is that function's `factor * 0.5`.
			var centre := o + ex * (float(tiles[0].x) + 0.5) + ey * (float(tiles[0].y) + 0.5)
			var hx := ex * 0.275
			var hy := ey * 0.275
			quads.append([centre - hx - hy, centre + hx - hy, centre + hx + hy,
					centre - hx + hy, colour])

	if not quads.is_empty():
		var points := PackedVector2Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		points.resize(quads.size() * 4)
		colours.resize(quads.size() * 4)
		indices.resize(quads.size() * 6)
		for n in quads.size():
			var q: Array = quads[n]
			var v := n * 4
			points[v] = q[0]
			points[v + 1] = q[1]
			points[v + 2] = q[2]
			points[v + 3] = q[3]
			colours[v] = q[4]
			colours[v + 1] = q[4]
			colours[v + 2] = q[4]
			colours[v + 3] = q[4]
			var i := n * 6
			indices[i] = v
			indices[i + 1] = v + 1
			indices[i + 2] = v + 2
			indices[i + 3] = v
			indices[i + 4] = v + 2
			indices[i + 5] = v + 3
		RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(), indices, points, colours)
	for row in outlines:
		_outline(row[0], row[1], 1.0)


## The named regions (PLAN.md 16.5): a faint wash, an outline, and the name once per rectangle.
##
## ## FOUR CORNERS OF THE WHOLE RECT, NOT A DIAMOND PER TILE
##
## ⚠️ **A REGION IS A `Rect2i` IN TILE SPACE AND ITS PROJECTION IS A PARALLELOGRAM**, because
## `Iso._project` is linear: the four screen corners of the rect ARE the four corners of the
## drawn shape, and every tile inside it is inside them. So one quad draws a 20x20 region rather
## than 400 diamonds — which is not a micro-optimisation but 16.x-slow-place's actual finding
## applied before it can bite: 9,216 `draw_colored_polygon` calls cost 439 ms on this machine,
## and a handful of regions on a large map is that order again.
##
## The corners go through `_to_screen_f()` like everything else here, so the geometry still comes
## from the game's hash-checked `Iso` and there is no second projection in this file.
##
## ## THE NAME IS DRAWN PER RECTANGLE, AND THAT IS THE HONEST CHOICE
##
## A region can be several rectangles (`MapData.areas` is flat, and a region is the union of the
## entries sharing a name), so "once per region" would mean picking one rectangle to label and
## leaving the others anonymous — and an author looking at an unlabelled magenta box would have
## no way to tell which region it belongs to, or that it belongs to one at all. Repeating the
## name is noisier and answers the question every box raises.
func _draw_areas() -> void:
	var font := ThemeDB.fallback_font
	for a in document.data.areas:
		var rect: Rect2i = a.get("rect", Rect2i())
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var quad := _area_quad(rect)
		draw_colored_polygon(quad, _AREA_FILL)
		draw_polyline(quad + PackedVector2Array([quad[0]]), AREA_COLOUR, 2.0)
		# AT THE REGION'S TOP CORNER, which in this projection is the tile-space origin -- the
		# same anchor `_draw_starts()` labels from, and for its reason: a centre-relative offset
		# lands inside the shape at low zoom and the text sits on the fill it is naming.
		draw_string(font, quad[0] + Vector2(6.0, -6.0), String(a.get("name", &"")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, AREA_COLOUR)


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
		_outline(s, START_COLOUR, 3.0)
		# The label ABOVE the marker, clear of it. Drawn at the tile's top corner rather than
		# its centre plus an offset: at low zoom a centre-relative nudge lands inside the
		# diamond and the text sits on top of the outline it is labelling.
		var at := _to_screen_f(Vector2(s))
		draw_string(font, at + Vector2(4.0, -6.0), "P%d" % (i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, START_COLOUR)


## A tile-space rect as its four screen corners, in order.
##
## Shared by `_draw_areas()` and the overlay's drag preview so the two cannot disagree about what
## a rectangle looks like — the live shape under the pointer IS the shape that gets saved.
##
## ⚠️ **`end` IS EXCLUSIVE, SO THE FAR CORNER IS `end` AND NOT `end - ONE`.** In TILE space the
## region covers tiles up to `end - ONE`, and its screen outline runs to the far edge of those
## tiles, which is the fractional coordinate `end`. Using `end - ONE` here would draw a box one
## tile short on both axes — visibly wrong at high zoom and invisible at low, which is the worse
## of the two ways to get it wrong.
func _area_quad(rect: Rect2i) -> PackedVector2Array:
	var lo := Vector2(rect.position)
	var hi := Vector2(rect.end)
	return PackedVector2Array([
		_to_screen_f(lo),
		_to_screen_f(Vector2(hi.x, lo.y)),
		_to_screen_f(hi),
		_to_screen_f(Vector2(lo.x, hi.y)),
	])


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
