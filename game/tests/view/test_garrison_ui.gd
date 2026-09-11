## Phase 4.8's view half: the tap that issues a garrison order, and the building
## panel's Garrison action with its roster. **And 4.8c's view half in the last
## section** -- which units may go inside at all, and the tap that must therefore
## reselect rather than order.
##
## `SelectionActions` is pure and static, so all of this is assertable without a
## panel -- the same division that file's header draws. The one case worth naming as
## load-bearing is the ACTION CAP: a castle already emitted 7 of `MAX_ACTIONS`' 8
## before this feature, so the Garrison button lands on exactly the last slot and one
## more verb after it would silently drop Destroy off the end.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	view.free()


## Facts as `GameView.apply_snapshot` would have built them for a building. Only the
## keys the code under test reads; `facts_for()`'s real dictionaries carry ~20 more.
func _building_facts(def_id: StringName, owner: int = 1, inside: Array = [],
		phase: int = SimBuilding.Phase.COMPLETE) -> Dictionary:
	var names: Array[StringName] = []
	for n in inside:
		names.append(StringName(n))
	return {
		"id": 10, "owner_id": owner, "def_id": def_id, "is_unit": false,
		"phase": phase, "alive": true, "tile": Vector2i(20, 20),
		"garrison_count": names.size(), "garrison": names,
		"queue_len": 0, "queue_fraction": 0.0, "queue": [] as Array[StringName],
		"gate_locked": false, "facing": 0, "herded_by": 0, "remembered": false,
	}


func _ids(actions: Array[HudAction]) -> Array[String]:
	var out: Array[String] = []
	for a in actions:
		out.append(String(a.id))
	return out


func _find(actions: Array[HudAction], id: StringName) -> HudAction:
	for a in actions:
		if a.id == id:
			return a
	return null


# ── the action button ───────────────────────────────────────────────────────

func test_a_tower_offers_a_garrison_action_and_a_house_does_not() -> void:
	var tower := SelectionActions.for_selection(
			_building_facts(&"building.watch_tower"), 1, true, [], 4)
	assert_true(_ids(tower).has("garrison"))

	var house := SelectionActions.for_selection(
			_building_facts(&"building.house"), 1, true, [], 4)
	assert_false(_ids(house).has("garrison"),
			"28 of the 31 buildings hold nobody, and one `garrison_cap > 0` test covers "
			+ "all of them without naming any")


func test_the_badge_says_how_full_it_is() -> void:
	# The only place in the HUD that reports a tower's occupancy.
	var facts := _building_facts(&"building.guard_tower", 1, ["unit.archer", "unit.archer"])
	var g := _find(SelectionActions.for_selection(facts, 1, true, [], 4), &"garrison")
	assert_not_null(g)
	assert_eq(g.badge, "2/5")


func test_an_empty_tower_shows_the_slot_disabled_rather_than_hiding_it() -> void:
	# So the slot does not move under the player's thumb as archers walk in and out.
	var empty := _find(SelectionActions.for_selection(
			_building_facts(&"building.watch_tower"), 1, true, [], 4), &"garrison")
	assert_not_null(empty)
	assert_false(empty.enabled)
	assert_eq(empty.badge, "0/5")

	var occupied := _find(SelectionActions.for_selection(
			_building_facts(&"building.watch_tower", 1, ["unit.archer"]), 1, true, [], 4),
			&"garrison")
	assert_true(occupied.enabled)


func test_a_tower_foundation_offers_nothing_to_garrison() -> void:
	var facts := _building_facts(&"building.watch_tower", 1, [],
			SimBuilding.Phase.FOUNDATION)
	assert_false(_ids(SelectionActions.for_selection(facts, 1, true, [], 4)).has("garrison"))


## ⚠️ **THIS WAS `== MAX_ACTIONS` AND IS NOW ONE UNDER IT, because the castle stopped training
## the dragon** (2026-09-04, PLAN.md 13.2 — a dragon is claimed at a nest, never trained).
##
## 3 trains + garrison + upgrade + destroy + repair = 7. It was 8 exactly, which is why the
## comment here used to read *"a ninth verb would drop Destroy silently"*.
##
## **Asserted as `<=` rather than as an exact number.** An equality here is a tripwire that
## fires on any roster edit and says nothing about whether the row is CORRECT — it broke on
## this one, and the number it was guarding was never the point. What must stay true is that
## the row fits and that nothing real fell off the end.
func test_the_castles_action_row_still_fits_in_its_eight_slots() -> void:
	var facts := _building_facts(&"building.castle", 1, ["unit.archer"])
	var actions := SelectionActions.for_selection(facts, 1, true, [], 4)
	assert_true(actions.size() <= SelectionActions.MAX_ACTIONS,
			"the row must fit: %d of %d" % [actions.size(), SelectionActions.MAX_ACTIONS])
	var ids := _ids(actions)
	assert_true(ids.has("garrison"))
	assert_true(ids.has("destroy"), "and nothing fell off the end")
	assert_true(ids.has("repair"), "which at 7 now includes the placeholder")


