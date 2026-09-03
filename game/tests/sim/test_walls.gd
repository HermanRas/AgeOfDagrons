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


# ── the crew builds the WHOLE run (2026-08-22) ──────────────────────────────

func test_one_villager_raises_every_segment_of_a_run() -> void:
	# THE REPORTED BUG, end to end: "builder does not continue to build all the
	# pieces, stops after 1". `BuildSystem._finished` called `stop()` for anything that
	# was not a field and there was no re-scan at all -- harmless while a placement was
	# one building, and exactly wrong for a drag that lays a dozen.
	#
	# One villager and a two-piece run, so the only way every segment finishes is by
	# the builder finding the next one itself.
	var origin := _clear_run(12)
	var villager := world.spawn_unit(&"unit.villager", 1, origin + Vector2i(0, 3))
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(11, 0),
			[villager.id])))

	var segments := _walls()
	assert_true(segments.size() >= 2, "a 12-tile drag is more than one piece")

	# 9 + 3 tiles is 360 + 120 ticks of work, plus the walk between them.
	for i in range(1200):
		world.step()
		var all_up := true
		for s in segments:
			if not s.is_complete():
				all_up = false
				break
		if all_up:
			return
	var standing := 0
	for s in segments:
		if s.is_complete():
			standing += 1
	assert_true(false, "only %d of %d segments went up" % [standing, segments.size()])


func test_the_builder_walks_the_length_of_a_run_it_did_not_start_at_the_end_of() -> void:
	# The bound is `SimSystem.SAME_WORK_RADIUS`, measured from the SEGMENT just
	# finished rather than from the unit, so a run longer than the radius is still
	# built end to end -- each piece is within ten tiles of the one before it even
	# when the far end is thirty tiles from where the villager started.
	var origin := _clear_run(24)
	var villager := world.spawn_unit(&"unit.villager", 1, origin + Vector2i(0, 3))
	assert_true(_run(PlaceWallCommand.new(1, WOOD, origin, origin + Vector2i(23, 0),
			[villager.id])))
	var segments := _walls()
	assert_true(segments.size() >= 3, "24 tiles is 9 + 9 + 6")

	for i in range(3000):
		world.step()
		var all_up := true
		for s in segments:
			if not s.is_complete():
				all_up = false
				break
		if all_up:
			return
	var standing := 0
	for s in segments:
		if s.is_complete():
			standing += 1
	assert_true(false, "only %d of %d segments went up" % [standing, segments.size()])


# ── upgrading a wall into a gate (2026-08-22) ───────────────────────────────
#
# THE ONLY WAY TO GET A GATE, and the reason is orientation. A gate is 9x2 and
# `PlaceBuildingCommand` carries no facing and never transposes a footprint, so a
# tap-placed gate could only ever lie east-west -- a north-south wall could not have
# one, which is what the project owner hit while playing. Upgrading the segment
# sidesteps the question: the wall already knows its axis and the gate inherits it.

const WOOD_LONG := &"building.wall_wood_long"


## A finished long segment on the given axis, ready to upgrade.
func _a_long_wall(axis: int = WallPlan.AXIS_X, at: Vector2i = CLEAR) -> SimBuilding:
	return world.spawn_building(WOOD_LONG, 1, at, SimBuilding.Phase.COMPLETE, true,
			WallPlan.footprint_for(9, axis), WallPlan.FACING_FOR_AXIS[axis])


func test_upgrading_a_long_wall_turns_it_into_that_tier_s_gate() -> void:
	var wall := _a_long_wall()
	var id := wall.id
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))

	assert_eq(wall.def_id, WOOD_GATE, "it is a gate now")
	assert_true(wall.is_gate)
	# THE ID SURVIVES. A despawn-and-respawn would empty the panel the player pressed
	# the button on, and would tell every other client a building was destroyed when
	# one was improved.
	assert_eq(wall.id, id, "same entity, upgraded in place")
	assert_eq(world.get_entity(id), wall)
	assert_false(world.removed_this_tick.has(id), "an upgrade is not a demolition")


func test_the_gate_inherits_the_wall_s_axis_rather_than_choosing_one() -> void:
	# The whole point of the feature. A north-south wall could never carry a gate
	# before this, because the only way to get one was a tap placement that was always
	# 9x2 east-west.
	var origin := _clear_run(9)
	var wall := world.spawn_building(WOOD_LONG, 1, origin, SimBuilding.Phase.COMPLETE,
			true, WallPlan.footprint_for(9, WallPlan.AXIS_Y),
			WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y])
	var before := wall.footprint_rect()

	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_eq(wall.footprint, Vector2i(WallPlan.DEPTH, 9), "still lying north-south")
	assert_eq(wall.facing, WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y], "and still facing that way")
	assert_eq(wall.footprint_rect(), before, "on exactly the ground it already held")


