## PLAN.md 16.2: the iso canvas, and the two things about it that can be tested without eyes.
##
## Most of a canvas needs looking at — whether a river reads as a river is 16.2's screenshot,
## not its test. **Two things do not**, and both are the kind of fault that looks like a
## drawing bug and is arithmetic:
##
##   1. **screen → tile → screen must round-trip**, or the tile you click is not the tile you
##      paint, and the error grows with the distance from the origin so it looks fine in the
##      middle of the map;
##   2. **the visible-tile cull must cover the whole viewport.** The inverse of an iso
##      projection is a ROTATED rectangle, so bounds taken from two corners instead of four
##      leave tiles undrawn at two edges of the screen — which reads as a rendering fault
##      rather than as a culling one.
extends TestCase

var canvas: MapCanvas = null
var doc: MapDocument = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(96, 96), "Canvas Test")
	canvas = MapCanvas.new()
	# A Control outside a tree has never had a layout pass, so the size is set by hand --
	# the same reason `preview_scenario_hud` exists on the game side. Without this every
	# bound is computed against a zero rect and every assertion below passes vacuously.
	canvas.size = Vector2(1600, 900)
	canvas.show_document(doc)


func after_each() -> void:
	canvas.free()


# ── the round trip ──────────────────────────────────────────────────────────

## Click a tile's centre, get that tile back. Checked across the whole map rather than near
## the origin, because a projection error scales with distance and is invisible in the middle.
func test_a_tile_centre_maps_back_to_its_own_tile() -> void:
	for t in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(48, 48),
			Vector2i(95, 95), Vector2i(95, 0), Vector2i(0, 95)]:
		var screen := _centre_of(t)
		assert_eq(canvas.tile_at(screen), t, "tile %s round-trips" % t)


## And it still holds after panning and zooming, which is what would break if the inverse
## used a stale zoom or forgot the pan.
func test_the_round_trip_survives_pan_and_zoom() -> void:
	canvas._zoom = 2.35
	canvas._pan = Vector2(-317.0, 148.0)
	for t in [Vector2i(3, 7), Vector2i(50, 12), Vector2i(80, 80)]:
		assert_eq(canvas.tile_at(_centre_of(t)), t, "tile %s after pan/zoom" % t)


func test_a_point_off_the_map_reports_no_tile() -> void:
	# Far outside in tile space, whichever way the projection leans.
	assert_eq(canvas.tile_at(Vector2(-100000.0, -100000.0)), Vector2i(-1, -1))
	assert_eq(canvas.tile_at(Vector2(100000.0, 100000.0)), Vector2i(-1, -1))


# ── the cull ────────────────────────────────────────────────────────────────

## ⚠️ **THE ONE THAT WOULD HAVE CAUGHT A TWO-CORNER BOUND.** Every tile whose centre is
## inside the viewport must be inside the range `_draw_terrain` iterates. A bound taken from
## the top-left and bottom-right corners alone passes a spot check in the middle of the
## screen and drops the left and right extremes, because those come from the OTHER two
## corners once the projection has rotated the rectangle 45 degrees.
func test_the_visible_bounds_cover_every_tile_on_screen() -> void:
	canvas._zoom = 1.0
	canvas._pan = Vector2(800.0, 100.0)
	var bounds := canvas._visible_tile_bounds()
	var checked := 0
	for y in range(doc.data.size.y):
		for x in range(doc.data.size.x):
			var t := Vector2i(x, y)
			var at := _centre_of(t)
			if at.x < 0.0 or at.y < 0.0 or at.x > 1600.0 or at.y > 900.0:
				continue
			checked += 1
			assert_true(bounds.has_point(t),
					"tile %s is on screen at %s but outside the drawn range %s"
					% [t, at, bounds])
	assert_true(checked > 50, "the test only means something if tiles were on screen: %d"
			% checked)


## And the bounds never leave the map, so a map panned far away costs an empty loop rather
## than iterating a range the size of the pan.
func test_the_bounds_are_clamped_to_the_map() -> void:
	canvas._pan = Vector2(-50000.0, -50000.0)
	var bounds := canvas._visible_tile_bounds()
	assert_true(bounds.position.x >= 0 and bounds.position.y >= 0, str(bounds))
	assert_true(bounds.end.x <= doc.data.size.x and bounds.end.y <= doc.data.size.y,
			str(bounds))


# ── framing ─────────────────────────────────────────────────────────────────

## Opening at 1:1 in a corner makes a 192x192 map look like an empty green wedge, which is
## indistinguishable from a broken canvas -- so a new map is framed.
func test_fit_to_view_puts_the_whole_map_on_screen() -> void:
	canvas.fit_to_view()
	for t in [Vector2i(0, 0), Vector2i(95, 0), Vector2i(0, 95), Vector2i(95, 95)]:
		var at := _centre_of(t)
		assert_true(at.x >= 0.0 and at.x <= 1600.0 and at.y >= 0.0 and at.y <= 900.0,
				"corner %s lands at %s" % [t, at])