# ── the roster in the detail grid ───────────────────────────────────────────

func test_the_roster_lists_an_empty_slot_and_then_the_occupants() -> void:
	var facts := _building_facts(&"building.guard_tower", 1,
			["unit.archer", "unit.swordsman"])
	var details := SelectionActions.details_for(&"garrison", facts)
	assert_eq(_ids(details), ["ungarrison:all", "ungarrison:0", "ungarrison:1"])
	assert_eq(details[1].payload, &"unit.archer",
			"the def id, so ActionSlot crops that unit's own portrait")
	assert_eq(details[2].payload, &"unit.swordsman")


func test_an_empty_tower_has_no_roster_and_no_empty_button() -> void:
	assert_true(SelectionActions.details_for(&"garrison",
			_building_facts(&"building.watch_tower")).is_empty())


func test_a_full_castles_roster_is_paged_rather_than_capped() -> void:
	# 15 occupants plus the Empty slot is 16 against MAX_DETAILS' 12. Capped, the last
	# four archers would be silently un-ejectable -- the failure `_buildable_details`
	# records having had with the town centre falling off the build list.
	var inside: Array = []
	for _i in range(15):
		inside.append("unit.archer")
	var details := SelectionActions.details_for(&"garrison",
			_building_facts(&"building.castle", 1, inside))

	assert_eq(details.size(), 16, "returned whole")
	assert_true(SelectionActions.page_count(details.size()) > 1)
	# Every occupant is reachable across the pages, arrows included.
	var seen: Array[String] = []
	for page in range(SelectionActions.page_count(details.size())):
		for a in SelectionActions.page_of(details, page):
			seen.append(String(a.id))
	for i in range(15):
		assert_true(seen.has("ungarrison:%d" % i), "slot %d is reachable" % i)


# ── the tap that issues the order ───────────────────────────────────────────

func _apply(facts: Dictionary) -> void:
	# One entity, straight into the view's fact table, which is what `tap_action`
	# reads. Going through a real snapshot would need a world and a pool.
	view._facts[int(facts["id"])] = facts


func test_tapping_your_own_tower_with_units_in_hand_garrisons_them() -> void:
	_apply(_building_facts(&"building.watch_tower"))
	assert_eq(view.tap_action(10, 1, true), GameView.TapAction.GARRISON)


func test_tapping_it_with_nothing_selected_still_just_selects() -> void:
	# So its panel, its health and its Ungarrison button stay reachable.
	_apply(_building_facts(&"building.watch_tower"))
	assert_eq(view.tap_action(10, 1, false), GameView.TapAction.SELECT)


func test_a_full_tower_reselects_instead_of_offering_an_order_the_sim_would_refuse() -> void:
	# Never offer an order the sim will refuse: a refused command is invisible, the
	# player taps and nothing happens and nothing says why. Reselecting is also how
	# they reach the Ungarrison button.
	_apply(_building_facts(&"building.watch_tower", 1,
			["unit.archer", "unit.archer", "unit.archer", "unit.archer", "unit.archer"]))
	assert_eq(view.tap_action(10, 1, true), GameView.TapAction.SELECT)


func test_tapping_a_house_or_a_town_centre_is_not_a_garrison() -> void:
	for def_id in [&"building.house", &"building.town_center", &"building.barracks"]:
		view._facts.clear()
		_apply(_building_facts(def_id))
		assert_eq(view.tap_action(10, 1, true), GameView.TapAction.SELECT, String(def_id))


func test_a_tower_foundation_is_a_build_assist_and_not_a_garrison() -> void:
	# The two flashes most likely to be confused, which is why GARRISON is violet and
	# not a shade of BUILD's blue: the same tap on the same tower means "help finish
	# it" while it is a foundation and "go inside" once it is not.
	_apply(_building_facts(&"building.watch_tower", 1, [], SimBuilding.Phase.FOUNDATION))
	assert_eq(view.tap_action(10, 1, true), GameView.TapAction.BUILD)


func test_somebody_elses_tower_is_a_thing_to_attack() -> void:
	_apply(_building_facts(&"building.watch_tower", 2))
	assert_eq(view.tap_action(10, 1, true), GameView.TapAction.ATTACK)


# ── 4.8c: the selection has to contain something that may go in ─────────────
#
# ⚠️ **NONE OF THIS WAS COVERED WHEN 4.8c SHIPPED.** The sim half is pinned six ways in
# `tests/sim/test_garrison.gd`, and the client half -- `garrisonable_selection()` and the
# fourth argument to `tap_action` -- had no test at all: every call site in the suite used
# the three-argument form, so the false branch this feature exists for was never taken.
# That is §6's *"a rule that can be left out is a rule that is off somewhere"* wearing a
# default value, and the default here is the pre-4.8c answer.

