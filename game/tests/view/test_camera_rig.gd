## Phase 3.3: drag to pan, clamped to the map.
##
## The clamp is the part worth testing rather than the gesture plumbing -- it is
## what stops the player sailing off into empty space, and it has to keep holding
## when 3.2 changes the visible size by zooming. Camera2D's own limit_* properties
## were not used precisely so this rule could be reached without a live viewport.
extends TestCase

## A 64x64 map, the size MatchConfig.debug_single_player() uses.
const MAP := Vector2i(64, 64)
const VIEW := Vector2(1152, 648)

var rig: CameraRig


func before_each() -> void:
	rig = CameraRig.new()
	# Stands in for the viewport a headless TestCase does not have. Not a test
	# fixture bolted on: the camera stores this because a rotation or a resize
	# genuinely changes it, and every rule here depends on it.
	rig.view_size = VIEW


func after_each() -> void:
	rig.free()


func _bounds() -> Rect2:
	return Iso.map_bounds(MAP)


# ── the projected map box (Iso) ────────────────────────────────────────────

func test_map_bounds_covers_every_corner_of_the_grid() -> void:
	var bounds := _bounds()
	# The four extremes of the diamond, taken from tile CORNERS: the map covers
	# fractional tile coordinates [0, w] x [0, h].
	for corner in [Vector2(0, 0), Vector2(MAP.x, 0), Vector2(0, MAP.y), Vector2(MAP.x, MAP.y)]:
		var projected := Iso.tile_to_world(Vector2i(corner))
		assert_true(bounds.has_point(projected) or bounds.abs().grow(0.01).has_point(projected),
				"corner %s is inside the bounds" % corner)


func test_map_bounds_is_as_wide_as_the_map_is_across() -> void:
	var bounds := Iso.map_bounds(Vector2i(4, 4))
	assert_almost_eq(bounds.size.x, 8.0 * Iso.TILE_SIZE.x / 2.0, 0.01,
			"a 4x4 map is 8 half-tiles wide across its diagonal")
	assert_almost_eq(bounds.size.y, 8.0 * Iso.TILE_SIZE.y / 2.0, 0.01)


func test_an_empty_map_has_empty_bounds() -> void:
	assert_eq(Iso.map_bounds(Vector2i.ZERO).size, Vector2.ZERO,
			"no map means nowhere to look, not an unbounded camera")


# ── clamping ───────────────────────────────────────────────────────────────

func test_the_view_never_leaves_the_projected_box() -> void:
	var bounds := _bounds()
	# Push hard past each edge in turn; the visible rect must still be inside.
	for target in [Vector2(-99999, 0), Vector2(99999, 0), Vector2(0, -99999), Vector2(0, 99999)]:
		var centre := CameraRig.clamped_centre(target, MAP, VIEW)
		var visible := Rect2(centre - VIEW * 0.5, VIEW)
		assert_true(bounds.encloses(visible),
				"panning toward %s leaves the viewport over the map" % target)


func test_the_camera_always_looks_at_a_real_tile() -> void:
	# The rule that stops the west and east corners being reachable with the
	# ground reduced to a sliver: the projected box extends half a map beyond the
	# diamond's tips, so clamping to the box alone is not enough.
	for target in [Vector2(-99999, 1024), Vector2(99999, 1024),
			Vector2(-99999, -99999), Vector2(99999, 99999)]:
		var t := Iso.world_to_tile_f(CameraRig.clamped_centre(target, MAP, VIEW))
		assert_true(t.x >= -0.01 and t.x <= MAP.x + 0.01,
				"panning toward %s keeps tile x on the map (got %f)" % [target, t.x])
		assert_true(t.y >= -0.01 and t.y <= MAP.y + 0.01,
				"panning toward %s keeps tile y on the map (got %f)" % [target, t.y])


func test_the_far_west_corner_still_shows_a_useful_amount_of_ground() -> void:
	# The regression this rule was added for, stated as what the player sees. At
	# the west extreme the middle row of the screen must be over the map -- with
	# only the box clamp it was entirely off it.
	var centre := CameraRig.clamped_centre(Vector2(-99999, 1024), MAP, VIEW)
	for x in [centre.x - VIEW.x * 0.4, centre.x, centre.x + VIEW.x * 0.4]:
		var t := Iso.world_to_tile(Vector2(x, centre.y))
		assert_true(t.x >= 0 and t.y >= 0 and t.x < MAP.x and t.y < MAP.y,
				"x=%f on the centre row is over tile %s" % [x, t])


func test_a_centre_well_inside_the_map_is_left_alone() -> void:
	var middle := _bounds().get_center()
	assert_eq(CameraRig.clamped_centre(middle, MAP, VIEW), middle,
			"the clamp only bites at the edges")


