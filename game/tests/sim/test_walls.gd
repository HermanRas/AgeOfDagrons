## Building a wall and opening a gate (PLAN.md 5.8).
##
## `test_wall_plan` covers the segmentation arithmetic. What is asserted here is what
## happens to a WORLD: that a run pays for itself, that it is partial when it has to
## be, and that a gate actually moves the movement grid -- which is the one thing in
## the feature that changes a tile's passability mid-match, and therefore the one
## thing that could desync.
extends TestCase

const WOOD := &"building.wall_wood_short"
const WOOD_GATE := &"building.wall_wood_gate"

var world: SimWorld


func before_each() -> void:
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)
	# Age 2 and rich, so nothing here fails on a gate the player has not reached or
	# a wall they cannot afford -- both are tested deliberately, further down.
	var p := world.player_for(1)
	p.age = 2
	for kind in [&"wood", &"stone", &"food", &"gold"]:
		p.stock[kind] = 10_000


## Somewhere on the debug map with nothing standing on it. Good for a short run, and
## NOT good enough for a long one -- see `_clear_run`.
const CLEAR := Vector2i(4, 40)


## An origin with `tiles` x DEPTH of genuinely clear ground, east-west.
##
## FOUND RATHER THAN ASSUMED, because assuming cost two tests at once: `CLEAR` fits a
## twelve-tile run and not an eighteen-tile one, so a test that dragged eighteen tiles
## got one segment from the map rather than from the rule it was checking -- and
## `test_a_run_across_something_places_what_fits` was therefore passing whether its
## house blocked anything or not. Exactly the "beware fixtures that agree with the
## bug" trap AGENT_GAME_CODER.md 5 records, caught here by a different test failing.
func _clear_run(tiles: int) -> Vector2i:
	for y in range(2, world.map.size.y - WallPlan.DEPTH - 1):
		for x in range(2, world.map.size.x - tiles - 1):
			var origin := Vector2i(x, y)
			if world.map.can_place_building(
					SimMap.footprint_rect(origin, Vector2i(tiles, WallPlan.DEPTH))):
				return origin
	assert_true(false, "no clear %d-tile strip on the debug map" % tiles)
	return CLEAR


func _run(cmd: Command) -> bool:
	if not cmd.validate(world):
		return false
	world.queue_command(cmd)
	world.step()
	return true


func _walls() -> Array[SimBuilding]:
	var out: Array[SimBuilding] = []
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and String(e.def_id).begins_with("building.wall_"):
			out.append(e)
	return out


func _held(kind: StringName) -> int:
	return int(world.player_for(1).stock.get(kind, 0))


# ── placing a run ───────────────────────────────────────────────────────────

func test_a_drag_places_a_run_of_segments() -> void:
	assert_true(_run(PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR + Vector2i(11, 0))))
	var walls := _walls()
	assert_eq(walls.size(), 2, "12 tiles is a long and a short")
	for w in walls:
		assert_eq(w.owner_id, 1)
		assert_eq(w.phase, SimBuilding.Phase.FOUNDATION,
				"placed as foundations, like every other building")


func test_a_run_pays_for_every_segment_it_places() -> void:
	var before := _held(&"wood")
	assert_true(_run(PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR + Vector2i(11, 0))))
	var expected := 0
	for w in _walls():
		expected += int((GameDataRegistry.building(w.def_id) as BuildingDef).cost.get(&"wood", 0))
	assert_true(expected > 0, "a wall costs something")
	assert_eq(_held(&"wood"), before - expected)


func test_a_vertical_run_claims_a_transposed_footprint() -> void:
	# The bug this exists for: a def authored [9, 2] laid north-south must hold
	# [2, 9] of grid, or nine tiles of ground are claimed in the wrong direction and
	# the wall blocks a corridor it is not standing in.
	assert_true(_run(PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR + Vector2i(0, 8))))
	var walls := _walls()
	assert_eq(walls.size(), 1)
	assert_eq(walls[0].footprint, Vector2i(WallPlan.DEPTH, 9))
	# And the MAP agrees, which is what actually stops a unit.
	assert_false(world.map.is_passable(CLEAR + Vector2i(0, 8)),
			"the far end of the run is solid")


