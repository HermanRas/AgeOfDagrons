## Phase 4.3: tap-select. The selection set, and picking an entity out of the
## world by the tile under the finger.
extends TestCase

var view: GameView


func before_each() -> void:
	view = GameView.new()


func after_each() -> void:
	# Each of GameView's three layers is a separate orphan in a headless test, since
	# _ready() never runs to parent them -- see test_game_view.after_each.
	view.pool.free()
	view.terrain.free()
	view.fog.free()
	view.free()


## `tile` is the ORIGIN for a building and the tile itself for anything else.
##
## THE FOOTPRINT IS NO LONGER A PARAMETER. 12.1f took it off the wire -- it is static
## content the client derives from `def_id` -- so a fixture that declared its own would be
## describing a building that does not exist. **These tests were doing exactly that:** they
## called `building.town_center` 8x8, with a comment saying so, and the real def is 10x10.
## Nothing caught it because the fixture and the assertions agreed with each other; the
## view was the only thing that disagreed, and it was being handed the fiction.
##
## `pos` is a `Vector2i` here for the same reason it is one on the wire now.
func _entity(id: int, def_id: String, tile: Vector2i, owner := 1,
		alive := true) -> Dictionary:
	var building := GameDataRegistry.building(StringName(def_id))
	var centre := tile * SimWorld.SUBTILE + Vector2i(SimWorld.SUBTILE / 2, SimWorld.SUBTILE / 2)
	if building != null:
		centre = SimBuilding.centre_of(tile, building.footprint)
	var d := {"id": id, "def_id": def_id, "owner_id": owner, "hp": 30, "max_hp": 30,
			"alive": alive, "pos": centre}
	if building != null:
		d["phase"] = SimBuilding.Phase.COMPLETE
	return d


func _populate(entries: Array) -> void:
	view.apply_snapshot({"tick": 1, "updated": entries, "removed": []})


# ── the selection set ──────────────────────────────────────────────────────

func test_selecting_replaces_rather_than_accumulates() -> void:
	var s := Selection.new()
	s.set_selection([1, 2] as Array[int])
	s.set_selection([3] as Array[int])
	assert_eq(s.current(), [3] as Array[int])


func test_the_same_id_is_not_selected_twice() -> void:
	var s := Selection.new()
	s.add([1, 1, 2] as Array[int])
	assert_eq(s.size(), 2)


func test_the_returned_list_cannot_be_used_to_mutate_the_selection() -> void:
	# A caller builds a MoveCommand from this; if it were the live array, the
	# command and the selection would alias and drift apart in confusing ways.
	var s := Selection.new()
	s.set_selection([1, 2] as Array[int])
	var taken := s.current()
	taken.append(99)
	assert_eq(s.size(), 2)


func test_selection_is_capped() -> void:
	var many: Array[int] = []
	for i in range(Selection.MAX_SELECTED + 25):
		many.append(i + 1)
	var s := Selection.new()
	s.set_selection(many)
	assert_eq(s.size(), Selection.MAX_SELECTED, "refused rather than truncated silently")


func test_a_dead_entity_drops_out_of_the_selection() -> void:
	# Otherwise an order names an entity the sim rejects and nothing happens,
	# which reads to the player as the game ignoring them.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])
	view.select([1, 2] as Array[int])

	# 1 is resent, 2 is despawned. An empty `updated` would now drop BOTH -- since 2.5
	# a snapshot that stops mentioning an entity means the player cannot see it any
	# more -- and this test is about the one that died, not the one that survived.
	view.apply_snapshot({"tick": 2,
			"updated": [_entity(1, "unit.villager", Vector2i(5, 5))], "removed": [2]})
	assert_eq(view.selection.current(), [1] as Array[int])


# ── losing sight of things (PLAN.md 2.5) ───────────────────────────────────

func test_an_entity_the_snapshot_stops_mentioning_is_forgotten() -> void:
	# The client half of fog of war. The server stops sending an enemy unit the moment
	# it walks back into the dark, and ABSENCE is the signal -- so the view has to let
	# go of it rather than leaving it frozen where it was last seen.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(20, 20), 2)])
	assert_not_null(view.pool.get_view(2), "in plain sight")

	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	assert_null(view.pool.get_view(2), "and gone when we lose sight of it")


