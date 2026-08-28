## Siege engines travelling packed and fighting deployed (PLAN.md 4.13, 9.2.1).
##
## The property under test is that THE TWO STATES ARE EXCLUSIVE and that the transition
## between them costs real time. A trebuchet that could shoot while rolling would be a
## mobile turret out-ranging every building in the game (its 12 against a castle's 8),
## which is the whole reason 0 A.D. ships these three as actor pairs in the first place.
##
## The other half is that the machine is AUTOMATIC: an order implies its own state, so
## what is asserted is the behaviour of `MoveCommand` and `AttackCommand`, not of a
## deploy verb. There is no deploy verb -- see `SiegeSystem`'s header for why.
extends TestCase

const BALLISTA := &"unit.ballista"
const TREBUCHET := &"unit.trebuchet"

## How far apart the two ends of the test lane are, in tiles. Comfortably past the
## trebuchet's 12, so an attack order across it is certain to involve a walk.
const LANE_TILES := 30

var world: SimWorld

## Two spots on a clear east-west lane: the engine starts at `_home` and `_away` has
## room for a 4x4 house. FOUND RATHER THAN ASSUMED -- `test_walls._clear_run` records
## what assuming a clear strip on this map cost there, which was two tests at once.
var _home: Vector2i
var _away: Vector2i


func before_each() -> void:
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)
	_pick_lane()


func _pick_lane() -> void:
	for y in range(2, world.map.size.y - 10):
		for x in range(2, world.map.size.x - LANE_TILES - 2):
			if world.map.can_place_building(
					SimMap.footprint_rect(Vector2i(x, y), Vector2i(LANE_TILES, 8))):
				_home = Vector2i(x + 1, y + 2)
				_away = Vector2i(x + LANE_TILES - 5, y + 2)
				return
	assert_true(false, "no clear %dx8 lane on the debug map" % LANE_TILES)


func _engine(def_id: StringName = BALLISTA) -> SimUnit:
	return world.spawn_unit(def_id, 1, _home)


func _def(u: SimUnit) -> UnitDef:
	return world.unit_def(u.def_id)


## An enemy building for the engine to shoot, owned by player 2.
func _target(at: Vector2i) -> SimBuilding:
	return world.spawn_building(&"building.house", 2, at, SimBuilding.Phase.COMPLETE, true)


## Step until `pred` holds, returning how many ticks it took or -1. Used instead of a
## fixed count where "eventually" is what is meant, and it reports the tick it actually
## happened on where a fixed count would just say false.
func _step_until(pred: Callable, limit: int = 400) -> int:
	for i in range(limit):
		world.step()
		if pred.call():
			return i + 1
	return -1


# ── the two states ──────────────────────────────────────────────────────────

func test_an_engine_is_trained_packed_so_it_can_leave_the_workshop() -> void:
	# Deployed-on-spawn would leave every new engine standing in the workshop doorway
	# for `pack_ticks` before it could walk to the rally point (4.8b), which is the one
	# thing it is certain to be asked to do first.
	var u := _engine()
	assert_true(u.packs, "the ballista declares packed art and so packs")
	assert_true(u.packed, "and comes out of the workshop folded up")
	assert_eq(u.pack_ticks_left, 0, "settled, not mid-transition")
	assert_true(u.can_move())
	assert_false(u.can_fire(), "a packed engine cannot shoot")


func test_a_unit_with_no_packed_art_does_not_pack_at_all() -> void:
	# `unit.siege_ram` is the case that keeps `packing` honest: a siege engine, mobile,
	# one actor. A rule that inferred packing from "is siege" or from `speed == 0` would
	# catch it wrongly, so the DATA is the switch.
	var ram := world.spawn_unit(&"unit.siege_ram", 1, _home)
	assert_false(ram.packs)
	assert_true(ram.can_move(), "and is therefore always able to do both")
	assert_true(ram.can_fire())
	world.step()
	assert_eq(ram.speed, world.unit_def(&"unit.siege_ram").speed,
			"SiegeSystem leaves its speed alone")


func test_the_two_states_are_never_both_available() -> void:
	# The invariant the whole feature exists for, asserted across every state a siege
	# engine can be in rather than at one convenient moment: packed, deployed, and both
	# halves of the transition between them.
	var u := _engine()
	for state in [[true, 0], [true, 5], [false, 0], [false, 5]]:
		u.packed = bool(state[0])
		u.pack_ticks_left = int(state[1])
		assert_false(u.can_move() and u.can_fire(),
				"packed=%s ticks=%s is not both" % state)