func test_the_upgrade_opens_the_wall_because_a_new_gate_is_open() -> void:
	# A wall blocks and an unlocked gate does not, so this is the tick the hole
	# appears. It follows from `blocks_now()` rather than being special-cased.
	var wall := _a_long_wall()
	assert_false(world.map.is_passable(CLEAR), "solid while it is a wall")
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_false(wall.gate_locked, "a new gate starts open")
	assert_true(world.map.is_passable(CLEAR), "and the ground opened with it")
	# Still CLAIMED, though -- nothing may be built in the doorway.
	assert_false(world.map.can_place_building(SimMap.footprint_rect(CLEAR, Vector2i(1, 1))))


func test_the_price_is_the_difference_and_not_the_whole_gate() -> void:
	# 36 wood was already spent on the wall and the gate lists 50, so the upgrade is
	# 14. Charging 50 again would make upgrading dearer than demolishing and rebuilding.
	var wall := _a_long_wall()
	var before := _held(&"wood")
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))

	var from: BuildingDef = GameDataRegistry.building(WOOD_LONG)
	var to: BuildingDef = GameDataRegistry.building(WOOD_GATE)
	var expected := int(to.cost.get(&"wood", 0)) - int(from.cost.get(&"wood", 0))
	assert_eq(before - _held(&"wood"), expected, "paid the difference only")
	assert_true(expected > 0 and expected < int(to.cost.get(&"wood", 0)),
			"and the difference is a real, smaller number")


func test_a_kind_the_wall_never_paid_for_is_charged_in_full() -> void:
	# The stone gate costs 30 wood on top of its stone, and the stone wall paid no
	# wood at all -- so the delta is the whole 30 there and the difference in stone.
	# There is no credit to apply: the stone wall's 45 stone is all wanted by the gate.
	var from: BuildingDef = GameDataRegistry.building(&"building.wall_stone_long")
	var to: BuildingDef = GameDataRegistry.building(&"building.wall_stone_gate")
	var delta := UpgradeBuildingCommand.cost_delta(from, to)
	assert_eq(int(delta.get(&"wood", 0)), int(to.cost[&"wood"]), "wood was never paid before")
	assert_eq(int(delta.get(&"stone", 0)),
			int(to.cost[&"stone"]) - int(from.cost[&"stone"]), "stone is the difference")
	for kind in delta:
		assert_true(int(delta[kind]) > 0, "%s is a charge, never a refund" % kind)


func test_a_surplus_of_a_kind_the_target_STILL_WANTS_is_credited_too() -> void:
	# The palisade gate is the case that needs it. 50 wood becoming a stone gate that
	# asks for 30 wood and 45 stone leaves 20 wood over -- and crediting only the kinds
	# the target wants NONE of would drop that on the floor and charge the full 45 stone,
	# while the player watches a 50-wood gate be consumed by the upgrade.
	var from: BuildingDef = GameDataRegistry.building(WOOD_GATE)
	var to: BuildingDef = GameDataRegistry.building(&"building.wall_stone_gate")
	var delta := UpgradeBuildingCommand.cost_delta(from, to)
	assert_false(delta.has(&"wood"), "50 already paid covers the 30 it asks for")
	var surplus := int(from.cost[&"wood"]) - int(to.cost[&"wood"])
	assert_eq(int(delta.get(&"stone", 0)), int(to.cost[&"stone"]) - surplus,
			"and the 20 left over comes off the stone")


func test_health_carries_its_fraction_across_the_upgrade() -> void:
	# A wall at half health becomes a gate at half health. Anything else would make
	# upgrading a way to heal, or a way to be punished for it -- the two defs have
	# different maxima (1200 and 1000), so the absolute number cannot simply ride over.
	var wall := _a_long_wall()
	wall.hp = wall.max_hp / 2
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_eq(wall.max_hp, GameDataRegistry.building(WOOD_GATE).hp, "the gate's own maximum")
	assert_almost_eq(float(wall.hp) / float(wall.max_hp), 0.5, 0.02, "still half hurt")


func test_an_undamaged_wall_becomes_an_undamaged_gate_exactly() -> void:
	# Pinned rather than left to the fraction, because the commonest case must not
	# round to 999/1000 and show a damage dot on a brand new gate.
	var wall := _a_long_wall()
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_eq(wall.hp, wall.max_hp, "full health, not a rounding of it")