func test_a_run_across_something_places_what_fits() -> void:
	# 0 A.D. does the same. Refusing the whole drag because it clipped one tree is
	# the opposite of what dragging means.
	#
	# ON GROUND PROVEN CLEAR FIRST, and then proven to place BOTH segments there --
	# without that, a map feature in the way would make this pass with the house
	# doing nothing at all.
	var origin := _clear_run(18)
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(17, 0))))
	assert_eq(_walls().size(), 2, "18 clear tiles is two long segments")

	var second := _fresh()
	var blocker := second.spawn_building(&"building.house", 1, origin + Vector2i(10, 0),
			SimBuilding.Phase.COMPLETE, true)
	assert_not_null(blocker, "something is in the way")
	var cmd := PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(17, 0))
	assert_true(cmd.validate(second))
	second.queue_command(cmd)
	second.step()

	var walls := 0
	for e in second.entities.values():
		if e is SimBuilding and String(e.def_id).begins_with("building.wall_"):
			walls += 1
	assert_eq(walls, 1, "the second long runs into the house and is skipped")


func test_a_run_stops_when_the_money_does() -> void:
	# Placed from the anchor outwards and ENDED rather than skipped -- a wall with a
	# hole where the budget ran out reads as a bug, where one that simply stops reads
	# as a wall you could not finish.
	var short_cost := int((GameDataRegistry.building(WOOD) as BuildingDef).cost.get(&"wood", 0))
	world.player_for(1).stock[&"wood"] = short_cost * 3
	var origin := _clear_run(30)
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(29, 0))))
	assert_true(_walls().size() >= 1, "some wall went up")
	assert_true(_held(&"wood") < short_cost, "and the money is spent")
	# Contiguous from the anchor: no gap where a segment was skipped for cost.
	var expected := origin.x
	for w in _walls():
		assert_eq(w.origin_tile().x, expected, "laid end to end from the anchor")
		expected += w.footprint.x


func test_a_budget_short_of_the_first_long_piece_still_buys_a_short_one() -> void:
	# THE CASE THAT MADE THE DOWNGRADE NECESSARY. A thirty-tile drag plans a long
	# piece first; a player with two shorts' worth of wood cannot afford it, and
	# before the downgrade they got nothing at all -- with wall they could plainly
	# pay for on the table. "As much wall as you can afford" has to mean it.
	var short_cost := int((GameDataRegistry.building(WOOD) as BuildingDef).cost.get(&"wood", 0))
	var long_cost := int((GameDataRegistry.building(&"building.wall_wood_long")
			as BuildingDef).cost.get(&"wood", 0))
	assert_true(short_cost * 2 < long_cost, "two shorts really are cheaper than a long")

	world.player_for(1).stock[&"wood"] = short_cost * 2
	var origin := _clear_run(30)
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(29, 0))))
	var walls := _walls()
	assert_eq(walls.size(), 1, "one piece, downgraded to what the budget reached")
	assert_eq(walls[0].origin_tile(), origin, "starting at the anchor")
	# THE LARGEST AFFORDABLE, not the smallest. Two shorts' worth of wood is exactly a
	# medium's price and a medium is exactly two shorts long, so the downgrade buys six
	# tiles of wall in one piece rather than three in one -- same ground, same money,
	# one fewer seam. That it lands on medium rather than short is the rule working,
	# and this assertion was the other way round until the suite said so.
	assert_eq(walls[0].def_id, &"building.wall_wood_medium")
	assert_eq(walls[0].footprint.x, 6)


func test_a_downgraded_piece_never_overruns_its_own_span() -> void:
	# The downgrade picks from the tier by length and must stay INSIDE the segment
	# the plan gave it -- a longer piece squeezed into a shorter span would claim
	# ground past where the finger stopped.
	var short_cost := int((GameDataRegistry.building(WOOD) as BuildingDef).cost.get(&"wood", 0))
	world.player_for(1).stock[&"wood"] = short_cost * 20
	# A 3-tile drag plans exactly one short piece, and 20 shorts' worth of wood must
	# not turn it into a long one.
	assert_true(_run(PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR)))
	var walls := _walls()
	assert_eq(walls.size(), 1)
	assert_eq(walls[0].footprint.x, 3, "a tap is a short piece however rich you are")