# ── moving ──────────────────────────────────────────────────────────────────

func test_an_order_to_move_folds_a_deployed_engine_up_before_it_walks() -> void:
	var u := _engine()
	# Start it deployed, which is where an engine that has been fighting is.
	u.packed = false
	world.step()
	assert_eq(u.speed, 0, "a deployed engine has nothing to spend")

	var from := u.tile()
	world.queue_command(MoveCommand.new(1, [u.id] as Array[int], _away))
	world.step()
	assert_true(u.packed, "the order folds it up immediately, so the art can change")
	assert_true(u.pack_ticks_left > 0, "but it is not usable yet")
	assert_eq(u.tile(), from, "and it has not moved")

	# STILL STANDING MOST OF THE WAY THROUGH. The cost has to be real or the feature is
	# decoration, and a two-tick fixture would have passed against a machine that
	# flipped instantly.
	for _i in range(_def(u).pack_ticks - 2):
		world.step()
	assert_eq(u.tile(), from, "still stowing, %d ticks in" % _def(u).pack_ticks)

	assert_true(_step_until(func(): return u.tile() != from) > 0, "and then it rolls")
	assert_eq(u.speed, _def(u).packed_speed, "at its packed speed, not its deployed 0")


func test_a_packed_engine_ordered_to_move_does_not_restart_its_timer() -> void:
	# `begin_packing` is idempotent on purpose: `SiegeSystem` asks every tick a unit
	# holds a route, so a version that reset the countdown each time would freeze an
	# engine mid-walk under itself, forever.
	var u := _engine()
	world.queue_command(MoveCommand.new(1, [u.id] as Array[int], _away))
	world.step()
	assert_eq(u.pack_ticks_left, 0, "already packed, so there was nothing to do")
	var from := u.tile()
	assert_true(_step_until(func(): return u.tile() != from) > 0, "it just goes")


func test_a_deployed_engine_can_be_ordered_to_move_at_all() -> void:
	# THIS WAS BROKEN BEFORE PACKING EXISTED and nothing reported it. All three engines
	# carried `speed: 0`, no command refused them, so one sent across the map took a
	# route from `PathService` and held it unwalked forever -- ordered, pathed, and
	# standing still, with nothing to say it had failed.
	var u := _engine()
	u.packed = false
	var cmd := MoveCommand.new(1, [u.id] as Array[int], _away)
	assert_true(cmd.validate(world), "the order is legal")
	world.queue_command(cmd)
	var took := _step_until(func(): return u.tile() == _away, 900)
	assert_true(took > 0, "and it arrives rather than standing there pathed")


# ── fighting ────────────────────────────────────────────────────────────────

func test_an_engine_sets_up_before_it_can_land_a_blow() -> void:
	var u := _engine()
	# Already in range, so nothing here waits on a walk: `attack_range` is 9 and the
	# house's near wall is 3 tiles off.
	var house := _target(_home + Vector2i(3, -1))
	var full := house.hp

	world.queue_command(AttackCommand.new(1, [u.id] as Array[int], house.id))
	# TWO TICKS, and the second one is `CombatSystem.halt()` taking away the route the
	# order came with. `SiegeSystem` reads a held route as "trying to be somewhere
	# else", which is right, so an engine deploys the tick after it stops rather than
	# the tick it is ordered.
	world.step()
	world.step()
	assert_false(u.packed, "in range and standing still, so it starts setting up")
	assert_true(u.pack_ticks_left > 0)

	for _i in range(_def(u).pack_ticks - 2):
		world.step()
	assert_eq(house.hp, full, "and lands nothing while its crew are still working")

	assert_true(_step_until(func(): return house.hp < full) > 0, "then it fires")


func test_an_engine_walks_into_range_packed_and_only_then_deploys() -> void:
	# The case that would be easiest to get wrong: deploying where the order was GIVEN
	# rather than where the target is would leave a trebuchet set up at home, out of
	# range of everything, having abandoned its route to do it.
	var u := _engine(TREBUCHET)
	var house := _target(_away)
	world.queue_command(AttackCommand.new(1, [u.id] as Array[int], house.id))

	world.step()
	assert_true(u.packed, "it has a long way to go and stays folded for it")

	assert_true(_step_until(func(): return not u.packed, 1200) > 0, "it deploys eventually")
	var gap := CombatSystem.tile_gap(u.tile(), house.footprint_rect())
	assert_true(gap <= _def(u).attack_range,
			"and it does so IN RANGE (gap %d, range %d)" % [gap, _def(u).attack_range])
	assert_true(_step_until(func(): return house.hp < house.max_hp, 1200) > 0,
			"then the shooting starts")


