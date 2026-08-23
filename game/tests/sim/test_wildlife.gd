## Phase 4.13's hostile wolf: the one thing in the game that picks a fight nobody
## ordered, and the one thing that turns from a unit into a resource when it dies.
##
## `Diplomacy` is exercised here rather than in a file of its own, because "owner 0 is
## sometimes a target" only means anything against a world with a wolf in it.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


## A wolf and a villager, `gap` tiles apart on the x axis, with nothing else nearby.
## Returns [wolf, villager].
func _pair(gap: int) -> Array:
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(40 + gap, 40))
	return [wolf, villager]


## Run the world far enough for WildlifeSystem to think at least once -- it scans
## every THINK_INTERVAL_TICKS rather than every tick.
func _run(ticks: int) -> void:
	for i in range(ticks):
		w.step()


# ── Diplomacy: gaia is not one thing ───────────────────────────────────────

func test_a_tree_is_not_a_target_but_a_wolf_is() -> void:
	# The whole reason this predicate exists. Both are owner 0; only one may be shot,
	# and before the wolf every call site read "owner 0" and meant "scenery".
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(10, 10), 0)
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(12, 12))
	assert_false(Diplomacy.is_enemy(tree, 1), "a swordsman may not be sent at an oak")
	assert_true(Diplomacy.is_enemy(wolf, 1), "but may be sent at a wolf")


func test_a_wolf_is_not_its_own_enemy() -> void:
	# Asked from the pack's side: owner 0 looking at owner 0. Nothing says "wolves are
	# friendly to wolves" anywhere -- it falls out of the owner clause.
	var a := w.spawn_unit(&"unit.wolf", 0, Vector2i(10, 10))
	assert_false(Diplomacy.is_enemy(a, 0))


func test_the_dead_and_the_typeless_are_never_enemies() -> void:
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(10, 10))
	wolf.take_damage(9999, 0)
	assert_false(Diplomacy.is_enemy(wolf, 1), "a carcass is not a fight")
	assert_false(Diplomacy.is_enemy(null, 1), "and null is not a crash")


func test_the_view_and_the_sim_answer_the_same_question() -> void:
	# These two used to be unrelated lines in unrelated layers. When they drift, the
	# tap offers an attack the sim then refuses and the game does nothing, silently.
	for owner_id in [0, 1, 2]:
		for is_unit in [true, false]:
			var f := {"owner_id": owner_id, "is_unit": is_unit, "alive": true}
			var expected: bool = (owner_id != 1) and (owner_id != 0 or is_unit)
			assert_eq(Diplomacy.is_enemy_fact(f, 1), expected,
					"owner %s, unit %s" % [owner_id, is_unit])


# ── the wolf decides for itself ────────────────────────────────────────────

func test_a_wolf_attacks_a_villager_that_walks_into_its_range() -> void:
	# NOBODY ORDERED THIS, which is what makes it new. CombatSystem's header rules
	# auto-acquire out for player units on purpose; the wolf is the exception the
	# rule was never about.
	var pair := _pair(3)
	var wolf: SimUnit = pair[0]
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task, SimUnit.Task.ATTACK, "it picked a fight on its own")
	assert_eq(wolf.task_target_id, (pair[1] as SimUnit).id)


func test_a_wolf_ignores_a_villager_beyond_its_aggro_radius() -> void:
	# Otherwise it is not a hazard you can walk around, it is a hazard that owns the
	# map. aggro_radius is the entire aggression of the thing.
	var pair := _pair(20)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq((pair[0] as SimUnit).task, SimUnit.Task.IDLE)


func test_a_villager_in_range_actually_loses_health() -> void:
	var pair := _pair(1)
	var villager: SimUnit = pair[1]
	var before := villager.hp
	_run(60)
	assert_true(villager.hp < before,
			"bitten: %s -> %s" % [before, villager.hp])


func test_a_wolf_does_not_eat_another_wolf() -> void:
	var a := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var b := w.spawn_unit(&"unit.wolf", 0, Vector2i(41, 40))
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(a.task, SimUnit.Task.IDLE, "no target")
	assert_eq(b.task, SimUnit.Task.IDLE)


