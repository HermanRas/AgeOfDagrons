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


# ── the drag stroke ─────────────────────────────────────────────────────────
#
# The owner's playtest of 16.2: *"the tool is very slow look at the single like drag of the
# cursor, some tiles did not place due to lag"*. Two separate faults wearing one symptom, and
# the tests below pin each — because both look like "lag" and neither is.


## ⚠️ **NOTHING WAS DROPPING TILES; NOTHING HAD EVER BEEN ASKED TO PAINT THEM.**
##
## `InputEventMouseMotion` arrives once a frame at best, so a quick stroke jumps several tiles
## between samples. Emitting only the sampled tile paints a dotted line, which reads exactly
## like a tool too slow to keep up — the one diagnosis that sends you optimising the drawing
## instead of fixing the input.
func test_a_fast_drag_paints_a_continuous_line() -> void:
	var from := Vector2i(10, 10)
	var to := Vector2i(20, 26)
	var walked := MapCanvas._tiles_between(from, to)
	assert_eq(walked[walked.size() - 1], to, "the walk has to arrive: %s" % [walked])

	# EVERY STEP TOUCHES THE LAST, which is what "continuous" means for a brush: a chebyshev
	# distance of one, so a diagonal counts and a jump of two does not.
	var previous := from
	for step in walked:
		var d := (step - previous).abs()
		assert_true(maxi(d.x, d.y) == 1,
				"step %s to %s is not adjacent" % [previous, step])
		previous = step


## Both ways, and through the axes -- a Bresenham with a sign error is right in one octant.
func test_the_stroke_is_continuous_in_every_direction() -> void:
	var ends := [
		Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 9), Vector2i(9, 9),
		Vector2i(30, 4), Vector2i(4, 30), Vector2i(40, 41),
	]
	for a in ends:
		for b in ends:
			if a == b:
				continue
			var walked := MapCanvas._tiles_between(a, b)
			assert_eq(walked[walked.size() - 1], b, "%s to %s must arrive" % [a, b])
			var previous: Vector2i = a
			for step in walked:
				var d := (step - previous).abs()
				assert_true(maxi(d.x, d.y) == 1, "%s to %s broke at %s" % [a, b, step])
				previous = step


## The gap is filled by dragging, and this drives it the way a mouse does: press, then one
## motion event a long way off. Both tiles and everything between them must be painted.
func test_dragging_paints_the_tiles_the_pointer_skipped_over() -> void:
	var painted: Array[Vector2i] = []
	canvas.painted.connect(func(t: Vector2i) -> void: painted.append(t))
	canvas.center_on(Vector2i(48, 48), 1.0)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _centre_of(Vector2i(40, 40))
	canvas._button(press)

	var motion := InputEventMouseMotion.new()
	motion.position = _centre_of(Vector2i(46, 44))
	canvas._motion(motion)

	assert_true(painted.has(Vector2i(40, 40)), "the press itself: %s" % [painted])
	assert_true(painted.has(Vector2i(46, 44)), "the far end: %s" % [painted])
	assert_true(painted.size() >= 7,
			"a six-tile jump has to fill in, got %d: %s" % [painted.size(), painted])


## ⚠️ **A RELEASE BREAKS THE STROKE.** Carrying the last sample across it would bridge two
## separate clicks with a painted line between them -- so clicking one corner of the map and
## then the other would draw a diagonal across everything.
func test_two_separate_clicks_are_not_joined_up() -> void:
	var painted: Array[Vector2i] = []
	canvas.painted.connect(func(t: Vector2i) -> void: painted.append(t))
	canvas.center_on(Vector2i(48, 48), 1.0)

	_click(Vector2i(20, 20))
	_click(Vector2i(60, 60))
	assert_eq(painted, [Vector2i(20, 20), Vector2i(60, 60)] as Array[Vector2i])


## Dragging out over the void and back must not paint a line across everything in between.
func test_a_stroke_leaving_the_map_does_not_bridge_across_it() -> void:
	var painted: Array[Vector2i] = []
	canvas.painted.connect(func(t: Vector2i) -> void: painted.append(t))
	canvas.center_on(Vector2i(48, 48), 1.0)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _centre_of(Vector2i(2, 2))
	canvas._button(press)

	var off := InputEventMouseMotion.new()
	off.position = Vector2(-4000.0, -4000.0)
	canvas._motion(off)

	var back := InputEventMouseMotion.new()
	back.position = _centre_of(Vector2i(90, 90))
	canvas._motion(back)

	assert_eq(painted, [Vector2i(2, 2), Vector2i(90, 90)] as Array[Vector2i],
			"an off-map excursion breaks the stroke rather than bridging it")


# ── layering and cost ───────────────────────────────────────────────────────

## ⚠️ **THE MAP DREW OVER THE TOOLBAR** (owner's playtest). A `Control` does not clip its own
## `_draw` to its rect, and this one draws a whole map projected from an arbitrary pan -- so at
## any zoom putting tiles above y=0 they landed on top of the buttons. It reads as a layering
## bug and is one property.
func test_the_canvas_clips_its_drawing_to_its_own_rect() -> void:
	var fresh := _ready_canvas()
	assert_true(fresh.clip_contents, "the map must not draw outside the canvas")
	fresh.free()