func test_only_the_long_segment_is_offered_a_gate() -> void:
	# The gate is 9x2 and `convert_building` keeps the ground the building already
	# holds, so a 3x2 short segment has nowhere to put one.
	#
	# ⚠️ THIS USED TO ASSERT THAT A SHORT SEGMENT COULD NOT BE UPGRADED AT ALL, and 5.3
	# ended that: every piece now climbs its tier at its own length. Worse, the old
	# assertion would still have PASSED -- a wood wall's stone target is age 3 and this
	# fixture's player is younger, so `validate()` would have refused it for a reason
	# that has nothing to do with what the test is named after. A fixture that agrees
	# with the change for the wrong reason is the trap §5 of AGENT_GAME_CODER.md is
	# about, so this asks the DEFS what they offer instead.
	for id in [&"building.wall_wood_short", &"building.wall_wood_medium",
			&"building.wall_stone_short", &"building.wall_stone_medium"]:
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_false(bd.upgrades_to.is_empty(), "%s climbs its tier" % id)
		for target in bd.upgrades_to:
			assert_false(GameDataRegistry.building(target).is_gate,
					"%s is too short to hold a gate, but offers %s" % [id, target])


# ── the tier ladder (5.3, owner 2026-09-03) ─────────────────────────────────

func test_every_piece_climbs_its_tier_length_for_length() -> void:
	# DERIVED FROM THE DEFS RATHER THAN LISTED, so adding a fourth tier or renaming a
	# piece fails here instead of quietly leaving a length behind. A wall the drag laid
	# down as a mix of lengths has to be upgradable piece by piece; a ladder with a hole
	# in it is a wall the player can only half improve, and they cannot see why.
	for pair in [["wood", "stone"], ["stone", "reinforced"]]:
		for piece in ["short", "medium", "long", "gate"]:
			var from_id := StringName("building.wall_%s_%s" % [pair[0], piece])
			var want := StringName("building.wall_%s_%s" % [pair[1], piece])
			var bd: BuildingDef = GameDataRegistry.building(from_id)
			assert_not_null(bd, from_id)
			assert_true(bd.upgrades_to.has(want),
					"%s should climb to %s, offers %s" % [from_id, want, bd.upgrades_to])


func test_a_long_wall_offers_its_gate_FIRST_and_then_its_tier() -> void:
	# The order is the order the tiles appear in, and the gate has been on that panel
	# since 5.8 -- a button that moves under a player's thumb because a new one was
	# added above it is the change nobody asked for.
	var bd: BuildingDef = GameDataRegistry.building(WOOD_LONG)
	assert_eq(bd.upgrades_to,
			[WOOD_GATE, &"building.wall_stone_long"] as Array[StringName])


func test_the_wood_a_wall_cost_is_credited_against_a_stone_one() -> void:
	# The owner's call, 2026-09-03: *"lets credit the wood onto stone"*. Same-kind credit
	# alone would have charged the full 45 stone, since a stone wall shares no resource
	# with the palisade it replaces -- a price that makes an upgrade cost exactly what a
	# rebuild costs, which is another way of saying there is no upgrade.
	#
	# 1:1, because `market.json` prices food, wood and stone identically against gold and
	# that is the only exchange rate this game has ever declared.
	var from: BuildingDef = GameDataRegistry.building(WOOD_LONG)
	var to: BuildingDef = GameDataRegistry.building(&"building.wall_stone_long")
	var delta := UpgradeBuildingCommand.cost_delta(from, to)
	var expected := int(to.cost[&"stone"]) - int(from.cost[&"wood"])
	assert_eq(int(delta.get(&"stone", 0)), expected, "45 stone less 36 wood of credit")
	assert_false(delta.has(&"wood"), "and no wood is asked for again")


func test_the_credit_can_cover_a_whole_upgrade_and_never_pays_out() -> void:
	# A cheaper target must be free rather than a refund: `SimPlayer.pay` on a negative
	# would hand resources back for downgrading, and the same arithmetic runs on every
	# client. There is no such pair in the roster today, which is exactly why it is
	# worth pinning before somebody authors one.
	var dear: BuildingDef = GameDataRegistry.building(&"building.wall_reinforced_long")
	var cheap: BuildingDef = GameDataRegistry.building(WOOD_LONG)
	var delta := UpgradeBuildingCommand.cost_delta(dear, cheap)
	for kind in delta:
		assert_true(int(delta[kind]) > 0, "%s is a charge, never a refund" % kind)
	assert_true(delta.is_empty(), "75 stone of credit covers a 36-wood wall outright")