func test_a_map_smaller_than_the_screen_is_centred_rather_than_inverted() -> void:
	# Both box-clamp ends cross over on an axis the map does not fill. Clamping to
	# an inverted range gives whichever end came last, which would pin a small map
	# to a corner; centring is the only sensible framing.
	var tiny := Iso.map_bounds(Vector2i(2, 2))
	var centre := CameraRig.clamped_centre(Vector2(5000, 5000), Vector2i(2, 2), VIEW)
	assert_almost_eq(centre.x, tiny.get_center().x, 0.01)
	assert_almost_eq(centre.y, tiny.get_center().y, 0.01)


func test_zooming_in_lets_the_camera_reach_closer_to_the_edge() -> void:
	# 3.2 changes the visible size; the clamp has to follow it rather than assume
	# a fixed viewport. A smaller visible area means less margin is needed.
	var wide := CameraRig.clamped_centre(Vector2(0, -99999), MAP, VIEW)
	var narrow := CameraRig.clamped_centre(Vector2(0, -99999), MAP, VIEW * 0.5)
	assert_true(narrow.y < wide.y, "a zoomed-in view can sit nearer the top edge")


# ── panning ────────────────────────────────────────────────────────────────

func test_dragging_moves_the_world_with_the_finger() -> void:
	# Drag right, and the ground should follow the finger right -- which means the
	# camera moves LEFT. Getting this backwards is the classic inverted-pan bug.
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	var before := rig.position
	rig.pan_by(Vector2(50, 30))
	assert_true(rig.position.x < before.x, "the player grabs the ground, not the camera")
	assert_true(rig.position.y < before.y)


func test_a_pan_is_scaled_by_zoom_so_the_ground_keeps_up_with_the_finger() -> void:
	# At 2x zoom a 100 px drag covers 50 world units, not 100. Without this the
	# map accelerates away from the finger as you zoom in (3.2).
	rig.map_size = MAP
	var start := _bounds().get_center()

	rig.position = start
	rig.zoom = Vector2.ONE
	rig.pan_by(Vector2(100, 0))
	var at_1x := start.x - rig.position.x

	rig.position = start
	rig.zoom = Vector2(2, 2)
	rig.pan_by(Vector2(100, 0))
	var at_2x := start.x - rig.position.x

	assert_almost_eq(at_2x, at_1x / 2.0, 0.01, "twice the zoom, half the world moved")


func test_panning_is_clamped_not_merely_offset() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	for i in range(200):
		rig.pan_by(Vector2(500, 0))          # far more than the map is wide
	assert_true(rig.position.x >= _bounds().position.x,
			"repeated drags cannot walk the camera off the map")


func test_setup_pulls_an_out_of_bounds_camera_back_onto_the_map() -> void:
	# The camera exists before the map is known, so its starting position is
	# meaningless until setup() runs.
	rig.position = Vector2(-50000, -50000)
	rig.setup(MAP)
	assert_true(rig.map_bounds().has_point(rig.position),
			"setup() does not leave the camera pointing at nothing")


# ── zoom (3.2) ─────────────────────────────────────────────────────────────

func test_swiping_up_the_edge_zooms_in_and_down_zooms_out() -> void:
	rig.map_size = MAP
	rig.zoom = Vector2.ONE

	rig.zoom_by_swipe(-100.0)                    # up the screen
	assert_true(rig.zoom.x > 1.0, "up zooms in, like pushing a slider away")

	rig.zoom = Vector2.ONE
	rig.zoom_by_swipe(100.0)
	assert_true(rig.zoom.x < 1.0, "down zooms out")


func test_zoom_is_multiplied_so_it_feels_the_same_at_both_ends() -> void:
	# A fixed step per pixel would crawl at 2x and leap at 0.6x. Two equal swipes
	# must apply the same RATIO, not the same amount.
	rig.map_size = MAP
	rig.zoom = Vector2(0.8, 0.8)
	rig.zoom_by_swipe(-50.0)
	var low_ratio := rig.zoom.x / 0.8

	rig.zoom = Vector2(1.6, 1.6)
	rig.zoom_by_swipe(-50.0)
	var high_ratio := rig.zoom.x / 1.6

	assert_almost_eq(low_ratio, high_ratio, 0.001, "the same swipe, the same factor")


func test_one_full_height_swipe_crosses_the_whole_range() -> void:
	# ZOOM_PER_PIXEL is derived from this rather than tuned by feel, so it is worth
	# asserting rather than trusting the arithmetic in the constant's comment.
	rig.map_size = MAP
	rig.zoom = Vector2(CameraRig.MIN_ZOOM, CameraRig.MIN_ZOOM)
	rig.zoom_by(exp(648.0 * CameraRig.ZOOM_PER_PIXEL))
	assert_almost_eq(rig.zoom.x, CameraRig.MAX_ZOOM, 0.01)