## ⚠️ **THE CURSOR ON ITS OWN LAYER IS THE PERFORMANCE FIX, and this is what keeps it there.**
##
## The playtest's "very slow" was not the tile count as such: the hover cursor was drawn in the
## same `_draw` as the terrain, so every mouse-move invalidated the whole map. At fit-to-view a
## 96x96 map is 9,216 tiles and the cull covers all of them, so one drag re-issued ~18,000 draw
## calls per motion event. Godot redraws a `CanvasItem` only when that item is invalidated, so
## a child means moving the mouse repaints four line segments.
##
## **WHAT THIS CAN AND CANNOT CHECK.** A redraw is counted by the renderer on a frame, and this
## harness runs tests on a `RefCounted` with no tree and no frames -- so "the terrain was not
## repainted" is not observable here. What is observable is the *structure the fix depends on*:
## a separate `CanvasItem` for the cursor that does not intercept the canvas's input. If a
## later edit moves the cursor back into `_draw()`, the overlay stops being drawn to and this
## test is where the shape is written down.
func test_the_cursor_has_its_own_canvas_item() -> void:
	var fresh := _ready_canvas()
	assert_true(fresh._overlay != null, "the cursor needs its own layer")
	assert_true(fresh._overlay is CanvasItem,
			"a separate CanvasItem is what makes the redraw independent")
	assert_eq(fresh._overlay.get_parent(), fresh, "and it hangs off the canvas")
	assert_true(fresh._overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the overlay must not eat the presses the canvas needs")
	fresh.free()


## ⚠️ **THE OVERLAY HAS TO STAY THE SAME RECT AS THE CANVAS.** It is a child `Control` with its
## own size, and a cursor drawn into a stale rect is clipped at the old edge -- the diamond
## vanishing near the bottom of a resized window, which reads as a projection fault. This
## canvas is resized constantly: the toolbar wraps, the window is dragged, `Fit` is pressed.
##
## Pinned as the ANCHORS rather than as a size, because the anchors are the mechanism -- the
## layout pass follows the parent on its own. The first version assigned `size` in
## `_on_resized()` as well, which fights them, and Godot said so.
func test_the_cursor_layer_is_anchored_to_the_whole_canvas() -> void:
	var fresh := _ready_canvas()
	assert_almost_eq(fresh._overlay.anchor_right, 1.0, 0.001)
	assert_almost_eq(fresh._overlay.anchor_bottom, 1.0, 0.001)
	assert_almost_eq(fresh._overlay.anchor_left, 0.0, 0.001)
	assert_almost_eq(fresh._overlay.anchor_top, 0.0, 0.001)
	fresh.free()


## And a resize still counts as a view change, because the cull is computed from the rect.
func test_a_resize_redraws_the_map() -> void:
	var fresh := _ready_canvas()
	fresh.show_document(doc)
	var seen := [0]
	fresh.view_changed.connect(func() -> void: seen[0] += 1)
	fresh._on_resized()
	assert_eq(seen[0], 1, "the visible-tile range depends on the size, so it must be redone")
	fresh.free()


# ── the batched projection (16.x-slow-place) ────────────────────────────────
#
# ⚠️ **THESE EXIST BECAUSE THE FIX FOR THE SLOWNESS TOUCHED THE ONE THING THIS FILE'S HEADER
# SAYS MUST NOT BE RE-DERIVED.** `MapCanvas`'s class comment: every tile-to-screen conversion
# goes through the game's own hash-checked `Iso`, and *"re-deriving the projection with a local
# `TILE_SIZE` would have been four lines and would have made the canvas a lie that nothing
# could detect."*
#
# Batching the terrain into one draw command means the corners are computed as
# `o + ex * x + ey * y` rather than by four `Iso` calls a tile — 439 ms of draw calls down to
# ~28 ms, measured by `dev/profile_editor.tscn`. `projection_basis()` takes `o`, `ex` and `ey`
# as **differences of `Iso` projections**, which is exact because `Iso._project` is linear, so
# nothing is written down. **These tests are what make that claim checkable** rather than a
# sentence in a header: the day somebody replaces the basis with `Vector2(32, 16)` for speed,
# or `Iso.TILE_SIZE` changes, this fails instead of the map quietly drawing at the wrong
# proportions in a tool whose whole job is judging proportions.

## The batched corners are `Iso`'s corners, tile by tile.
##
## Checked at the extremes as well as the middle, for the round trip's reason: an error in a
## projection scales with distance from the origin and is invisible where you happen to look.
func test_the_batched_corners_are_the_projections_they_replace() -> void:
	var basis := canvas.projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	for t in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(48, 48),
			Vector2i(95, 95), Vector2i(95, 0), Vector2i(0, 95)]:
		var batched := o + ex * float(t.x) + ey * float(t.y)
		# `_to_screen_f` IS THE ROUTE THE REST OF THIS FILE DRAWS BY, and it ends in
		# `Iso.tile_to_world_f` -- so comparing against it compares against the game's copy.
		assert_almost_eq(batched.x, canvas._to_screen_f(Vector2(t)).x, 0.01,
				"tile %s corner x" % t)
		assert_almost_eq(batched.y, canvas._to_screen_f(Vector2(t)).y, 0.01,
				"tile %s corner y" % t)


