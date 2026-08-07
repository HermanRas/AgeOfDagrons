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