func test_a_forgotten_entity_stops_answering_questions_about_itself() -> void:
	# DROPPING THE FACTS IS THE HALF THAT MATTERS. A stale entry would still answer
	# pick() and still draw a minimap blip, which would make the fog a purely cosmetic
	# overlay with the position leaking out the side.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(20, 20), 2)])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(20, 20)), 0), 2)

	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(20, 20)), 0), 0, "nothing there now")
	assert_true(view.facts_for(2).is_empty())
	assert_false(view.all_facts().has(2), "and no blip for the minimap either")


func test_losing_sight_of_a_selected_unit_drops_it_from_the_selection() -> void:
	# Otherwise an order would name an entity the player can no longer see, which the
	# sim would accept for their own unit and refuse for anybody else's -- either way
	# the selection has to follow what is actually on screen.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])
	view.select([1, 2] as Array[int])

	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.selection.current(), [1] as Array[int])


func test_a_remembered_building_is_marked_as_such_in_the_facts() -> void:
	# What SnapshotSystem._remembered sends: a static in explored territory, stripped
	# of everything live. hp arrives as 0/0, which SelectionPanel already reads as "no
	# health bar" without having to know why.
	var remembered := _entity(3, "building.house", Vector2i(20, 20), 2)
	remembered.erase("hp")
	remembered.erase("max_hp")
	remembered["remembered"] = true
	_populate([remembered])

	var facts := view.facts_for(3)
	assert_true(bool(facts["remembered"]))
	assert_eq(int(facts["max_hp"]), 0, "no health bar for a memory")


func test_an_entity_in_plain_sight_is_not_marked_remembered() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	assert_false(bool(view.facts_for(1)["remembered"]))


## A corpse/rubble (4.7, 5.5) is `alive == false` but stays in the snapshot for a
## while -- the "still here, just dead" case `removed[]` alone cannot cover.
func test_a_corpse_drops_out_of_the_selection_the_tick_it_dies() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])
	view.select([1, 2] as Array[int])

	view.apply_snapshot({"tick": 2, "updated": [
			_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5), 1, false)], "removed": []})
	assert_eq(view.selection.current(), [1] as Array[int])
	assert_false(view.pool.get_view(2).selected, "no ring on a corpse")


# ── picking (4.3) ──────────────────────────────────────────────────────────

func test_tapping_a_units_own_tile_selects_it() -> void:
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5))), 7)


func test_tapping_anywhere_inside_a_tile_selects_what_is_on_it() -> void:
	# The regression that `Iso.tile_at()` exists for: `world_to_tile()` ROUNDS, so
	# using it here sent the near half of every tile to its neighbour and the tap
	# missed whatever the player was aiming at.
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	var centre := Iso.tile_centre_to_world(Vector2i(5, 5))
	for nudge in [Vector2(0, -12), Vector2(0, 12), Vector2(-24, 0), Vector2(24, 0)]:
		assert_eq(view.pick(centre + nudge), 7, "nudged by %s" % nudge)


func test_tapping_empty_ground_selects_nothing() -> void:
	_populate([_entity(7, "unit.villager", Vector2i(5, 5))])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(20, 20))), 0)


func test_a_building_can_be_tapped_anywhere_on_its_footprint() -> void:
	# A town centre is 10x10 -- read off its def now rather than asserted at 8x8 here,
	# which is what this comment used to claim. Only tapping its centre tile would make
	# most of it untappable.
	_populate([_entity(3, "building.town_center", Vector2i(10, 10))])
	for tile in [Vector2i(10, 10), Vector2i(13, 14), Vector2i(17, 17)]:
		assert_eq(view.pick(Iso.tile_centre_to_world(tile)), 3, "tapped %s" % tile)
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(9, 9))), 0, "and not just outside it")


func test_a_unit_standing_on_a_building_wins_the_tap() -> void:
	# The villager is the thing worth tapping; the town centre is not going
	# anywhere and is far easier to hit elsewhere.
	_populate([
		_entity(3, "building.town_center", Vector2i(10, 10)),
		_entity(9, "unit.villager", Vector2i(12, 12)),
	])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(12, 12))), 9)


func test_picking_can_be_limited_to_one_players_things() -> void:
	_populate([_entity(4, "unit.villager", Vector2i(5, 5), 2)])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5)), 1), 0, "not mine")
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5)), 2), 4, "theirs")


func test_a_corpse_cannot_be_picked() -> void:
	_populate([_entity(7, "unit.villager", Vector2i(5, 5), 1, false)])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(5, 5))), 0)