## And the other three corners of a tile, which is what the two triangles are wound from.
##
## A basis that had `ex` and `ey` the wrong way round would put every corner in the right PLACE
## and every diamond in the wrong ORIENTATION -- which at fit-to-view is a map that looks
## subtly like a different map, and is exactly the class of fault a screenshot argues about.
func test_a_tiles_four_corners_come_out_in_the_same_order_as_the_diamond() -> void:
	var basis := canvas.projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	for t in [Vector2i(2, 3), Vector2i(70, 12)]:
		var a := o + ex * float(t.x) + ey * float(t.y)
		var batched := PackedVector2Array([a, a + ex, a + ex + ey, a + ey])
		var expected := canvas._diamond(t)
		for i in 4:
			assert_almost_eq(batched[i].x, expected[i].x, 0.01, "tile %s corner %d x" % [t, i])
			assert_almost_eq(batched[i].y, expected[i].y, 0.01, "tile %s corner %d y" % [t, i])


## The basis tracks the view, so a zoom or a pan cannot leave it stale.
##
## ⚠️ **THIS IS THE FAILURE THE BASIS INVITES AND THE PER-TILE VERSION COULD NOT HAVE.** Three
## values computed once and used nine thousand times are three values that could be computed at
## the wrong moment -- cached across a wheel-zoom, say -- and the result is a whole map drawn at
## the previous view while the cursor overlay is at the current one. `_draw_terrain` takes them
## inside the draw for that reason, and this pins it.
func test_the_basis_follows_a_zoom_and_a_pan() -> void:
	canvas._zoom = 2.35
	canvas._pan = Vector2(-317.0, 148.0)
	var basis := canvas.projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	for t in [Vector2i(3, 7), Vector2i(50, 12), Vector2i(80, 80)]:
		var batched := o + ex * float(t.x) + ey * float(t.y)
		var expected := canvas._to_screen_f(Vector2(t))
		assert_almost_eq(batched.x, expected.x, 0.01, "tile %s x after pan/zoom" % t)
		assert_almost_eq(batched.y, expected.y, 0.01, "tile %s y after pan/zoom" % t)
	# AND THE EDGE VECTORS SCALE WITH THE ZOOM, which is the half a corner comparison at one
	# zoom cannot distinguish from a coincidence.
	assert_almost_eq(ex.length(), canvas._to_screen_f(Vector2(1.0, 0.0)).distance_to(o), 0.01)


## The small marker's corners are `_diamond_scaled()`'s corners.
##
## `_draw_entities` reproduces that function's arithmetic from the basis (`factor * 0.5` is the
## 0.275 in the code), so a unit's diamond and the terrain under it are projected by the same
## three vectors. **The two numbers agreeing is the whole check**: a marker drawn from a
## slightly different centre is a unit that does not sit on its tile, which reads as a
## placement bug rather than as a drawing one.
func test_the_small_marker_matches_the_scaled_diamond() -> void:
	var basis := canvas.projection_basis()
	var o: Vector2 = basis[0]
	var ex: Vector2 = basis[1]
	var ey: Vector2 = basis[2]
	var t := Vector2i(40, 22)
	var centre := o + ex * (float(t.x) + 0.5) + ey * (float(t.y) + 0.5)
	var hx := ex * 0.275
	var hy := ey * 0.275
	var batched := PackedVector2Array([centre - hx - hy, centre + hx - hy,
			centre + hx + hy, centre - hx + hy])
	var expected := canvas._diamond_scaled(t, 0.55)
	for i in 4:
		assert_almost_eq(batched[i].x, expected[i].x, 0.01, "marker corner %d x" % i)
		assert_almost_eq(batched[i].y, expected[i].y, 0.01, "marker corner %d y" % i)


## A canvas that has run `_ready()`, without a tree -- which `add_child` does not need. The
## suite's other tests deliberately use one that has NOT, since the projection maths is pure
## and testing it without a window is the point.
func _ready_canvas() -> MapCanvas:
	var fresh := MapCanvas.new()
	fresh._ready()
	# The canvas's own anchors are left alone (only the overlay's are set), so a plain
	# assignment is fine here -- it was assigning the OVERLAY's size that fought its anchors.
	fresh.size = Vector2(1600, 900)
	return fresh


func _click(t: Vector2i) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = _centre_of(t)
	canvas._button(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = down.position
	canvas._button(up)


func _centre_of(t: Vector2i) -> Vector2:
	return canvas._to_screen_f(Vector2(t) + Vector2(0.5, 0.5))