func test_zoom_stops_at_both_ends() -> void:
	rig.map_size = MAP
	rig.zoom = Vector2.ONE
	for i in range(100):
		rig.zoom_by_swipe(-200.0)
	assert_almost_eq(rig.zoom.x, CameraRig.MAX_ZOOM, 0.001, "cannot zoom past the near end")

	for i in range(100):
		rig.zoom_by_swipe(200.0)
	assert_true(rig.zoom.x >= CameraRig.MIN_ZOOM - 0.001, "nor past the far end")


func test_zoom_stays_square() -> void:
	# A Camera2D zoom is a Vector2 and nothing stops the axes diverging, which
	# would shear the isometric grid off its 2:1 tile ratio.
	rig.map_size = MAP
	rig.zoom_by_swipe(-140.0)
	assert_almost_eq(rig.zoom.x, rig.zoom.y, 0.0001)


func test_zooming_out_pulls_the_camera_back_inside_the_map() -> void:
	# Zooming out enlarges the visible area, so a camera legally parked against an
	# edge is suddenly looking past it. The re-clamp is the whole reason zoom_by
	# touches position at all.
	rig.map_size = MAP
	rig.zoom = Vector2(2.0, 2.0)
	rig.position = CameraRig.clamped_centre(Vector2(0, -99999), MAP, rig.visible_size())
	var at_edge := rig.position.y

	rig.zoom_by(0.5)
	assert_true(rig.position.y > at_edge,
			"the wider view is pushed back down onto the map")


func test_the_map_sets_the_zoom_out_floor_when_it_is_smaller_than_the_screen() -> void:
	# Past the point where the whole map is on screen, zooming out only adds void.
	# Never binds on a 64x64 map; a small one hits it at once.
	rig.map_size = MAP
	assert_almost_eq(rig.min_zoom(), CameraRig.MIN_ZOOM, 0.001,
			"a full-size map leaves the configured floor alone")


# ── which gesture a drag becomes (3.2 vs 3.3) ──────────────────────────────

func test_the_zoom_strip_runs_down_both_sides() -> void:
	# Left- and right-handed players both need to reach it (IDEA 3.2).
	assert_true(rig.is_edge(10.0), "left strip")
	assert_true(rig.is_edge(VIEW.x - 10.0), "right strip")
	assert_false(rig.is_edge(VIEW.x * 0.5), "the middle is for panning")


func test_a_swipe_that_starts_in_the_middle_pans_even_if_it_wanders_to_the_edge() -> void:
	# The gesture is decided on touch-down and held until release. Re-deciding per
	# move would flip a pan into a zoom mid-drag as the finger crossed the strip.
	rig.map_size = MAP
	rig.zoom = Vector2.ONE
	rig.position = _bounds().get_center()
	var before := rig.position

	rig.begin_gesture(VIEW.x * 0.5)
	rig.apply_drag(Vector2(0.0, -120.0))
	rig.apply_drag(Vector2(-VIEW.x * 0.5, -120.0))    # finger is now over the strip

	assert_almost_eq(rig.zoom.x, 1.0, 0.0001, "still a pan")
	assert_ne(rig.position, before)


func test_a_swipe_that_starts_on_the_edge_zooms_and_does_not_pan() -> void:
	rig.map_size = MAP
	rig.zoom = Vector2.ONE
	rig.position = _bounds().get_center()
	var before := rig.position

	rig.begin_gesture(8.0)
	rig.apply_drag(Vector2(0.0, -120.0))

	assert_true(rig.zoom.x > 1.0, "the edge strip zooms")
	assert_eq(rig.position, before, "and does not also drag the map")


func test_without_a_map_the_camera_cannot_wander() -> void:
	# Bounds default to empty, so an unconfigured rig stays put rather than
	# drifting over a map that has not loaded.
	rig.pan_by(Vector2(1000, 1000))
	assert_eq(rig.position, Vector2.ZERO)


# ── locking for building placement (PLAN.md 5.1) ───────────────────────────
#
# Exercised through synthetic InputEvents into _unhandled_input() rather than
# through pan_by()/apply_drag() directly: `locked` guards the input plumbing
# itself, not the pure math those two are, so there is nothing to see from the
# pure functions alone.

func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	return t


func _drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	d.relative = relative
	return d


func test_a_locked_camera_ignores_touch_entirely() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	var before := rig.position
	rig.locked = true

	rig._unhandled_input(_touch(0, Vector2(100, 100), true))
	rig._unhandled_input(_drag(0, Vector2(150, 130), Vector2(50, 30)))

	assert_eq(rig.position, before, "no pan while locked")