func test_rubble_cannot_be_picked() -> void:
	_populate([_entity(3, "building.town_center", Vector2i(10, 10), 1, false)])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(10, 10))), 0)


# ── what can be given a move order (3.6) ───────────────────────────────────

func test_only_units_can_be_ordered_to_move() -> void:
	# MoveCommand.validate() rejects the WHOLE command if any id is not a unit, so
	# selecting the town centre alongside villagers would silently cancel the move
	# for the villagers too.
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5)),
		_entity(3, "building.town_center", Vector2i(10, 10)),
	])
	view.select([1, 3] as Array[int])
	assert_eq(view.movable_selection(), [1] as Array[int])


func test_a_resource_node_is_not_mistaken_for_a_unit() -> void:
	# Resource nodes are 1x1 and carry no `phase`, so anything inferring unit-ness
	# from the snapshot's shape would call a tree a unit and send move orders
	# naming it. The registry is asked instead.
	_populate([_entity(4, "res.tree", Vector2i(7, 7), 0)])
	assert_false(bool(view.facts_for(4)["is_unit"]), "a tree is not a unit")
	view.select([4] as Array[int])
	assert_true(view.movable_selection().is_empty())


func test_a_unit_beats_a_resource_node_on_the_same_tile_when_picking() -> void:
	_populate([
		_entity(4, "res.tree", Vector2i(7, 7), 0),
		_entity(5, "unit.villager", Vector2i(7, 7)),
	])
	assert_eq(view.pick(Iso.tile_centre_to_world(Vector2i(7, 7))), 5)


# ── two-finger box select (8.3) ────────────────────────────────────────────

## A box in local space covering the given tiles, grown so the tile centres are
## comfortably inside rather than exactly on the boundary.
func _box_over(a: Vector2i, b: Vector2i) -> Rect2:
	var pa := Iso.tile_centre_to_world(a)
	var pb := Iso.tile_centre_to_world(b)
	return Rect2(Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y)), (pb - pa).abs()).grow(8.0)


func test_a_box_selects_every_unit_inside_it() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5)),
		_entity(2, "unit.villager", Vector2i(6, 6)),
		_entity(3, "unit.villager", Vector2i(30, 30)),
	])
	var picked := view.units_in_box(_box_over(Vector2i(4, 4), Vector2i(7, 7)), 1)
	assert_eq(picked, [1, 2] as Array[int], "the far one is left out")


func test_a_box_ignores_buildings_and_resources() -> void:
	# Dragging a box across your settlement and catching the town centre, four
	# trees and a deer is not what anyone means by a box select.
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5)),
		_entity(2, "building.town_center", Vector2i(5, 6)),
		_entity(3, "res.tree", Vector2i(6, 5), 0),
	])
	assert_eq(view.units_in_box(_box_over(Vector2i(3, 3), Vector2i(9, 9)), 1),
			[1] as Array[int])


func test_a_box_ignores_other_players_units() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5), 1),
		_entity(2, "unit.villager", Vector2i(6, 6), 2),
	])
	assert_eq(view.units_in_box(_box_over(Vector2i(4, 4), Vector2i(7, 7)), 1),
			[1] as Array[int])


func test_a_box_over_empty_ground_selects_nothing() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	assert_true(view.units_in_box(_box_over(Vector2i(40, 40), Vector2i(44, 44)), 1).is_empty())


func test_a_box_ignores_a_corpse() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5), 1, false),
			_entity(2, "unit.villager", Vector2i(6, 6))])
	assert_eq(view.units_in_box(_box_over(Vector2i(4, 4), Vector2i(7, 7)), 1),
			[2] as Array[int])


func test_a_box_result_is_ordered_so_it_is_the_same_on_every_machine() -> void:
	# A box catching more than MAX_SELECTED has to keep the SAME units everywhere,
	# not whichever the Dictionary happened to yield first -- the selection becomes
	# a command, and two clients disagreeing about its contents is a desync.
	var entries: Array = []
	for i in range(12):
		entries.append(_entity(20 - i, "unit.villager", Vector2i(5 + i, 5)))
	_populate(entries)
	var picked := view.units_in_box(_box_over(Vector2i(4, 4), Vector2i(18, 6)), 1)
	var sorted := picked.duplicate()
	sorted.sort()
	assert_eq(picked, sorted, "returned in id order")