func test_the_builders_are_spread_across_the_segments() -> void:
	# All five villagers queued on the first of twelve foundations would raise it in
	# a fifth of the time and then idle -- the same "a foundation nobody returns to"
	# pattern the PlayTest AI needed a standing order for.
	var villagers: Array[int] = []
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimUnit and e.owner_id == 1 and e.def_id == &"unit.villager":
			villagers.append(int(id))
	assert_true(villagers.size() >= 2, "the start has villagers to send")

	var origin := _clear_run(18)
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(17, 0),
			villagers)))
	var segments := _walls().size()
	assert_true(segments >= 2, "the run placed %d segments to spread across" % segments)

	var targets := {}
	for id in villagers:
		var u := world.get_entity(id) as SimUnit
		if u.task == SimUnit.Task.BUILD:
			targets[u.task_target_id] = true
	# As many distinct foundations as there were villagers to send, capped by how many
	# segments there are -- which is exactly what round-robin promises.
	assert_eq(targets.size(), mini(villagers.size(), segments),
			"one villager per segment, wrapping: %d villagers over %d segments"
			% [villagers.size(), segments])


func test_a_wall_you_have_not_reached_the_age_for_is_refused() -> void:
	# Enforced on the SERVER as well as by the menu, for the reason
	# PlaceBuildingCommand records: the menu is a client.
	world.player_for(1).age = 1
	var cmd := PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR + Vector2i(8, 0))
	assert_false(cmd.validate(world), "no palisade in age 1")


func test_a_def_that_is_not_a_wall_tier_is_refused() -> void:
	# `wall_lengths` being non-empty IS the flag, so a house dragged as a wall is a
	# command that must not quietly place one house.
	assert_false(PlaceWallCommand.new(1, &"building.house", CLEAR, CLEAR).validate(world))
	# Nor a segment the drag chooses rather than the player: only the tier's
	# representative carries the list.
	assert_false(PlaceWallCommand.new(1, &"building.wall_wood_long", CLEAR, CLEAR)
			.validate(world))


func test_a_run_survives_the_wire() -> void:
	var back := Command.from_dict(PlaceWallCommand.new(
			2, WOOD, Vector2i(3, 4), Vector2i(9, 4), [7, 8] as Array[int], 11).to_dict())
	assert_not_null(back, "the dispatch table knows the type")
	assert_true(back is PlaceWallCommand)
	assert_eq(back.player_id, 2)
	assert_eq(back.def_id, WOOD)
	assert_eq(back.from, Vector2i(3, 4))
	assert_eq(back.to, Vector2i(9, 4))
	assert_eq(back.builder_ids, [7, 8] as Array[int])
	assert_eq(back.issued_tick, 11)


# ── gates ───────────────────────────────────────────────────────────────────

func _a_gate() -> SimBuilding:
	# COMPLETE, because a gate cannot be locked until it is built -- which is itself
	# asserted below.
	return world.spawn_building(WOOD_GATE, 1, CLEAR, SimBuilding.Phase.COMPLETE, true,
			Vector2i(9, WallPlan.DEPTH), WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_X])


func test_a_gate_starts_open_and_is_walked_through() -> void:
	# The project owner's call (2026-08-21): a wall never strands its own villagers,
	# and the price is that it does nothing until somebody locks it.
	var gate := _a_gate()
	assert_false(gate.gate_locked)
	assert_true(world.map.is_passable(CLEAR), "an open gate is a doorway")
	# And it still CLAIMS the ground, so nothing is built on top of it -- the same
	# split a field makes between "occupied" and "blocking".
	assert_false(world.map.can_place_building(SimMap.footprint_rect(CLEAR, Vector2i(1, 1))))


func test_locking_a_gate_closes_the_ground() -> void:
	var gate := _a_gate()
	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_true(gate.gate_locked)
	assert_false(world.map.is_passable(CLEAR), "a locked gate is a wall")


func test_unlocking_opens_it_again() -> void:
	var gate := _a_gate()
	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_true(_run(ToggleGateCommand.new(1, gate.id, false)))
	assert_false(gate.gate_locked)
	assert_true(world.map.is_passable(CLEAR))


func test_the_command_names_a_state_so_a_repeat_is_harmless() -> void:
	# A toggle would depend on when it landed: on a client the second tap goes out
	# before the first one's snapshot comes back, so a double tap would be as likely
	# to close a gate as open it.
	var gate := _a_gate()
	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_true(gate.gate_locked, "still shut, not flipped back open")


func test_locking_shoves_whoever_is_in_the_doorway_clear() -> void:
	# A unit inside a blocked cell is a unit AStarGrid2D will not plan a route OUT
	# of -- it stands there for the rest of the match. That cost the AI a barracks
	# once already (SimWorld._evict_from_footprint), and a gate swinging shut is the
	# one thing in the game that can create the situation on purpose.
	var gate := _a_gate()
	var villager := world.spawn_unit(&"unit.villager", 1, CLEAR + Vector2i(1, 0))
	assert_not_null(villager)
	assert_eq(villager.tile(), CLEAR + Vector2i(1, 0), "standing in the gateway")

	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_false(gate.footprint_rect().has_point(villager.tile()),
			"pushed clear of the footprint, not sealed inside it")