func test_a_tier_upgrade_charges_what_the_delta_says_and_converts_in_place() -> void:
	var wall := _a_long_wall()
	var id := wall.id
	world.player_for(1).age = 3
	world.player_for(1).stock[&"stone"] = 500
	var before := _held(&"stone")

	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id, &"building.wall_stone_long")))
	assert_eq(wall.def_id, &"building.wall_stone_long", "stone now")
	assert_eq(wall.id, id, "same entity, upgraded in place")
	assert_false(wall.is_gate, "and it did not become a gate by accident")
	var expected := UpgradeBuildingCommand.cost_delta(
			GameDataRegistry.building(WOOD_LONG),
			GameDataRegistry.building(&"building.wall_stone_long"))
	assert_eq(before - _held(&"stone"), int(expected.get(&"stone", 0)))


func test_a_command_may_not_name_a_target_the_def_does_not_offer() -> void:
	# THE LIST IS THE AUTHORITY AND THE SERVER IS THE ONLY TRUST BOUNDARY. Without this,
	# a client could send `building.castle` and turn a 36-wood palisade into a 650-stone
	# castle for the difference -- which is a real exploit and not a tidiness point.
	var wall := _a_long_wall()
	world.player_for(1).age = 4
	world.player_for(1).stock[&"stone"] = 5000
	assert_false(UpgradeBuildingCommand.new(1, wall.id, &"building.castle").validate(world))
	assert_false(UpgradeBuildingCommand.new(1, wall.id,
			&"building.wall_reinforced_long").validate(world),
			"two rungs at once is not on the list either")
	assert_eq(wall.def_id, WOOD_LONG, "untouched")


func test_an_empty_target_still_means_the_first_one() -> void:
	# Every command written before 5.3 named no target, and there are three years of
	# tests in this file that still do not. Empty resolves to the head of the list, which
	# is why that order is load bearing.
	var wall := _a_long_wall()
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_eq(wall.def_id, WOOD_GATE, "the gate, as it always was")


func test_every_declared_upgrade_in_the_whole_ROSTER_keeps_its_footprint() -> void:
	# ⚠️ THE GUARD THAT MAKES THE FEATURE SAFE TO EXTEND, and it is the reason the watch
	# tower does not become a guard tower: [3, 2] against [3, 3]. `convert_building` keeps
	# the ground the building already holds, so a bigger target would occupy tiles nobody
	# checked were free -- a wall growing a row into a unit standing beside it.
	#
	# Walked over EVERY building rather than over the walls, because the next upgrade
	# somebody adds will not be a wall, and this is the test that will meet it first.
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		for target in bd.upgrades_to:
			var to: BuildingDef = GameDataRegistry.building(target)
			assert_not_null(to, "%s upgrades to %s, which does not exist" % [id, target])
			if to == null:
				continue
			assert_eq(to.footprint, bd.footprint,
					"%s [%s] cannot become %s [%s]" % [id, bd.footprint, target, to.footprint])


func test_the_watch_tower_does_not_upgrade_to_the_guard_tower() -> void:
	# The owner's decision, 2026-09-03, and it is pinned by name because it is the pair
	# anybody reading the roster proposes first. The footprints differ, so it would be
	# refused anyway -- this says it was a decision rather than an oversight.
	assert_true((GameDataRegistry.building(&"building.watch_tower") as BuildingDef)
			.upgrades_to.is_empty())
	assert_ne((GameDataRegistry.building(&"building.watch_tower") as BuildingDef).footprint,
			(GameDataRegistry.building(&"building.guard_tower") as BuildingDef).footprint,
			"and this is why")


func test_a_foundation_cannot_be_upgraded() -> void:
	# Otherwise a player skips most of a wall's build time by ordering the cheap thing
	# and immediately improving it -- and there is no finished wall to convert anyway.
	var wall := world.spawn_building(WOOD_LONG, 1, CLEAR, SimBuilding.Phase.FOUNDATION,
			true, Vector2i(9, WallPlan.DEPTH), 0)
	assert_false(UpgradeBuildingCommand.new(1, wall.id).validate(world))


func test_you_cannot_upgrade_somebody_elses_wall() -> void:
	var wall := _a_long_wall()
	assert_false(UpgradeBuildingCommand.new(2, wall.id).validate(world))
	assert_eq(wall.def_id, WOOD_LONG, "untouched")