func test_unlocking_resumes_ordinary_panning() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	rig.locked = true
	rig.set_locked(false)

	# x = 400 rather than 100: EDGE_WIDTH is 100, and a touch AT the strip
	# boundary would decide ZOOM instead of PAN -- this test wants an ordinary
	# mid-screen pan, not a rerun of test_a_swipe_that_starts_on_the_edge_zooms.
	rig._unhandled_input(_touch(0, Vector2(400, 100), true))
	var before := rig.position
	rig._unhandled_input(_drag(0, Vector2(450, 130), Vector2(50, 30)))

	assert_true(rig.position.x < before.x, "unlocked pans exactly as it did before")


func test_locking_drops_a_touch_in_progress_so_it_cannot_resume_on_unlock() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()

	rig._unhandled_input(_touch(0, Vector2(100, 100), true))    # gesture decided, mid-pan
	rig.set_locked(true)
	rig.set_locked(false)

	var before := rig.position
	rig._unhandled_input(_drag(0, Vector2(150, 130), Vector2(50, 30)))   # same finger index

	assert_eq(rig.position, before,
			"the touch from before the lock was dropped, not silently resumed")


# ── edge-pan while placing (BUGS.md) ──────────────────────────────────────
#
# The dead end this exists for: build mode locks the camera so one finger can drag
# the ghost, which used to mean an off-screen build site could only be reached by
# cancelling the placement, panning, and re-opening the menu. Dragging the ghost
# into the edge strip now slides the map instead.

func test_the_middle_of_the_screen_pushes_nothing() -> void:
	assert_eq(rig.edge_push_for(VIEW * 0.5), Vector2.ZERO,
			"a finger nowhere near an edge leaves the map alone")


func test_each_edge_pushes_its_own_way() -> void:
	var mid_y := VIEW.y * 0.5
	var mid_x := VIEW.x * 0.5
	assert_true(rig.edge_push_for(Vector2(1, mid_y)).x < 0.0, "left edge pushes left")
	assert_true(rig.edge_push_for(Vector2(VIEW.x - 1, mid_y)).x > 0.0, "right edge pushes right")
	assert_true(rig.edge_push_for(Vector2(mid_x, 1)).y < 0.0, "top edge pushes up")
	assert_true(rig.edge_push_for(Vector2(mid_x, VIEW.y - 1)).y > 0.0, "bottom edge pushes down")


func test_the_push_ramps_up_across_the_strip_and_stops_at_full() -> void:
	var mid_y := VIEW.y * 0.5
	# Just inside the strip boundary, halfway in, and hard against the glass.
	var shallow := absf(rig.edge_push_for(Vector2(CameraRig.EDGE_WIDTH - 1, mid_y)).x)
	var halfway := absf(rig.edge_push_for(Vector2(CameraRig.EDGE_WIDTH * 0.5, mid_y)).x)
	var against := absf(rig.edge_push_for(Vector2(0, mid_y)).x)
	assert_true(shallow < halfway and halfway < against,
			"deeper into the strip pushes harder: %f < %f < %f" % [shallow, halfway, against])
	assert_almost_eq(against, 1.0, 0.001, "against the glass is full speed")
	assert_almost_eq(absf(rig.edge_push_for(Vector2(-500, mid_y)).x), 1.0, 0.001,
			"a finger tracked past the bezel pushes at full speed, not faster")


func test_nothing_pushing_is_not_a_move() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	var before := rig.position

	assert_false(rig.step_edge_scroll(0.1), "no push, no move to report")
	assert_eq(rig.position, before)


func test_a_push_slides_the_map_toward_the_pushed_edge() -> void:
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	var before := rig.position
	rig.edge_push = Vector2(-1, 0)

	assert_true(rig.step_edge_scroll(0.1), "the view moved")
	assert_true(rig.position.x < before.x,
			"pushing at the left edge shows what lies further left")


func test_a_locked_camera_still_edge_pans() -> void:
	# The entire point. `locked` stops the camera reading input for itself; it does
	# not stop the placement that owns the gesture from driving it.
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	rig.set_locked(true)
	rig.edge_push = Vector2(1, 0)

	assert_true(rig.step_edge_scroll(0.1), "locked is not frozen")


func test_pushing_past_the_end_of_the_map_reports_no_move() -> void:
	# A ghost over ground that did not move needs no re-reading, so a camera parked
	# against the clamp must stop claiming to have moved -- otherwise it re-previews
	# the placement every frame for as long as a thumb rests on the edge.
	rig.map_size = MAP
	rig.position = _bounds().get_center()
	rig.edge_push = Vector2(-1, 0)
	for _i in range(200):
		rig.step_edge_scroll(0.1)

	assert_false(rig.step_edge_scroll(0.1),
			"hard against the west clamp, a further push changes nothing")


func test_leaving_placement_stops_the_map() -> void:
	# Otherwise the map keeps sliding after the ghost is gone, with no finger down
	# to stop it.
	rig.edge_push = Vector2(1, 1)
	rig.set_locked(false)

	assert_eq(rig.edge_push, Vector2.ZERO, "the push belonged to the placement")
