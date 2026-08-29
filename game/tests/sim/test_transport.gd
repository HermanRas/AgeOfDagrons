## Carrying land units across water (2.4d, PLAN.md 11.6) -- the thing that makes an
## archipelago a match rather than four peaceful economies.
##
## **THE FEATURE IS A SECOND READER OF GARRISON, NOT A SECOND FEATURE**, and most of
## what is asserted here is that the reuse is honest rather than superficial. 4.8's
## garrison already stored an ENTITY id, already took a unit off the map without
## despawning it, already kept charging population for it and already refused to place
## somebody where there was nowhere legal to stand. A boat needed all five and none of
## them had to be written again.
##
## What is genuinely new is the two rules a building never had to state: a carrier may
## not be cargo, and a landing needs a shore.
extends TestCase

const TRANSPORT := &"unit.transport_ship"
const SOLDIER := &"unit.spearman"

var world: SimWorld

## A stretch of coast painted into the debug map: `_beach` is walkable land and `_sea`
## is the shallow tile beside it, which is where the boat sits. Painted rather than
## found, because the debug map has no water at all -- and painted over ground that was
## checked clear first, which is `test_walls._clear_run`'s lesson.
var _beach: Vector2i
var _sea: Vector2i


func before_each() -> void:
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)
	_make_a_coast()


## Turn a clear 10x10 patch into land on one side and shallow water on the other.
func _make_a_coast() -> void:
	for y in range(4, world.map.size.y - 12):
		for x in range(4, world.map.size.x - 12):
			var origin := Vector2i(x, y)
			if not world.map.can_place_building(
					SimMap.footprint_rect(origin, Vector2i(10, 10))):
				continue
			# A four-tile-wide sea down the right of the patch, so the boat has room to
			# be moored and room to be somewhere with no land beside it at all.
			for wy in range(y, y + 10):
				for wx in range(x + 5, x + 10):
					world.map.set_terrain(Vector2i(wx, wy), SimMap.Terrain.WATER_SHALLOW)
			_beach = Vector2i(x + 4, y + 5)
			_sea = Vector2i(x + 5, y + 5)
			if world.paths != null:
				world.paths.rebuild(world.map)
			return
	assert_true(false, "no clear 10x10 patch on the debug map to make a coast in")


func _boat(at: Vector2i = Vector2i.ZERO) -> SimUnit:
	return world.spawn_unit(TRANSPORT, 1, _sea if at == Vector2i.ZERO else at)


func _soldier(at: Vector2i = Vector2i.ZERO) -> SimUnit:
	return world.spawn_unit(SOLDIER, 1, _beach if at == Vector2i.ZERO else at)


func _step_until(pred: Callable, limit: int = 300) -> int:
	for i in range(limit):
		world.step()
		if pred.call():
			return i + 1
	return -1


func _board(boat: SimUnit, soldiers: Array[int]) -> void:
	var cmd := GarrisonCommand.new(1, soldiers, boat.id)
	assert_true(cmd.validate(world), "the order to board is legal")
	world.queue_command(cmd)


# ── the fixture itself ──────────────────────────────────────────────────────

func test_the_coast_is_a_coast() -> void:
	# Every test below is about land meeting water, so a fixture that quietly painted
	# neither would make all of them pass for the wrong reason.
	assert_true(world.map.is_passable(_beach, SimMap.Domain.LAND), "the beach is walkable")
	assert_false(world.map.is_passable(_sea, SimMap.Domain.LAND), "the sea is not")
	assert_true(world.map.is_passable(_sea, SimMap.Domain.WATER), "and a boat can float on it")
	assert_eq(CombatSystem.tile_gap(_beach, Rect2i(_sea, Vector2i.ONE)), 1,
			"and they are touching")


# ── boarding ────────────────────────────────────────────────────────────────

func test_a_soldier_walks_to_the_shore_and_gets_aboard() -> void:
	var boat := _boat()
	var soldier := _soldier(_beach - Vector2i(3, 0))
	_board(boat, [soldier.id] as Array[int])

	assert_true(_step_until(func(): return soldier.garrisoned_in == boat.id) > 0,
			"it boards")
	assert_eq(boat.garrison.size(), 1, "and the boat knows it")
	assert_eq(StringName(boat.garrison[0]["def_id"]), SOLDIER,
			"recorded by def id, which is what the portrait is cropped from")