func test_a_gate_climbs_to_the_next_tier_s_gate_and_never_back_to_a_wall() -> void:
	# Since 5.3 a palisade gate becomes a stone gate becomes a reinforced one. What must
	# NOT appear is a target that is not a gate: a doorway silently becoming solid wall
	# would shut a hole the player deliberately left in their own defences.
	var gate: BuildingDef = GameDataRegistry.building(WOOD_GATE)
	assert_eq(gate.upgrades_to, [&"building.wall_stone_gate"] as Array[StringName])
	for target in gate.upgrades_to:
		assert_true(GameDataRegistry.building(target).is_gate, "%s is a gate" % target)


func test_the_top_of_the_ladder_upgrades_to_nothing() -> void:
	# The chain ends rather than looping, which is what it always did -- the end has
	# simply moved from the wood gate to the reinforced tier.
	for id in [&"building.wall_reinforced_short", &"building.wall_reinforced_medium",
			&"building.wall_reinforced_gate"]:
		assert_true((GameDataRegistry.building(id) as BuildingDef).upgrades_to.is_empty(),
				"%s is the top of its ladder" % id)
	# The reinforced LONG is the exception and keeps exactly one: its own gate.
	assert_eq((GameDataRegistry.building(&"building.wall_reinforced_long") as BuildingDef)
			.upgrades_to, [&"building.wall_reinforced_gate"] as Array[StringName])


func test_an_upgrade_you_cannot_afford_is_refused_and_charges_nothing() -> void:
	var wall := _a_long_wall()
	world.player_for(1).stock[&"wood"] = 1
	assert_false(UpgradeBuildingCommand.new(1, wall.id).validate(world))
	assert_eq(wall.def_id, WOOD_LONG, "still a wall")
	assert_eq(_held(&"wood"), 1, "and still holding the wood")


func test_the_age_gate_is_on_the_gate_and_not_on_the_wall_you_have() -> void:
	# A stone wall is age 3 and so is its gate, so this bites on a player who somehow
	# holds a wall above their own age -- the server is the only trust boundary, and
	# the panel hiding the button is not a rule.
	var wall := world.spawn_building(&"building.wall_stone_long", 1, CLEAR,
			SimBuilding.Phase.COMPLETE, true, Vector2i(9, WallPlan.DEPTH), 0)
	world.player_for(1).age = 2
	assert_false(UpgradeBuildingCommand.new(1, wall.id).validate(world))
	world.player_for(1).age = 3
	assert_true(UpgradeBuildingCommand.new(1, wall.id).validate(world))


func test_the_upgrade_survives_the_wire() -> void:
	var round_tripped := Command.from_dict(
			UpgradeBuildingCommand.new(1, 77, &"building.wall_stone_long").to_dict())
	assert_true(round_tripped is UpgradeBuildingCommand)
	assert_eq((round_tripped as UpgradeBuildingCommand).building_id, 77)
	assert_eq(round_tripped.player_id, 1)
	# THE TARGET TRAVELS. Without it the server would have to guess which of a long
	# wall's two futures the player pressed, and JSON has no StringName -- so this also
	# pins the conversion at the boundary that every other id off the wire needs.
	assert_eq((round_tripped as UpgradeBuildingCommand).target_def_id,
			&"building.wall_stone_long")


func test_the_upgrade_moves_the_state_hash() -> void:
	# It changes `def_id`, the movement grid and the player's stock. Two hosts that
	# disagreed about whether a wall had become a gate would route armies through a
	# hole one of them does not have.
	var wall := _a_long_wall()
	var before := world.state_hash()
	assert_true(_run(UpgradeBuildingCommand.new(1, wall.id)))
	assert_ne(world.state_hash(), before)


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
	#
	# BOTH FACINGS NAMED SYMBOLICALLY, and the fixture used to spawn at a literal 0.
	# That was the axis-Y facing under the old (wrong) `FACING_FOR_AXIS`, so correcting
	# the constant on 2026-08-28 turned this into "set the facing to the one it already
	# has, and assert the hash changed". A test that hard-codes one side of the very
	# table it is checking is a test that fails for the wrong reason.
	var seg := world.spawn_building(&"building.wall_wood_long", 1, CLEAR,
			SimBuilding.Phase.COMPLETE, true, Vector2i(9, WallPlan.DEPTH),
			WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_X])
	var before := world.state_hash()
	seg.facing = WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y]
	assert_ne(world.state_hash(), before, "turning a segment onto the other axis is a different world")


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