func test_fitting_a_bigger_map_zooms_out_further() -> void:
	canvas.fit_to_view()
	var small := canvas.zoom()
	canvas.show_document(MapDocument.create(Vector2i(192, 192), "Big"))
	assert_true(canvas.zoom() < small, "%f should be tighter than %f" % [canvas.zoom(), small])


## ⚠️ **THIS IS THE TEST THAT FOUND `MIN_ZOOM` WAS SET TOO HIGH TO USE.** The floor was 0.25,
## and fitting even a 96x96 map needs 0.24 — so the tool would have opened every real map
## clamped, showing a corner of it, which reads as a broken canvas. The floor is now derived
## from `MapDocument.MAX_SIZE`, and this asserts the derivation holds at both ends rather than
## trusting the arithmetic in the comment.
func test_the_zoom_floor_can_fit_the_largest_allowed_map() -> void:
	for side in [MapDocument.MIN_SIZE, 96, 192, MapDocument.MAX_SIZE]:
		canvas.show_document(MapDocument.create(Vector2i(side, side), "Size %d" % side))
		canvas.fit_to_view()
		assert_true(canvas.zoom() > MapCanvas.MIN_ZOOM,
				"a %dx%d map must fit without hitting the floor (zoom %f)"
				% [side, side, canvas.zoom()])
		for t in [Vector2i(0, 0), Vector2i(side - 1, side - 1)]:
			var at := _centre_of(t)
			assert_true(at.x >= 0.0 and at.x <= 1600.0 and at.y >= 0.0 and at.y <= 900.0,
					"corner %s of a %d map lands at %s" % [t, side, at])


func test_zoom_stays_within_its_limits() -> void:
	for i in 40:
		canvas._zoom_at(Vector2(800, 450), 1.5)
	assert_true(canvas.zoom() <= MapCanvas.MAX_ZOOM)
	for i in 40:
		canvas._zoom_at(Vector2(800, 450), 0.5)
	assert_true(canvas.zoom() >= MapCanvas.MIN_ZOOM)


## Zooming about the CENTRE makes the thing you are looking at slide away as you zoom in on
## it, so you chase it with the pan. The anchor staying put is the difference between a
## usable canvas and an annoying one.
func test_zooming_keeps_the_tile_under_the_pointer_under_it() -> void:
	var anchor := Vector2(640.0, 380.0)
	var before := canvas.tile_at(anchor)
	canvas._zoom_at(anchor, 1.4)
	assert_eq(canvas.tile_at(anchor), before, "the tile under the cursor must not move")


## The canvas draws through the hash-checked copy of the game's `Iso`, which is the whole
## reason `format/` exists: a diamond drawn here is the diamond the game draws. A local
## `TILE_SIZE` would have been four lines and a lie nothing could detect.
func test_the_canvas_projects_through_the_games_own_iso() -> void:
	canvas._zoom = 1.0
	canvas._pan = Vector2.ZERO
	assert_eq(canvas._to_screen_f(Vector2(3, 5)), Iso.tile_to_world_f(Vector2(3, 5)))


# ── the view-changed signal ─────────────────────────────────────────────────

## ⚠️ **THE STATUS LINE WAS LYING AND A SCREENSHOT CAUGHT IT.** The editor reports the zoom by
## asking `zoom()`, but it only asked when a hover or a paint refreshed the status — and a
## mouse wheel moves neither the pointer's tile nor the map, so scrolling changed the view and
## left the readout on the old figure indefinitely. The shot said 0.23x while the canvas was
## at 1.20x. **A number on screen that is quietly stale is worse than no number, because it
## gets believed**, so every path that moves the view now announces it and this is what keeps
## that true.
func test_every_view_change_announces_itself() -> void:
	var seen := [0]
	canvas.view_changed.connect(func() -> void: seen[0] += 1)

	canvas._zoom_at(Vector2(800, 450), 1.2)
	assert_eq(seen[0], 1, "zooming announces")

	canvas.center_on(Vector2i(10, 10), 1.5)
	assert_eq(seen[0], 2, "centring announces")

	canvas.fit_to_view()
	assert_eq(seen[0], 3, "fitting announces")

	# And panning, which is the other half of the same problem.
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_MIDDLE
	drag.pressed = true
	canvas._button(drag)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, 12.0)
	canvas._motion(motion)
	assert_eq(seen[0], 4, "panning announces")


## Centring is what a preview and 16.4a use to frame something, so it has to actually centre.
func test_centring_puts_the_tile_in_the_middle() -> void:
	canvas.center_on(Vector2i(70, 20), 1.0)
	var at := _centre_of(Vector2i(70, 20))
	assert_almost_eq(at.x, canvas.size.x * 0.5, 0.5)
	assert_almost_eq(at.y, canvas.size.y * 0.5, 0.5)


func _centre_of(t: Vector2i) -> Vector2:
	return canvas._to_screen_f(Vector2(t) + Vector2(0.5, 0.5))