func test_a_gate_under_construction_cannot_be_locked_and_stays_open() -> void:
	# It is a hole in the ground with a frame around it. Letting it be shut would
	# mean sealing a gap with something nobody has built.
	var gate := world.spawn_building(WOOD_GATE, 1, CLEAR, SimBuilding.Phase.FOUNDATION,
			true, Vector2i(9, WallPlan.DEPTH), 0)
	assert_false(ToggleGateCommand.new(1, gate.id, true).validate(world))
	assert_true(world.map.is_passable(CLEAR), "and it is still a doorway")


func test_an_ordinary_wall_segment_is_not_a_gate() -> void:
	var seg := world.spawn_building(&"building.wall_wood_long", 1, CLEAR,
			SimBuilding.Phase.COMPLETE, true, Vector2i(9, WallPlan.DEPTH), 0)
	assert_false(seg.is_gate)
	assert_false(ToggleGateCommand.new(1, seg.id, false).validate(world),
			"there is no door in it to open")
	assert_false(world.map.is_passable(CLEAR), "and it blocks from the start")


func test_you_cannot_open_somebody_elses_gate() -> void:
	# Otherwise the army outside opens the gate it is standing at, which is not a
	# siege. `Net` overwriting `player_id` with the sender's real id is what makes
	# this check bite.
	var gate := _a_gate()
	assert_true(_run(ToggleGateCommand.new(1, gate.id, true)))
	assert_false(ToggleGateCommand.new(2, gate.id, false).validate(world))
	assert_true(gate.gate_locked)


func test_a_gate_survives_the_wire() -> void:
	var back := Command.from_dict(ToggleGateCommand.new(4, 77, true, 5).to_dict())
	assert_not_null(back, "the dispatch table knows the type")
	assert_true(back is ToggleGateCommand)
	assert_eq(back.player_id, 4)
	assert_eq(back.building_id, 77)
	assert_true(back.locked)
	assert_eq(back.issued_tick, 5)


# ── the desync surface ──────────────────────────────────────────────────────

func test_a_locked_gate_is_in_the_state_hash() -> void:
	# It moves the MOVEMENT GRID, so two hosts disagreeing about a doorway would
	# route the same army two different ways and diverge in position a tick later --
	# which `pos` reports long after the cause.
	var gate := _a_gate()
	var before := world.state_hash()
	world.set_gate_locked(gate, true)
	assert_ne(world.state_hash(), before)


func test_a_wall_segment_facing_is_in_the_state_hash() -> void:
	# Placement state that nothing recomputes: a wrong one stays wrong, and it is
	# what the view derives the transposed footprint from.
	var seg := world.spawn_building(&"building.wall_wood_long", 1, CLEAR,
			SimBuilding.Phase.COMPLETE, true, Vector2i(9, WallPlan.DEPTH), 0)
	var before := world.state_hash()
	seg.facing = WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y]
	assert_ne(world.state_hash(), before)


func test_two_worlds_given_the_same_drag_stay_identical() -> void:
	# The determinism check every other command file runs. A wall run is the first
	# command that places SEVERAL entities from one order, so the id assignment and
	# the payment order both have to be reproducible.
	#
	# BOTH WORLDS BUILT HERE, not one of them inherited from `before_each`: that one
	# has been handed 10,000 of four resources and an age, and matching those on a
	# second world by hand is how a determinism test comes to compare two things that
	# were never equal (it failed exactly that way first time round).
	var a := _fresh()
	var b := _fresh()
	assert_eq(a.state_hash(), b.state_hash(), "identical worlds start equal")

	for w: SimWorld in [a, b]:
		w.queue_command(PlaceWallCommand.new(1, WOOD, CLEAR, CLEAR + Vector2i(17, 0)))
		w.step()
	assert_eq(a.state_hash(), b.state_hash(), "and stay equal through a run")

	for i in range(20):
		a.step()
		b.step()
		assert_eq(a.state_hash(), b.state_hash(), "diverged on tick %d" % (i + 1))


## A world set up exactly as `before_each` does, so two of them are genuinely equal.
func _fresh() -> SimWorld:
	var cfg := MatchConfig.debug_skirmish()
	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	var p := w.player_for(1)
	p.age = 2
	for kind in [&"wood", &"stone", &"food", &"gold"]:
		p.stock[kind] = 10_000
	return w