func test_a_unit_aboard_is_off_the_map_but_still_costs_population() -> void:
	# The property `garrisoned_in` was built for, restated for a carrier that floats:
	# out of the spatial index so nothing can find it, out of the snapshot so the client
	# releases the sprite, and still in `entities` so hiding six spearmen on a boat does
	# not buy six free ones.
	var boat := _boat()
	var soldier := _soldier()
	var pop_before := _pop_used()
	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)

	assert_eq(world.spatial.query_radius(_beach, 4).find(soldier.id), -1,
			"nothing can find it on the map")
	assert_eq(_pop_used(), pop_before, "and it is still being paid for")
	assert_false(_snapshot_ids().has(soldier.id), "the client is not told about it")
	assert_true(_snapshot_ids().has(boat.id), "though the boat carrying it is sent")


func _pop_used() -> int:
	world.step()
	return world.player_for(1).pop_used


func _snapshot_ids() -> Array:
	var out: Array = []
	for e in SnapshotSystem.build(world, 1).get("updated", []):
		out.append(int(e["id"]))
	return out


func test_a_boat_holds_six_and_refuses_the_seventh() -> void:
	var boat := _boat()
	var ids: Array[int] = []
	for i in range(8):
		ids.append(_soldier(_beach - Vector2i(1 + i % 4, i / 4)).id)
	_board(boat, ids)
	_step_until(func(): return boat.garrison.size() >= 6, 600)

	var cap := world.unit_def(TRANSPORT).garrison_cap
	assert_eq(cap, 6, "the declared capacity")
	assert_eq(boat.garrison.size(), cap, "and it is what fits")
	# The latecomers are stood down where they are rather than queueing, which is
	# `GarrisonSystem`'s rule for a tower that filled up while they walked.
	var aboard := 0
	for id in ids:
		if (world.get_entity(id) as SimUnit).garrisoned_in != 0:
			aboard += 1
	assert_eq(aboard, cap, "the other two are still on the beach")


func test_a_boat_may_not_be_cargo() -> void:
	# Nothing carries ships, so this has to be refused somewhere -- and refusing it in
	# `validate` makes the recursion impossible rather than merely unusual.
	var boat := _boat()
	var ferry := _boat(_sea + Vector2i(1, 0))
	assert_false(GarrisonCommand.new(1, [ferry.id] as Array[int], boat.id).validate(world),
			"a transport cannot be loaded onto a transport")
	assert_false(GarrisonCommand.new(1, [boat.id] as Array[int], boat.id).validate(world),
			"nor onto itself")


func test_a_knight_is_not_a_ferry() -> void:
	# Capacity comes from the data and nothing infers it: every unit but the transport
	# declares 0, which is what keeps the tap and the panel quiet for the whole roster.
	var knight := world.spawn_unit(&"unit.knight", 1, _beach)
	var soldier := _soldier(_beach - Vector2i(1, 0))
	assert_eq(knight.garrison_cap, 0)
	assert_false(knight.has_garrison_room())
	assert_false(GarrisonCommand.new(1, [soldier.id] as Array[int], knight.id).validate(world))


# ── landing ─────────────────────────────────────────────────────────────────

func test_unloading_beside_a_shore_puts_the_soldier_on_land() -> void:
	var boat := _boat()
	var soldier := _soldier()
	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)

	world.queue_command(UngarrisonCommand.new(1, boat.id, UngarrisonCommand.ALL))
	world.step()
	assert_eq(soldier.garrisoned_in, 0, "it is off the boat")
	assert_true(world.map.is_passable(soldier.tile(), SimMap.Domain.LAND),
			"and standing on ground it can stand on, at %s" % soldier.tile())
	assert_true(boat.garrison.is_empty())