func test_a_wolf_does_not_gnaw_buildings() -> void:
	# `Diplomacy` would allow it -- a town centre is a legal target for anybody. The
	# filter is WildlifeSystem's, because a wolf parked on a granary for four hundred
	# bites is not wildlife, it is a siege engine.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	w.spawn_building(&"building.house", 1, Vector2i(41, 40))
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task, SimUnit.Task.IDLE)


func test_a_wolf_keeps_the_target_it_has_rather_than_re_choosing() -> void:
	# It re-scans every 5 ticks. Without this it would oscillate between two equally
	# near villagers and reach neither.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var first := w.spawn_unit(&"unit.villager", 1, Vector2i(43, 40))
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task_target_id, first.id)

	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))     # nearer, and too late
	_run(WildlifeSystem.THINK_INTERVAL_TICKS * 2)
	assert_eq(wolf.task_target_id, first.id, "still on the one it chose")


# ── the player may hunt it back ────────────────────────────────────────────

func test_a_player_may_order_an_attack_on_a_wolf() -> void:
	# The half of Diplomacy that makes the wolf huntable rather than merely dangerous.
	# AttackCommand refused every owner-0 target before today.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var soldier := w.spawn_unit(&"unit.militia", 1, Vector2i(42, 40))
	var cmd := AttackCommand.new(1, [soldier.id] as Array[int], wolf.id)
	assert_true(cmd.validate(w))


func test_a_player_still_may_not_order_an_attack_on_a_tree() -> void:
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(40, 40), 0)
	var soldier := w.spawn_unit(&"unit.militia", 1, Vector2i(42, 40))
	var cmd := AttackCommand.new(1, [soldier.id] as Array[int], tree.id)
	assert_false(cmd.validate(w), "an oak is not a belligerent")


# ── death turns it into food ───────────────────────────────────────────────

func test_killing_a_wolf_leaves_a_gatherable_carcass_on_its_tile() -> void:
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var tile := wolf.tile()
	wolf.take_damage(9999, 0)
	_run(1)

	assert_null(w.get_entity(wolf.id), "the unit is gone the tick it dies")
	var carcass: SimResourceNode = null
	for e in w.entities.values():
		if e is SimResourceNode and (e as SimResourceNode).def_id == &"res.wolf_carcass":
			carcass = e
	assert_not_null(carcass, "and a carcass took its place")
	assert_eq(carcass.tile(), tile, "on the tile it fell on")
	assert_eq(carcass.kind, &"food")
	assert_eq(carcass.amount, 30, "the roster's figure for a wolf")
	assert_true(GatherSystem.is_harvestable(carcass, 1), "and a villager may work it")


func test_a_wolf_leaves_no_corpse_to_wait_out() -> void:
	# A villager's body takes 70 seconds to clear (4.7). The wolf's body IS the
	# reward, so making the hunter stand over it for a minute would read as a bug.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	wolf.take_damage(9999, 0)
	_run(1)
	for e in w.entities.values():
		assert_false(e is SimUnit and (e as SimUnit).def_id == &"unit.wolf",
				"no wolf corpse lingers")


func test_only_one_carcass_is_dropped_however_long_the_world_runs() -> void:
	# The sentinel guard. `corpse_ticks_left` is reused as "already handled" here,
	# and without it every tick between death and despawn would queue another node.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	wolf.take_damage(9999, 0)
	_run(30)
	var count := 0
	for e in w.entities.values():
		if e is SimResourceNode and (e as SimResourceNode).def_id == &"res.wolf_carcass":
			count += 1
	assert_eq(count, 1)


func test_a_villager_killed_by_a_wolf_still_leaves_an_ordinary_corpse() -> void:
	# The carcass path is keyed off `is_wildlife`, not off "died". Everything else
	# dies the way it always did.
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(40, 40))
	villager.take_damage(9999, 0)
	_run(1)
	assert_not_null(w.get_entity(villager.id), "still there as a corpse")
	assert_eq(villager.anim, &"die")
	assert_true(villager.corpse_ticks_left > 0, "counting down, not despawned")
