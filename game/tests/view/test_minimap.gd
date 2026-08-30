## PLAN.md 8.2a (minimap), 3.4/3.8 (its tap gestures).
extends TestCase

var map: Minimap


func before_each() -> void:
	map = Minimap.new()


func after_each() -> void:
	map.free()


func _touch(pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = pressed
	return e


func _grass(w: int, h: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	for i in range(w * h):
		bytes.append(SimMap.Terrain.GRASS)
	return bytes


func test_build_terrain_accepts_a_valid_grid() -> void:
	map.build_terrain(Vector2i(2, 2), _grass(2, 2))
	assert_not_null(map._terrain_tex)


func test_build_terrain_rejects_a_short_array() -> void:
	map.build_terrain(Vector2i(4, 4), PackedByteArray([0, 0]))
	assert_null(map._terrain_tex)


func test_update_entities_colors_the_local_owner_differently_from_others_and_gaia() -> void:
	map.update_entities({
		1: {"tile": Vector2i(1, 1), "owner_id": 1, "alive": true},
		2: {"tile": Vector2i(2, 2), "owner_id": 2, "alive": true},
		3: {"tile": Vector2i(3, 3), "owner_id": 0, "alive": true},
	}, 1)
	assert_eq(map._blips.size(), 3)

	var colors := {}
	for b in map._blips:
		colors[b["tile"]] = b["color"]
	assert_eq(colors[Vector2i(1, 1)], Minimap.OWN_COLOR)
	assert_eq(colors[Vector2i(2, 2)], Minimap.OTHER_COLOR)
	assert_eq(colors[Vector2i(3, 3)], Minimap.GAIA_COLOR)


func test_dead_entities_are_excluded_from_blips() -> void:
	map.update_entities({1: {"tile": Vector2i(0, 0), "owner_id": 1, "alive": false}}, 1)
	assert_true(map._blips.is_empty())


func test_two_taps_within_the_window_emit_double_tapped_not_tapped() -> void:
	var doubles: Array = []
	var singles: Array = []
	map.double_tapped.connect(func() -> void: doubles.append(true))
	map.tapped.connect(func(tile: Vector2i) -> void: singles.append(tile))

	map._gui_input(_touch(Vector2(10, 10), true))
	map._gui_input(_touch(Vector2(10, 10), false))
	map._gui_input(_touch(Vector2(10, 10), true))
	map._gui_input(_touch(Vector2(10, 10), false))

	assert_eq(doubles.size(), 1)
	assert_true(singles.is_empty(), "the completed double must not also queue a single move")


func test_a_lone_tap_resolves_to_nothing_without_a_tree_to_defer_on() -> void:
	# Same tree-guard reasoning as ControlGroupsHud: a widget outside a tree
	# cannot schedule the deferred single-tap timer, so nothing fires yet --
	# this asserts it does not crash or fire early, not that it later would.
	var singles: Array = []
	map.tapped.connect(func(tile: Vector2i) -> void: singles.append(tile))
	map._gui_input(_touch(Vector2(10, 10), true))
	map._gui_input(_touch(Vector2(10, 10), false))
	assert_true(singles.is_empty())


# ── the ornate frame, [P8] 2026-08-30 ───────────────────────────────────────


func test_the_map_diamond_fits_inside_the_frames_aperture() -> void:
	# THE BUG THIS PINS SHIPPED AND WAS FOUND BY EYE. `SIZE` was 150 against a 200 px
	# area, which put the map's diamond 18% wider than the hole in the frame it sits
	# in -- so the map covered the braided diamond bar completely and left two dragons
	# apparently floating in the corners. Nothing errored, nothing warned, and it
	# looked like a z-order problem rather than arithmetic.
	var half_diagonal := Minimap.SIZE / sqrt(2.0)
	var aperture := Minimap.AREA_SIZE * Minimap.APERTURE_RATIO
	assert_true(half_diagonal <= aperture + 0.5,
			"the map's diamond reaches %.1f px from centre and the frame's hole is %.1f"
			% [half_diagonal, aperture])


func test_the_map_actually_fills_that_aperture() -> void:
	# The other half, and it is why `SIZE` is derived rather than merely bounded: a map
	# comfortably INSIDE the hole is a map that gave away screen for nothing, and the
	# frame would draw a black ring around it.
	var half_diagonal := Minimap.SIZE / sqrt(2.0)
	var aperture := Minimap.AREA_SIZE * Minimap.APERTURE_RATIO
	assert_true(half_diagonal >= aperture - 0.5,
			"the map leaves %.1f px of black inside the frame" % [aperture - half_diagonal])