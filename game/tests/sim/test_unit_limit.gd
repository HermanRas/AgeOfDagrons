## PLAN.md 13: how many dragons may exist, and **the answer depends on the match mode**
## (project owner, 2026-09-04).
##
## The rule is not a balance number. The dragon has no playercolour mask and cannot be given
## one, so two on screen are indistinguishable — and `colours.json` says player colour is the
## only thing marking ownership in v1. `UnitLimitSystem`'s header carries the measurement.
##
## ⚠️ **THE INTERESTING HALF IS THE SCOPE, NOT THE COUNT.** "One" is easy to assert; *one
## whose* is where the rule lives, and it differs per mode:
##
##   - conquest (`LAST_MAN_STANDING`, `KING_OF_THE_HILL`) — one per MAP, whoever gets it first
##   - `TROPHY` — one per PLAYER
##   - `SCENARIO` — uncapped, so a mission can place a mother and a baby at once
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = _world(MatchConfig.Mode.LAST_MAN_STANDING)


## A world in a given mode, with two players and a castle each so both can order a dragon.
func _world(mode: MatchConfig.Mode) -> SimWorld:
	var world := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.mode = mode
	world.setup(cfg)
	return world


## The dragon is age 4 and costs 500 food + 800 gold, so a test that did not arrange both
## would be testing the age gate and the treasury rather than the limit.
func _make_ready(world: SimWorld, player_id: int, at: Vector2i) -> SimBuilding:
	var p := world.player_for(player_id)
	p.age = 4
	var ud: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	for kind in ud.cost:
		p.stock[kind] = int(ud.cost[kind]) * 4        # enough for several orders
	# Population: the dragon is pop 10, so a town centre's 10 is exactly one and no more.
	# Two of them, so the CAP is never what refuses the second dragon in these tests.
	world.spawn_building(&"building.town_center", player_id, at + Vector2i(0, 20),
			SimBuilding.Phase.COMPLETE, true)
	world.spawn_building(&"building.town_center", player_id, at + Vector2i(0, 35),
			SimBuilding.Phase.COMPLETE, true)
	world.spawn_building(&"building.house", player_id, at + Vector2i(10, 20),
			SimBuilding.Phase.COMPLETE, true)
	world.spawn_building(&"building.house", player_id, at + Vector2i(10, 30),
			SimBuilding.Phase.COMPLETE, true)
	var castle := world.spawn_building(&"building.castle", player_id, at,
			SimBuilding.Phase.COMPLETE, true)
	world.step()                                       # so PopulationSystem has run
	return castle


func _order(world: SimWorld, player_id: int, castle: SimBuilding) -> bool:
	var cmd := TrainCommand.new(player_id, castle.id, &"unit.dragon")
	if not cmd.validate(world):
		return false
	cmd.apply(world)
	return true


# ── the data ────────────────────────────────────────────────────────────────

## The whole rule hangs off one number in `units.json`, and every other unit must be
## untouched by it -- a limit that leaked onto the villager would be catastrophic and silent.
func test_the_dragon_is_the_only_limited_unit() -> void:
	var limited: Array[StringName] = []
	for id in GameDataRegistry.unit_ids():
		if (GameDataRegistry.unit(id) as UnitDef).is_limited():
			limited.append(id)
	assert_eq(limited, [&"unit.dragon"] as Array[StringName])
	assert_eq((GameDataRegistry.unit(&"unit.dragon") as UnitDef).limit, 1)


## `speed: 0` was the unrigged mesh, not balance. It is rigged now and 220 is the owner's
## call -- and a dragon back at 0 would be a unit that cannot move with a walk clip that says
## it can, which is the state this phase existed to leave.
func test_the_dragon_can_move_and_uses_the_rigged_visual() -> void:
	var ud: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_eq(ud.speed, 220)
	assert_eq(ud.visual, &"vis.dragon_rigged")
	assert_eq(ud.domain, &"air")


# ── the scope, per mode ─────────────────────────────────────────────────────

func test_conquest_modes_allow_one_dragon_on_the_whole_map() -> void:
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.KING_OF_THE_HILL]:
		assert_eq(int(UnitLimitSystem.scope_for(mode)), int(UnitLimitSystem.Scope.MAP),
				"%s counts across the map" % MatchConfig.mode_name(mode))


func test_trophy_allows_one_dragon_each() -> void:
	assert_eq(int(UnitLimitSystem.scope_for(MatchConfig.Mode.TROPHY)),
			int(UnitLimitSystem.Scope.PLAYER))


## A scenario places what the mission needs. 15.x's "find a dragon and tame it" wants a gaia
## mother AND a baby alive at once, which a map-wide cap of one would make unauthorable.
func test_a_scenario_is_not_capped_at_all() -> void:
	assert_eq(int(UnitLimitSystem.scope_for(MatchConfig.Mode.SCENARIO)),
			int(UnitLimitSystem.Scope.NONE))


# ── enforcement, through the real command ──────────────────────────────────

