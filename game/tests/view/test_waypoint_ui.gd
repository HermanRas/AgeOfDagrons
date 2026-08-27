## The rally point's view half: the gesture that sets it, and the flag that shows it.
##
## The gesture is the risky part, because it REPURPOSES a tap that used to do something
## else — bare ground with a building selected used to clear the selection. So most of
## what is here is about what must NOT become a rally point: a tap with any unit in hand
## (that is a move order and always was), a multi-selection, somebody else's building, and
## bare ground with nothing selected at all.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	view.free()


func _building_facts(id: int, def_id: StringName, owner: int = 1,
		waypoint: Vector2i = SimBuilding.NO_WAYPOINT) -> Dictionary:
	return {
		"id": id, "owner_id": owner, "def_id": def_id, "is_unit": false,
		"phase": SimBuilding.Phase.COMPLETE, "alive": true, "tile": Vector2i(20, 20),
		"waypoint": waypoint, "garrison_count": 0, "garrison": [] as Array[StringName],
		"queue_len": 0, "queue_fraction": 0.0, "queue": [] as Array[StringName],
		"gate_locked": false, "facing": 0, "herded_by": 0, "remembered": false,
	}


func _unit_facts(id: int, owner: int = 1) -> Dictionary:
	return {
		"id": id, "owner_id": owner, "def_id": &"unit.villager", "is_unit": true,
		"phase": SimBuilding.Phase.COMPLETE, "alive": true, "tile": Vector2i(10, 10),
		"waypoint": SimBuilding.NO_WAYPOINT, "herded_by": 0, "remembered": false,
	}


func _put(facts: Dictionary) -> void:
	view._facts[int(facts["id"])] = facts


## BUILT ELEMENT BY ELEMENT, not `ids as Array[int]`. That cast works on a LITERAL
## (`[picked] as Array[int]`, which is what `GameScene` does) and silently fails on an
## untyped `Array` parameter -- `select()` then rejects it at runtime with "the array of
## argument 1 does not have the same element type". Same conversion every
## `Command.from_dict` does, for the same reason.
func _select(ids: Array) -> void:
	var typed: Array[int] = []
	for id in ids:
		typed.append(int(id))
	view.select(typed)


# ── the gesture ─────────────────────────────────────────────────────────────

func test_ground_tapped_with_one_of_your_buildings_selected_sets_a_rally_point() -> void:
	_put(_building_facts(10, &"building.barracks"))
	_select([10])
	assert_eq(view.tap_action(0, 1, false), GameView.TapAction.WAYPOINT)
	assert_eq(view.waypoint_target(1), 10)


func test_a_unit_in_hand_still_means_MOVE() -> void:
	# The ordering that makes the whole gesture safe: with anything movable selected a
	# ground tap is a move order and must stay one, so no mixed selection can ever
	# reach the rally-point branch.
	_put(_building_facts(10, &"building.barracks"))
	_put(_unit_facts(11))
	_select([10, 11])
	assert_eq(view.tap_action(0, 1, true), GameView.TapAction.MOVE)


func test_nothing_selected_still_clears() -> void:
	assert_eq(view.tap_action(0, 1, false), GameView.TapAction.NONE)


func test_two_buildings_selected_sets_nothing() -> void:
	# A player who box-selected their base and tapped the ground would otherwise flag
	# every building they own at once, and a rally point belongs to one building.
	_put(_building_facts(10, &"building.barracks"))
	_put(_building_facts(11, &"building.house"))
	_select([10, 11])
	assert_eq(view.waypoint_target(1), 0)
	assert_eq(view.tap_action(0, 1, false), GameView.TapAction.NONE)


func test_somebody_elses_building_sets_nothing() -> void:
	_put(_building_facts(10, &"building.barracks", 2))
	_select([10])
	assert_eq(view.waypoint_target(1), 0)
	assert_eq(view.tap_action(0, 1, false), GameView.TapAction.NONE)


func test_a_selected_unit_is_not_a_rally_point_target() -> void:
	_put(_unit_facts(11))
	_select([11])
	assert_eq(view.waypoint_target(1), 0)


func test_rubble_is_not_a_rally_point_target() -> void:
	var facts := _building_facts(10, &"building.barracks")
	facts["alive"] = false
	_put(facts)
	_select([10])
	assert_eq(view.waypoint_target(1), 0)


func test_a_resource_node_is_not_a_rally_point_target() -> void:
	# Gaia owns it, so the owner test already excludes it — this pins that a tree can
	# never answer `waypoint_target` even if that test were ever relaxed.
	var facts := _building_facts(10, &"res.tree", 0)
	_put(facts)
	_select([10])
	assert_eq(view.waypoint_target(0), 0)


func test_a_foundation_can_still_be_given_one() -> void:
	# `SetWaypointCommand` accepts a foundation so it is ready the moment it finishes,
	# and the tap has to agree or the command is unreachable.
	var facts := _building_facts(10, &"building.barracks")
	facts["phase"] = SimBuilding.Phase.FOUNDATION
	_put(facts)
	_select([10])
	assert_eq(view.waypoint_target(1), 10)


func test_tapping_the_building_itself_still_reselects_it() -> void:
	# The rally point is BARE GROUND only, so the building's own panel stays reachable.
	_put(_building_facts(10, &"building.barracks"))
	_select([10])
	assert_eq(view.tap_action(10, 1, false), GameView.TapAction.SELECT)


# ── the flag ────────────────────────────────────────────────────────────────

func test_the_flag_stands_on_the_tile_it_is_given() -> void:
	var flag := WaypointFlag.new()
	flag.show_on(Vector2i(7, 9), Color.RED)
	assert_true(flag.visible)
	assert_eq(flag.position, Iso.tile_centre_to_world(Vector2i(7, 9)))
	assert_eq(flag.current_colour(), Color.RED)
	flag.free()


func test_the_flag_carries_the_players_colour_rather_than_a_fixed_one() -> void:
	# Colour is the only thing that distinguishes players in v1, and a marker is one of
	# the few things that CAN be tinted — the pixels of baked art cannot.
	var flag := WaypointFlag.new()
	var before := flag.current_colour()
	flag.set_colour(Color.BLUE)
	assert_ne(flag.current_colour(), before)
	assert_eq(flag.current_colour(), Color.BLUE)
	flag.free()


func test_a_flag_outside_the_tree_still_takes_its_visible_state() -> void:
	# Same convention ActionFlash and NoticeToast follow, so a headless test can assert
	# the marker without building a scene.
	var flag := WaypointFlag.new()
	assert_false(flag.is_inside_tree())
	flag.show_on(Vector2i(1, 1), Color.WHITE)
	assert_true(flag.visible)
	flag.free()


func test_the_pole_is_measured_in_metres_and_not_pixels() -> void:
	# So it is foreshortened by the camera elevation exactly as a sprite's height is,
	# and stays right if that elevation ever changes.
	assert_true(WaypointFlag.POLE_METRES > 2.178,
			"taller than the villager, who measures 2.178 m")
	assert_true(WaypointFlag.POLE_METRES < Iso.METRES_PER_TILE * 3.0,
			"and not so tall it reads as a building")