func _unit_facts(id: int, def_id: StringName, owner: int = 1,
		garrison_count: int = 0) -> Dictionary:
	return {
		"id": id, "owner_id": owner, "def_id": def_id, "is_unit": true,
		"phase": SimBuilding.Phase.COMPLETE, "alive": true, "tile": Vector2i(10, 10),
		"garrison_count": garrison_count, "garrison": [] as Array[StringName],
		"waypoint": SimBuilding.NO_WAYPOINT, "herded_by": 0, "remembered": false,
	}


## BUILT ELEMENT BY ELEMENT, not `ids as Array[int]` -- that cast works on a literal and
## silently produces an untyped array from a variable, which `select()` then rejects at
## runtime. Same conversion every `Command.from_dict` does.
func _select(ids: Array) -> void:
	var typed: Array[int] = []
	for id in ids:
		typed.append(int(id))
	view.select(typed)


func test_a_dragon_is_movable_and_is_not_garrisonable() -> void:
	# The one unit the two questions differ on, which is the whole reason
	# `garrisonable_selection()` is asked separately instead of folded into
	# `movable_selection()`.
	_apply(_unit_facts(1, &"unit.dragon"))
	_select([1])
	assert_eq(view.movable_selection(), [1] as Array[int], "a dragon is perfectly movable")
	assert_true(view.garrisonable_selection().is_empty(), "and may not go inside anything")


func test_every_def_the_roster_refuses_is_refused_on_the_client_too() -> void:
	# By NAME, the same way `test_garrison` pins the sim half: a def quietly losing
	# `can_garrison` fails with its own id rather than becoming garrisonable again in
	# the one place a player actually taps.
	for def_id in [&"unit.siege_ram", &"unit.ballista", &"unit.onager",
			&"unit.trebuchet", &"unit.dragon", &"unit.dragon_baby"]:
		view._facts.clear()
		_apply(_unit_facts(1, def_id))
		_select([1])
		assert_true(view.garrisonable_selection().is_empty(), String(def_id))


func test_an_ordinary_unit_is_still_garrisonable() -> void:
	# The inverse, and it is not redundant: a typo making the default false everywhere
	# would be a game in which nobody can garrison, and every test above would pass.
	_apply(_unit_facts(1, &"unit.swordsman"))
	_select([1])
	assert_eq(view.garrisonable_selection(), [1] as Array[int])


func test_a_mixed_selection_still_has_somebody_to_send() -> void:
	# This answers "is there anybody", not "who" -- `GarrisonCommand` drops the onager on
	# arrival. A blanket refusal here would cancel a garrison the player plainly meant
	# because one siege engine was caught in a box-select.
	_apply(_unit_facts(1, &"unit.swordsman"))
	_apply(_unit_facts(2, &"unit.onager"))
	_select([1, 2])
	assert_eq(view.garrisonable_selection(), [1] as Array[int])


func test_a_def_the_client_cannot_resolve_is_let_through() -> void:
	# Matches `UnitDef.can_garrison`'s default and `GarrisonCommand._may_garrison`: an
	# unresolvable id gets the pre-4.8c answer rather than a new refusal layered on top of
	# whatever is already wrong. The server is the trust boundary either way.
	_apply(_unit_facts(1, &"unit.no_such_thing"))
	_select([1])
	assert_eq(view.garrisonable_selection(), [1] as Array[int])


func test_a_lone_dragon_tapping_its_own_castle_reselects() -> void:
	# ⚠️ **THE FOURTH ARGUMENT'S FALSE BRANCH, and nothing exercised it until this test.**
	# Issuing the order instead would be the invisible refusal `tap_action`'s own comments
	# keep warning about, arriving through the rule added to stop it -- the player taps,
	# the server drops every id, and nothing says why. Reselecting is also how they reach
	# that castle's own panel.
	_apply(_building_facts(&"building.castle"))
	assert_eq(view.tap_action(10, 1, true, false), GameView.TapAction.SELECT)
	assert_eq(view.tap_action(10, 1, true, true), GameView.TapAction.GARRISON,
			"and the same tap with an infantryman in hand is still an order")


func test_a_dragon_tapping_your_own_transport_reselects_too() -> void:
	# THE SECOND FALSE BRANCH, twenty lines above the tower's in the same function and
	# easy to fix one of. A boat is boarded by the same gesture, so without it a dragon
	# tapping one issues a command `GarrisonCommand` refuses for a reason nobody can see.
	_apply(_unit_facts(10, &"unit.transport_ship"))
	assert_eq(view.tap_action(10, 1, true, false), GameView.TapAction.SELECT)
	assert_eq(view.tap_action(10, 1, true, true), GameView.TapAction.GARRISON)