func test_unloading_in_open_water_refuses_and_keeps_the_cargo() -> void:
	# THE RULE THAT NOBODY WROTE. `ungarrison_unit` looks for a free tile in the
	# PASSENGER's domain, so there is simply nowhere to put a spearman in mid-ocean and
	# it stays aboard. The same line already handled a tower walled in by its own owner.
	var boat := _boat()
	var soldier := _soldier()
	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)

	# Move the boat out to sea, three tiles from any land.
	var offshore := _sea + Vector2i(3, 0)
	assert_false(world.map.is_passable(offshore + Vector2i(1, 0), SimMap.Domain.LAND),
			"the fixture really is open water")
	boat.pos = SimUnit.centre_of_tile(offshore)
	world.spatial.move(boat.id, offshore)

	world.queue_command(UngarrisonCommand.new(1, boat.id, UngarrisonCommand.ALL))
	world.step()
	assert_eq(soldier.garrisoned_in, boat.id, "still aboard: there is nowhere to land")
	assert_eq(boat.garrison.size(), 1)


func test_a_landing_party_comes_off_where_the_boat_is_moored() -> void:
	# The end-to-end shape of the feature: load on one shore, sail, unload on another.
	var boat := _boat()
	var ids: Array[int] = []
	for i in range(3):
		ids.append(_soldier(_beach - Vector2i(1 + i, 0)).id)
	_board(boat, ids)
	assert_true(_step_until(func(): return boat.garrison.size() == 3, 600) > 0, "all aboard")

	# Sail four tiles along the coast, which is still beside land.
	var along := _sea + Vector2i(0, 3)
	boat.pos = SimUnit.centre_of_tile(along)
	world.spatial.move(boat.id, along)

	world.queue_command(UngarrisonCommand.new(1, boat.id, UngarrisonCommand.ALL))
	world.step()
	assert_true(boat.garrison.is_empty(), "everybody is off")
	for id in ids:
		var u := world.get_entity(id) as SimUnit
		assert_true(CombatSystem.tile_gap(u.tile(), Rect2i(along, Vector2i.ONE)) <= 2,
				"and standing next to the boat, not back where it loaded")


# ── losing the boat ─────────────────────────────────────────────────────────

func test_sinking_a_transport_drowns_what_is_aboard() -> void:
	# The same rule a falling tower follows, and for the same reason: the alternative is
	# six spearmen alive inside a boat that no longer exists, unreachable and
	# un-selectable for the rest of the match.
	var boat := _boat()
	var soldier := _soldier()
	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)

	# Out to sea first, so there is nowhere to put the survivors -- the case that
	# actually drowns them rather than beaching them.
	var offshore := _sea + Vector2i(3, 0)
	boat.pos = SimUnit.centre_of_tile(offshore)
	world.spatial.move(boat.id, offshore)

	boat.take_damage(boat.hp, 0)
	world.step()
	assert_false(soldier.alive, "the passenger went down with it")
	assert_eq(soldier.garrisoned_in, 0, "and is no longer inside anything")


# ── what a boat is not ──────────────────────────────────────────────────────

func test_a_boat_is_not_a_hospital() -> void:
	# Healing is what a BUILDING affords -- a tower is a place to shelter and recover,
	# which is what makes retreating into one a real choice. A ferry that repaired an
	# army would make sailing back and forth the cheapest repair in the game.
	var boat := _boat()
	var soldier := _soldier()
	soldier.hp = 5
	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)

	var hp := soldier.hp
	for _i in range(GarrisonSystem.HEAL_TICKS * 6):
		world.step()
	assert_eq(soldier.hp, hp, "no healing at sea")


func test_the_wire_carries_a_boats_cargo_and_nothing_elses() -> void:
	# In exactly the shape a building sends: a count for the badge and def ids for the
	# portraits, never entity ids -- `UngarrisonCommand` names a SLOT because a
	# garrisoned unit is not in the snapshot for a client to look one up.
	var boat := _boat()
	var soldier := _soldier()
	var d := boat.to_snapshot()
	assert_true(d.has("garrison_count"), "a carrier reports how full it is")
	assert_eq(int(d["garrison_count"]), 0)
	assert_false(soldier.to_snapshot().has("garrison_count"),
			"and a spearman says nothing, as every non-carrier does")

	_board(boat, [soldier.id] as Array[int])
	assert_true(_step_until(func(): return soldier.garrisoned_in != 0) > 0)
	d = boat.to_snapshot()
	assert_eq(int(d["garrison_count"]), 1)
	assert_eq((d["garrison"] as Array)[0], String(SOLDIER), "def ids, not entity ids")