func test_being_told_to_leave_takes_a_deployed_engine_out_of_the_fight() -> void:
	# The tactical cost, stated as a test: a trebuchet shifted two tiles pays its pack
	# AND its unpack, and 80 ticks each way makes that sixteen seconds rather than a
	# formality. This is the number that stops it being a mobile turret.
	var u := _engine(TREBUCHET)
	var house := _target(_home + Vector2i(4, -1))
	world.queue_command(AttackCommand.new(1, [u.id] as Array[int], house.id))
	assert_true(_step_until(func(): return house.hp < house.max_hp, 1200) > 0,
			"it is in the fight")

	world.queue_command(MoveCommand.new(1, [u.id] as Array[int], _home + Vector2i(0, 2)))
	world.step()
	assert_true(u.packed, "and out of it again on the tick the order lands")
	assert_false(u.can_fire())
	var after := house.hp
	for _i in range(_def(u).pack_ticks):
		world.step()
	assert_eq(house.hp, after, "nothing lands while it is stowing")


# ── what the rest of the game sees ──────────────────────────────────────────

func test_the_packed_state_is_in_the_state_hash() -> void:
	# Two hosts disagreeing have an engine that shoots on one and not on the other, and
	# the engine that shoots is the only thing on the board that out-ranges a castle.
	# `pos` cannot report it: packed and deployed stand on the same tile.
	var u := _engine()
	var before := world.state_hash()
	u.packed = false
	assert_ne(world.state_hash(), before, "which state it is in")

	before = world.state_hash()
	u.pack_ticks_left = 12
	assert_ne(world.state_hash(), before, "and how long until it counts")


func test_the_wire_carries_which_art_to_draw_and_only_when_it_must() -> void:
	# Sent only when true, exactly as `herded_by` is sent only when non-zero: the client
	# reads `get("packed", false)` and absence is a correct reading of the default. One
	# more always-false field on every unit is what 12.1f spent the snapshot audit
	# removing.
	var u := _engine()
	assert_true(bool(u.to_snapshot().get("packed", false)), "a packed engine says so")

	u.packed = false
	assert_false(u.to_snapshot().has("packed"), "a deployed one says nothing")

	var villager := world.spawn_unit(&"unit.villager", 1, _home + Vector2i(2, 2))
	assert_false(villager.to_snapshot().has("packed"),
			"and neither does anything that cannot pack")


func test_the_packed_actor_resolves_to_its_own_art() -> void:
	# The whole point of the sim-side flag: `GameView` reads it off the snapshot and
	# asks the seam, which is the allowed direction across PLAN.md 4's boundary.
	for id in [BALLISTA, &"unit.onager", TREBUCHET] as Array[StringName]:
		var deployed := GameDataRegistry.visual_for(id, -1, -1, false)
		var packed := GameDataRegistry.visual_for(id, -1, -1, true)
		assert_ne(packed, deployed, "%s draws differently packed" % id)
		assert_true(String(packed).ends_with("_packed"), "%s -> %s" % [id, packed])

	# And it is free for everything else, which is what keeps the argument optional.
	assert_eq(GameDataRegistry.visual_for(&"unit.villager", -1, -1, true),
			GameDataRegistry.visual_for(&"unit.villager"),
			"a villager has no folded-up form and asking for one changes nothing")


func test_every_engine_that_packs_declares_a_usable_second_state() -> void:
	# Data check rather than behaviour: a packed speed of 0 would be an engine that
	# folds up and then still cannot move, and no test of the machine would catch it
	# because the machine would be working perfectly.
	var packing := 0
	for id in GameDataRegistry.unit_ids():
		var d := GameDataRegistry.unit(id)
		if not d.packs():
			continue
		packing += 1
		assert_true(d.packed_speed > 0, "%s can travel packed" % id)
		assert_true(d.pack_ticks > 0, "%s pays something to change state" % id)
		assert_eq(d.speed, 0, "%s does not move deployed" % id)
	assert_eq(packing, 3, "ballista, onager and trebuchet, and nothing else")