func test_a_box_selection_draws_rings_on_all_of_them() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5)),
		_entity(2, "unit.villager", Vector2i(6, 6)),
	])
	view.select(view.units_in_box(_box_over(Vector2i(4, 4), Vector2i(7, 7)), 1))
	assert_true(view.pool.get_view(1).selected)
	assert_true(view.pool.get_view(2).selected)
	assert_eq(view.selection.size(), 2)


# ── the ring ───────────────────────────────────────────────────────────────

## ── control groups (PLAN.md 10.1/10.4/10.5) ─────────────────────────────────

func test_control_group_alive_members_drops_the_dead_and_the_unseen() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5), 1, false)])
	assert_eq(view.control_group_alive_members([1, 2, 999]), [1] as Array[int])


func test_control_group_summary_picks_the_most_represented_alive_def() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5)),
		_entity(2, "unit.villager", Vector2i(6, 5)),
		_entity(3, "building.town_center", Vector2i(10, 10)),
	])
	var summary := view.control_group_summary([1, 2, 3])
	assert_eq(summary["icon"], &"unit.villager")
	assert_eq(summary["count"], 3)


func test_control_group_summary_ignores_dead_members_for_both_icon_and_count() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(5, 5), 1, false),
		_entity(2, "building.town_center", Vector2i(10, 10)),
	])
	var summary := view.control_group_summary([1, 2])
	assert_eq(summary["icon"], &"building.town_center")
	assert_eq(summary["count"], 1)


func test_control_group_summary_is_empty_once_every_member_is_dead() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5), 1, false)])
	var summary := view.control_group_summary([1])
	assert_eq(summary["icon"], &"")
	assert_eq(summary["count"], 0)


func test_control_group_centre_averages_alive_members_positions() -> void:
	_populate([
		_entity(1, "unit.villager", Vector2i(4, 4)),
		_entity(2, "unit.villager", Vector2i(6, 4)),
	])
	var centre = view.control_group_centre([1, 2])
	var expected := (Iso.tile_centre_to_world(Vector2i(4, 4)) + Iso.tile_centre_to_world(Vector2i(6, 4))) * 0.5
	assert_almost_eq(centre.x, expected.x, 0.01)
	assert_almost_eq(centre.y, expected.y, 0.01)


func test_control_group_centre_is_null_with_nothing_alive() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5), 1, false)])
	assert_null(view.control_group_centre([1]))


## ── minimap support (PLAN.md 3.4, 8.2a) ─────────────────────────────────────

func test_all_facts_returns_every_entity_keyed_by_id() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 6), 2)])
	var facts := view.all_facts()
	assert_eq(facts.keys().size(), 2)
	assert_eq(facts[1]["tile"], Vector2i(5, 5))


func test_all_facts_is_a_copy() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	var facts := view.all_facts()
	facts.clear()
	assert_eq(view.all_facts().keys().size(), 1, "mutating the copy must not touch the view")


func test_owned_entity_position_finds_the_players_town_centre() -> void:
	_populate([_entity(3, "building.town_center", Vector2i(10, 10))])
	var pos = view.owned_entity_position(1, &"building.town_center")
	assert_eq(pos, Iso.tile_centre_to_world(view.facts_for(3)["tile"]))


func test_owned_entity_position_is_null_with_none_matching() -> void:
	_populate([_entity(3, "building.town_center", Vector2i(10, 10), 2)])
	assert_null(view.owned_entity_position(1, &"building.town_center"))


func test_owned_entity_position_ignores_a_dead_match() -> void:
	_populate([_entity(3, "building.town_center", Vector2i(10, 10), 1, false)])
	assert_null(view.owned_entity_position(1, &"building.town_center"))


func test_selecting_marks_the_view_and_deselecting_clears_it() -> void:
	_populate([_entity(1, "unit.villager", Vector2i(5, 5)),
			_entity(2, "unit.villager", Vector2i(6, 5))])

	view.select([1] as Array[int])
	assert_true(view.pool.get_view(1).selected)
	assert_false(view.pool.get_view(2).selected)

	view.select([2] as Array[int])
	assert_false(view.pool.get_view(1).selected, "the old ring is taken away")
	assert_true(view.pool.get_view(2).selected)


func test_a_selection_survives_the_next_snapshot() -> void:
	# Views are pooled and re-pointed every snapshot; a ring that vanished on the
	# next tick would make selection look broken while the state was fine.
	_populate([_entity(1, "unit.villager", Vector2i(5, 5))])
	view.select([1] as Array[int])
	_populate([_entity(1, "unit.villager", Vector2i(6, 5))])
	assert_true(view.pool.get_view(1).selected)
