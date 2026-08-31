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


func test_an_ally_is_sky_blue_and_only_an_enemy_is_red() -> void:
	# Until 2026-08-31 this map drew green for your own and red for everything else, so
	# in a 2v2 your partner's army crossing the board read as an incoming attack. The
	# owner's fix, and their word for the colour.
	var facts := {
		1: {"tile": Vector2i(1, 1), "owner_id": 1, "alive": true},
		2: {"tile": Vector2i(2, 2), "owner_id": 2, "alive": true},
		3: {"tile": Vector2i(3, 3), "owner_id": 3, "alive": true},
		4: {"tile": Vector2i(4, 4), "owner_id": 0, "alive": true},
	}
	map.update_entities(facts, 1, {}, {1: 1, 2: 1, 3: 2})
	var colors := {}
	for b in map._blips:
		colors[b["tile"]] = b["color"]
	assert_eq(colors[Vector2i(1, 1)], Minimap.OWN_COLOR, "your own stay green")
	assert_eq(colors[Vector2i(2, 2)], Minimap.ALLY_COLOR, "your partner is not a threat")
	assert_eq(colors[Vector2i(3, 3)], Minimap.OTHER_COLOR, "and the other side still is")
	assert_eq(colors[Vector2i(4, 4)], Minimap.GAIA_COLOR,
			"gaia never reaches the ally test -- it has no team and is not on yours")


func test_a_free_for_all_draws_exactly_what_it_always_did() -> void:
	# The whole back catalogue: no teams, so nobody is anybody's ally and the map is the
	# two colours it has always been. A default `teams` of `{}` has to mean this.
	map.update_entities({
		1: {"tile": Vector2i(1, 1), "owner_id": 1, "alive": true},
		2: {"tile": Vector2i(2, 2), "owner_id": 2, "alive": true},
	}, 1)
	var colors := {}
	for b in map._blips:
		colors[b["tile"]] = b["color"]
	assert_eq(colors[Vector2i(2, 2)], Minimap.OTHER_COLOR)


func test_the_ally_blip_is_far_enough_from_the_water_to_be_seen_on_it() -> void:
	# ⚠️ THE OWNER ASKED EXACTLY THIS -- *"sky blue if its not to close to the water
	# colour"* -- and it is a measurement, not a taste. Sky blue and shallow water are
	# SIX DEGREES APART IN HUE, so hue cannot be what separates them; lightness is, and
	# the pairing that has to work is a SHIP, since an ally standing in water is a boat
	# and the archipelago is the map built around a fleet.
	#
	# Asserted as an ORDERING with a floor rather than as three figures, the rule the
	# galleon's volley is pinned by: the numbers are inputs and "you can see it on the
	# water" is the requirement.
	var shallow := Color(GameDataRegistry.placeholder_for(&"terrain.water_shallow").color)
	var deep := Color(GameDataRegistry.placeholder_for(&"terrain.water_deep").color)
	var ally := _lightness(Minimap.ALLY_COLOR)
	assert_true(ally - _lightness(shallow) > 20.0,
			"ally L* %.0f against shallow water %.0f" % [ally, _lightness(shallow)])
	assert_true(ally - _lightness(deep) > 20.0,
			"ally L* %.0f against deep water %.0f" % [ally, _lightness(deep)])
	# AND NOT SO PALE IT EATS THE DAMAGE FLASH, which is the bound in the other
	# direction and the reason it was not simply made lighter until the first test passed
	# comfortably. See `DAMAGE_FLASH_COLOR`.
	assert_true(_lightness(Minimap.DAMAGE_FLASH_COLOR) - ally > 15.0,
			"ally L* %.0f against the white flash's 100" % ally)


## CIE L*, from a colour's relative luminance. The one measure the eight-player palette
## was chosen on (`web/player-colour-ladder.html`), where neighbours sit about nine
## apart -- which is what makes the thresholds above readable as "three steps".
func _lightness(c: Color) -> float:
	var y := 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)
	return (116.0 * pow(y, 1.0 / 3.0) - 16.0) if y > 0.008856 else (903.3 * y)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 \
			else pow((channel + 0.055) / 1.055, 2.4)


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


# ── the damage flash (project owner, 2026-08-30) ────────────────────────────

func test_a_flashing_entity_is_drawn_white_or_in_its_own_colour_and_nothing_else() -> void:
	# The half of the under-attack alert that says WHERE. `DamageAlert` decides who is
	# flashing and on which phase; this asserts the minimap honours it and never
	# invents a third colour -- which is the failure that would actually ship, since a
	# blip is two pixels and a wrong one reads as an enemy.
	var facts := {
		1: {"id": 1, "tile": Vector2i(2, 2), "owner_id": 1, "alive": true},
		2: {"id": 2, "tile": Vector2i(4, 4), "owner_id": 1, "alive": true},
	}
	map.update_entities(facts, 1, {1: true})
	for b in map._blips:
		var c: Color = b["color"]
		assert_true(c == Minimap.OWN_COLOR or c == Minimap.DAMAGE_FLASH_COLOR,
				"a blip is its owner colour or the flash, never anything else -- got %s"
				% [c])


func test_nothing_flashing_means_nothing_white() -> void:
	# The phase is a function of the wall clock, so the WHITE case cannot be asserted
	# directly without injecting one. This is the direction that can be: an empty
	# flashing set must leave every blip alone whatever the clock says.
	var facts := {1: {"id": 1, "tile": Vector2i(2, 2), "owner_id": 1, "alive": true}}
	map.update_entities(facts, 1, {})
	assert_eq(map._blips.size(), 1)
	assert_eq(map._blips[0]["color"], Minimap.OWN_COLOR)


func test_an_entity_nobody_reported_is_never_flashed() -> void:
	# `DamageAlert` only ever records the local player's own entities, so an enemy blip
	# cannot light up -- but the minimap should not depend on that being true upstream.
	var facts := {
		1: {"id": 1, "tile": Vector2i(2, 2), "owner_id": 2, "alive": true},
		2: {"id": 2, "tile": Vector2i(3, 3), "owner_id": 1, "alive": true},
	}
	map.update_entities(facts, 1, {2: true})
	for b in map._blips:
		if b["tile"] == Vector2i(2, 2):
			assert_eq(b["color"], Minimap.OTHER_COLOR, "the enemy stays red")