## ⚠️ **THE ONE THAT MATTERS IN CONQUEST: P2 IS REFUSED BECAUSE P1 HAS ONE.** This is the only
## limit in the game that one player's action can exhaust for somebody else, so it is asserted
## through `TrainCommand` rather than against the counter -- the command is the trust boundary
## (PLAN.md §4) and the menu hiding a button is not enforcement.
func test_in_conquest_one_players_dragon_denies_the_other() -> void:
	var mine := _make_ready(w, 1, Vector2i(10, 10))
	var theirs := _make_ready(w, 2, Vector2i(60, 60))

	assert_true(_order(w, 1, mine), "the first dragon is allowed")
	assert_false(_order(w, 2, theirs),
			"player 2 must be refused: there is already a dragon on this map")
	assert_false(_order(w, 1, mine), "and so is player 1's second")


func test_in_trophy_both_players_get_one_and_neither_gets_two() -> void:
	var world := _world(MatchConfig.Mode.TROPHY)
	var mine := _make_ready(world, 1, Vector2i(10, 10))
	var theirs := _make_ready(world, 2, Vector2i(60, 60))

	assert_true(_order(world, 1, mine))
	assert_true(_order(world, 2, theirs), "Trophy is one EACH, not one between them")
	assert_false(_order(world, 1, mine))
	assert_false(_order(world, 2, theirs))


func test_in_a_scenario_nothing_is_refused() -> void:
	var world := _world(MatchConfig.Mode.SCENARIO)
	var mine := _make_ready(world, 1, Vector2i(10, 10))
	assert_true(_order(world, 1, mine))
	assert_true(_order(world, 1, mine), "a scenario author is not capped")


# ── the ways a cap gets beaten ──────────────────────────────────────────────

## ⚠️ **A QUEUED DRAGON COUNTS, AND WITHOUT THIS THE LIMIT IS ONE LINE OF CODE AWAY FROM
## USELESS.** Exactly `PopulationSystem.queued_pop`'s reasoning: two castles, two orders in the
## same tick, and `ProductionSystem` spawns both -- the count of what is STANDING is 0 at the
## moment both are validated.
func test_a_dragon_on_order_counts_before_it_has_hatched() -> void:
	var first := _make_ready(w, 1, Vector2i(10, 10))
	var second := w.spawn_building(&"building.castle", 1, Vector2i(30, 10),
			SimBuilding.Phase.COMPLETE, true)
	w.step()

	assert_true(_order(w, 1, first))
	assert_eq(UnitLimitSystem.alive(w, &"unit.dragon", -1), 0, "nothing has spawned yet")
	assert_eq(UnitLimitSystem.queued(w, &"unit.dragon", -1), 1, "but one is on order")
	assert_false(_order(w, 1, second),
			"a second castle must not be able to order the dragon the first is already making")


## A dead dragon frees the slot. The limit is about what is in the world, not about how many
## have ever existed -- the alternative is a player who loses their dragon and can never have
## another, which is a mode nobody asked for.
func test_a_dead_dragon_frees_the_slot() -> void:
	var castle := _make_ready(w, 1, Vector2i(10, 10))
	assert_true(_order(w, 1, castle))
	# Let it out of the queue and into the world.
	for _i in range(2100):
		w.step()
		if UnitLimitSystem.alive(w, &"unit.dragon", -1) > 0:
			break
	assert_eq(UnitLimitSystem.alive(w, &"unit.dragon", -1), 1, "the dragon has to hatch")
	assert_false(_order(w, 1, castle), "and while it lives, no second")

	for e in w.entities.values():
		if e is SimUnit and (e as SimUnit).def_id == &"unit.dragon":
			(e as SimUnit).alive = false
	assert_eq(UnitLimitSystem.alive(w, &"unit.dragon", -1), 0)
	assert_true(_order(w, 1, castle), "a lost dragon can be replaced")


## Gaia counts under `Scope.MAP`, because "one dragon per map" has to mean one. A wild dragon
## placed on a conquest map is the dragon of that map, and nobody trains a second.
func test_a_wild_dragon_uses_up_the_maps_only_slot() -> void:
	var castle := _make_ready(w, 1, Vector2i(10, 10))
	w.spawn_unit(&"unit.dragon", 0, Vector2i(80, 80))
	assert_eq(UnitLimitSystem.alive(w, &"unit.dragon", -1), 1, "gaia's counts")
	assert_false(_order(w, 1, castle),
			"the map already has its dragon, even though nobody owns it")


## And the limit is the ONLY thing being tested here -- an unlimited unit at the same castle
## must still queue freely, or this suite would pass just as well against a broken castle.
func test_an_unlimited_unit_at_the_same_castle_is_unaffected() -> void:
	var castle := _make_ready(w, 1, Vector2i(10, 10))
	var bd: BuildingDef = GameDataRegistry.building(&"building.castle")
	var other := &""
	for id in bd.trains:
		if id != &"unit.dragon" and not (GameDataRegistry.unit(id) as UnitDef).is_limited():
			other = id
			break
	assert_true(other != &"", "the castle has to train something else for this to mean anything")

	var p := w.player_for(1)
	for kind in (GameDataRegistry.unit(other) as UnitDef).cost:
		p.stock[kind] = 9999
	for i in range(3):
		var cmd := TrainCommand.new(1, castle.id, other)
		assert_true(cmd.validate(w), "%s order %d must be allowed" % [other, i + 1])
		cmd.apply(w)
