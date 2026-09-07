## Phase 4.10: special abilities and their cooldowns -- the monk's heal, the dragon's fire.
##
## The two abilities are the two SHAPES the system supports, and the tests are organised
## that way rather than by unit: a targeted effect that repeats until it is done, and a
## ground effect that fires once over an area. Four things carry the weight:
##
##   - **The order-then-arrive split.** `Task.ABILITY` is a travel task, so a monk told to
##     heal somebody across the square walks there. `is_travel_task()` omitting it is the
##     exact failure `set_task_garrison` hit in 4.8 -- `PathService` throws the route away
##     and the unit stands in that task forever -- so it is pinned directly.
##   - **The aim is not the destination.** `set_path` rewrites `task_target_tile` to
##     wherever the route could actually end. A breath weapon reading that instead of
##     `ability_target_tile` lands on the dragon's own feet.
##   - **No friendly fire, and no burning the livestock.** The blast reuses the caster's
##     own war predicate, which is the fix 4.9 shipped without.
##   - **Determinism.** One blast damages many things at once, and a kill despawns -- so
##     the targets are collected and sorted before anything is hurt.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	w.map.fill_terrain(SimMap.Terrain.GRASS)


func _run_until(pred: Callable, max_ticks: int) -> int:
	for i in range(max_ticks):
		w.step()
		if pred.call():
			return i + 1
	return -1


func _monk(at: Vector2i = Vector2i(20, 20), owner: int = 1) -> SimUnit:
	return w.spawn_unit(&"unit.monk", owner, at)


func _dragon(at: Vector2i = Vector2i(20, 20), owner: int = 1) -> SimUnit:
	return w.spawn_unit(&"unit.dragon", owner, at)


## A militia knocked down to `hp`, so there is something for a heal to do.
func _wounded(at: Vector2i, hp: int, owner: int = 1) -> SimUnit:
	var u := w.spawn_unit(&"unit.militia", owner, at)
	u.hp = hp
	return u


# ── the data ────────────────────────────────────────────────────────────────

func test_exactly_two_units_in_the_roster_declare_an_ability() -> void:
	# A sweep, so a third arriving is a deliberate act rather than a surprise. Both of
	# these were promised in IDEA.md before they existed (4.6's healing unit, 13.1's
	# fire breath), which is why they and not something else.
	#
	# COLLECTED AS STRINGS, and that is not fussiness: `Array[StringName].sort()` orders
	# by StringName IDENTITY rather than by content, and identity order is not stable
	# between runs -- so sorting the ids as StringNames gives a list that compares equal
	# to a literal only by luck. The build menu re-sorts for the same reason.
	var with_one: Array[String] = []
	for id in GameDataRegistry.unit_ids():
		if GameDataRegistry.unit(id).has_ability():
			with_one.append(String(id))
	with_one.sort()
	assert_eq(with_one, ["unit.dragon", "unit.monk"] as Array[String])


func test_the_monk_had_no_other_verb_at_all_which_is_why_heal_is_its_own() -> void:
	var d: UnitDef = GameDataRegistry.unit(&"unit.monk")
	assert_eq(d.attack_damage, 0)
	assert_true(d.gather_rate.is_empty())
	assert_eq(d.ability_effect, &"heal")
	assert_eq(d.ability_target, &"friendly")


func test_the_dragons_breath_is_the_one_area_effect_in_the_game() -> void:
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_eq(d.ability_effect, &"damage")
	assert_eq(d.ability_target, &"ground")
	assert_true(d.ability_radius > 0, "an area, which nothing else in the sim has")
	assert_true(d.ability_cooldown_ticks > d.attack_cooldown_ticks,
			"or it would simply be a better ordinary attack")


func test_a_unit_with_no_ability_block_has_none_and_that_is_the_switch() -> void:
	assert_false(GameDataRegistry.unit(&"unit.villager").has_ability())
	assert_eq(GameDataRegistry.unit(&"unit.villager").ability_id, &"")


# ── heal: a targeted effect that repeats until it is done ───────────────────

func test_a_monk_walks_to_a_wounded_soldier_and_heals_it() -> void:
	var monk := _monk(Vector2i(20, 20))
	var hurt := _wounded(Vector2i(32, 20), 5)

	w.queue_command(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO))
	var ticks := _run_until(func(): return hurt.hp > 5, 900)
	assert_true(ticks > 0, "it closed the distance and got to work")
	assert_true(monk.tile().distance_squared_to(hurt.tile()) > 0,
			"and it is a WALK, not a heal at range 12")


func test_the_heal_keeps_going_until_the_target_is_full() -> void:
	# One press, not one press per six hp. `_is_finished_with` is what ends it.
	var monk := _monk(Vector2i(20, 20))
	var hurt := _wounded(Vector2i(22, 20), 5)

	w.queue_command(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO))
	var ticks := _run_until(func(): return hurt.hp >= hurt.max_hp, 900)
	assert_true(ticks > 0, "it topped the soldier up")
	# ONE MORE TICK BEFORE ASKING WHETHER IT STOOD DOWN. `_is_finished_with` is checked
	# at the TOP of `_process`, before the heal that fills the bar -- so on the very tick
	# the target reaches full the monk is still on the order, and it retires on the next
	# one. Asserting on the same tick tests the ordering of two lines rather than the
	# behaviour, and it fails.
	w.step()
	assert_eq(monk.task, SimUnit.Task.IDLE, "and then stood down of its own accord")


func test_the_heal_respects_its_cooldown_rather_than_firing_every_tick() -> void:
	var monk := _monk(Vector2i(20, 20))
	var hurt := _wounded(Vector2i(21, 20), 1)
	var d: UnitDef = GameDataRegistry.unit(&"unit.monk")

	w.queue_command(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO))
	# One tick to let the command land and the first heal to fire.
	_run_until(func(): return hurt.hp > 1, 60)
	var after_first := hurt.hp
	# Well inside the cooldown, so nothing more may land.
	for i in range(d.ability_cooldown_ticks - 2):
		w.step()
	assert_eq(hurt.hp, after_first,
			"a cooldown that did nothing would make the monk an instant full heal")


func test_a_heal_cannot_be_aimed_at_an_enemy() -> void:
	var monk := _monk(Vector2i(20, 20))
	var theirs := _wounded(Vector2i(22, 20), 5, 2)
	assert_false(AbilityCommand.new(1, monk.id, theirs.id, Vector2i.ZERO).validate(w),
			"the one effect in the game that would be worth aiming at the other side")


func test_a_heal_cannot_be_aimed_at_a_building() -> void:
	var monk := _monk(Vector2i(20, 20))
	var house := w.spawn_building(&"building.house", 1, Vector2i(24, 20))
	assert_false(AbilityCommand.new(1, monk.id, house.id, Vector2i.ZERO).validate(w),
			"mending a wall is repair (5.3) -- a different verb with a different cost")


func test_a_heal_order_retires_when_its_target_dies_on_the_way() -> void:
	var monk := _monk(Vector2i(20, 20))
	var hurt := _wounded(Vector2i(40, 20), 5)
	w.queue_command(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO))
	w.step()
	assert_eq(monk.task, SimUnit.Task.ABILITY)

	hurt.take_damage(999, 0, SimEntity.NO_ATTACKER)
	w.step()
	assert_eq(monk.task, SimUnit.Task.IDLE,
			"rather than walking to where somebody used to be")


func test_ability_is_a_travel_task_or_the_route_is_thrown_away() -> void:
	# 4.8's `set_task_garrison` bug, pinned so it cannot arrive a third time: a task
	# `PathService` does not recognise has its request dropped, and the unit then stands
	# in that task forever with nothing on screen to explain it.
	var monk := _monk()
	monk.set_task_ability(0, Vector2i(30, 30))
	assert_true(monk.is_travel_task())


# ── fire breath: a ground effect that fires once over an area ───────────────

func test_the_dragon_burns_everything_hostile_in_the_blast() -> void:
	var dragon := _dragon(Vector2i(20, 20))
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	var aim := Vector2i(23, 20)

	var a := w.spawn_unit(&"unit.militia", 2, aim)
	var b := w.spawn_unit(&"unit.militia", 2, aim + Vector2i(d.ability_radius, 0))
	var outside := w.spawn_unit(&"unit.militia", 2, aim + Vector2i(d.ability_radius + 1, 0))
	var hp_before := outside.hp

	w.queue_command(AbilityCommand.new(1, dragon.id, 0, aim))
	_run_until(func(): return not a.alive or a.hp < a.max_hp, 300)

	assert_true(not a.alive or a.hp < a.max_hp, "the one it was aimed at")
	assert_true(not b.alive or b.hp < b.max_hp, "and the one at the edge of the radius")
	assert_eq(outside.hp, hp_before, "and nothing one tile beyond it")


# ── the falloff: 250 at the centre, -50 a ring out (owner, 2026-09-07) ─────────

## The owner's own numbers, pinned as data. *"it needs a aoe o 5x5 with 250 damage to any
## unit or building around the click with -50 damage every ring out"* -- after play-testing
## her in HowToPlay scenario 5 and finding the flat 40 weak.
##
## THE 5x5 WAS ALREADY RIGHT, which is why this asserts `radius` unchanged alongside the two
## new numbers: `radius: 2` has meant `2 * 2 + 1 = 5` tiles across since 4.10, and it is
## what `BlastEffects` is sized from, so the drawn fire still covers exactly the damaged
## ground.
func test_the_breath_is_250_at_the_centre_falling_50_a_ring_over_a_5x5() -> void:
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_eq(d.ability_amount, 250, "what the centre ring takes")
	assert_eq(d.ability_falloff_per_ring, 50, "and each ring out")
	assert_eq(d.ability_radius, 2, "over a 5x5, which did not change")
	assert_eq(d.ability_radius * 2 + 1, 5)
	# THE OUTERMOST RING IS STILL WORTH SOMETHING. 250 - 2 * 50 = 150, so no ring of this
	# ability is ever skipped by `_burn`'s "worth nothing" guard -- which matters, because a
	# silently empty outer ring would still DRAW fire over those tiles.
	assert_true(d.ability_amount - d.ability_radius * d.ability_falloff_per_ring > 0,
			"the edge of the blast still burns")


## ⚠️ **`_burn` IS CALLED DIRECTLY AND NOT THROUGH THE COMMAND, ON PURPOSE.** The targets
## have to hold still: three living dragons given a tick would be re-homed by their own
## stance and the ring each stands in is the whole measurement. This is the same reach-in
## `test_garrison`'s stale-entry guard uses, for the same reason -- the unit under test is
## the blast, not the walk, and the walk already has its own test above.
##
## **THE DIFFERENCES ARE ASSERTED, NOT THE ABSOLUTE HP**, because armour is subtracted after
## the falloff (`_damage_after_armour`) and three identical targets subtract the identical
## amount. So the gaps between them are exactly the falloff, and the test does not have to
## restate the dragon's armour to know what 250 becomes.
func test_each_ring_out_takes_fifty_less() -> void:
	var caster := _dragon(Vector2i(10, 10))
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	var aim := Vector2i(30, 30)

	# 600 hp each, so all three SURVIVE a 250 hit and their losses can be read. A militia
	# would simply die at the centre and there would be nothing left to measure.
	var ring0 := w.spawn_unit(&"unit.dragon", 2, aim)
	var ring1 := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(1, 0))
	var ring2 := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(2, 0))
	var beyond := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(3, 0))

	AbilitySystem.new()._burn(w, caster, d, aim)

	var lost0 := ring0.max_hp - ring0.hp
	var lost1 := ring1.max_hp - ring1.hp
	var lost2 := ring2.max_hp - ring2.hp
	assert_true(lost0 > 0, "the aim tile was hit at all")
	assert_eq(lost0 - lost1, d.ability_falloff_per_ring, "ring 1 takes 50 less than centre")
	assert_eq(lost1 - lost2, d.ability_falloff_per_ring, "and ring 2 takes 50 less again")
	assert_eq(beyond.hp, beyond.max_hp, "and nothing a tile outside the 5x5")


func test_the_centre_of_the_blast_is_worth_six_of_the_old_flat_forty() -> void:
	# The change the owner actually asked for, stated as damage DEALT rather than as a
	# field: 40 flat became 250 at the centre. Read through armour, which is why this is a
	# `>` against the old number rather than an equality -- the point is the magnitude.
	var caster := _dragon(Vector2i(10, 10))
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	var aim := Vector2i(30, 30)
	var victim := w.spawn_unit(&"unit.dragon", 2, aim)

	AbilitySystem.new()._burn(w, caster, d, aim)

	assert_true(victim.max_hp - victim.hp > 200,
			"a hit worth taking a 120 s cooldown for, which the flat 40 was not")


## ⚠️ **A RING WORTH NOTHING IS SKIPPED, NOT FLOORED, and this is the only test that can
## reach that branch** -- the dragon's own numbers never produce one (its outer ring is
## 150). A synthetic def is the fixture, because the guard is about arithmetic rather than
## about the dragon: `_damage_after_armour` enforces `MIN_DAMAGE`, so handing it a 0 would
## deal the floor to something the falloff had just placed out of reach.
func test_a_ring_the_falloff_has_reduced_to_nothing_is_not_hit_at_all() -> void:
	var caster := _dragon(Vector2i(10, 10))
	var steep := UnitDef.from_dict(&"unit.test_steep_blast", {
		"name": "Steep", "visual": "vis.dragon_rigged", "hp": 1, "speed": 0,
		"ability": {
			"id": "steep", "name": "Steep", "effect": "damage", "target": "ground",
			"range": 5, "radius": 3, "amount": 100, "falloff_per_ring": 50,
			"damage_type": "melee", "cooldown_ticks": 10,
		},
	})
	var aim := Vector2i(30, 30)
	var ring1 := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(1, 0))
	var ring2 := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(2, 0))
	var ring3 := w.spawn_unit(&"unit.dragon", 2, aim + Vector2i(3, 0))

	AbilitySystem.new()._burn(w, caster, steep, aim)

	assert_true(ring1.hp < ring1.max_hp, "100 - 50 = 50, which lands")
	assert_eq(ring2.hp, ring2.max_hp, "100 - 100 = 0, which is not a hit for MIN_DAMAGE")
	assert_eq(ring3.hp, ring3.max_hp, "and negative is not a heal either")


func test_the_dragon_cannot_burn_its_own_army() -> void:
	var dragon := _dragon(Vector2i(20, 20))
	var aim := Vector2i(23, 20)
	var friend := w.spawn_unit(&"unit.militia", 1, aim)
	var enemy := w.spawn_unit(&"unit.militia", 2, aim + Vector2i(1, 0))

	w.queue_command(AbilityCommand.new(1, dragon.id, 0, aim))
	_run_until(func(): return not enemy.alive or enemy.hp < enemy.max_hp, 300)
	assert_eq(friend.hp, friend.max_hp,
			"a design choice rather than a physical law, and the reason a breath "
			+ "weapon needs no aiming skill")
	# ✅ **AND THE OWNER CONFIRMED IT 2026-09-07**, asked because the breath went to 250 that
	# day and *"250 damage to any unit or building around the click"* could have meant "my
	# own included". It does not. This test was already here; what changed is that it now
	# pins a decision rather than an assumption -- and at 250 the difference is a stack of
	# your own infantry per press.
	assert_true(GameDataRegistry.unit(&"unit.dragon").ability_amount >= 250,
			"and the stakes that made it worth asking are the amount itself")


func test_the_dragon_cannot_burn_a_flock_of_sheep() -> void:
	# 4.9's bug again, at a third mechanism. `Diplomacy.is_enemy` says a sheep may be
	# attacked; `_is_at_war_with` is the question a weapon that fires unaimed at
	# individuals has to ask.
	var dragon := _dragon(Vector2i(20, 20))
	var aim := Vector2i(23, 20)
	var sheep := w.spawn_unit(&"unit.sheep", 0, aim)
	sheep.herded_by = 1
	var enemy := w.spawn_unit(&"unit.militia", 2, aim + Vector2i(1, 0))

	w.queue_command(AbilityCommand.new(1, dragon.id, 0, aim))
	_run_until(func(): return not enemy.alive or enemy.hp < enemy.max_hp, 300)
	assert_eq(sheep.hp, sheep.max_hp)


func test_a_ground_ability_fires_once_and_stands_down() -> void:
	var dragon := _dragon(Vector2i(20, 20))
	var enemy := w.spawn_unit(&"unit.militia", 2, Vector2i(23, 20))

	w.queue_command(AbilityCommand.new(1, dragon.id, 0, Vector2i(23, 20)))
	_run_until(func(): return dragon.ability_cooldown > 0, 300)
	assert_eq(dragon.task, SimUnit.Task.IDLE,
			"a tile does not get healthier, so there is nothing to re-evaluate -- "
			+ "firing again would be a dragon strafing a patch of grass forever")
	assert_true(not enemy.alive or enemy.hp < enemy.max_hp, "sanity: it did fire")


func test_the_blast_lands_on_the_AIM_and_not_on_where_the_dragon_stopped() -> void:
	# `set_path` rewrites `task_target_tile` to wherever the route could actually end, so
	# a breath weapon reading that field instead of `ability_target_tile` lands on the
	# dragon's own feet. Pinned at the unit rather than through a blocked path, because
	# the field being separate is the fix and the walk is incidental to it.
	var dragon := _dragon(Vector2i(20, 20))
	dragon.set_task_ability(0, Vector2i(26, 20))
	dragon.set_path(PackedVector2Array([Vector2(22, 20)]))
	assert_eq(dragon.task_target_tile, Vector2i(22, 20), "the route ended short")
	assert_eq(dragon.ability_target_tile, Vector2i(26, 20), "the aim did not move")


func test_a_ground_ability_refuses_an_aim_off_the_edge_of_the_map() -> void:
	var dragon := _dragon()
	assert_false(AbilityCommand.new(1, dragon.id, 0, Vector2i(-3, 10)).validate(w),
			"PathService cannot solve a route there, which retires the task and looks "
			+ "from outside exactly like a button that does nothing")


func test_a_ground_ability_refuses_a_named_entity() -> void:
	var dragon := _dragon()
	var enemy := w.spawn_unit(&"unit.militia", 2, Vector2i(23, 20))
	assert_false(AbilityCommand.new(1, dragon.id, enemy.id, Vector2i(23, 20)).validate(w),
			"a client that named one has mixed up which tap it was waiting for")


# ── the cooldown, and the gates around it ───────────────────────────────────

func test_the_cooldown_counts_down_while_the_unit_walks() -> void:
	# The same call `CombatSystem` makes for `attack_cooldown`: closing the distance is
	# not paid on top of the cooldown.
	var monk := _monk(Vector2i(20, 20))
	monk.ability_cooldown = 10
	w.queue_command(MoveCommand.new(1, [monk.id], Vector2i(30, 20)))
	w.step()
	w.step()
	assert_true(monk.ability_cooldown < 10)


func test_a_second_press_inside_the_cooldown_is_refused() -> void:
	var dragon := _dragon()
	dragon.ability_cooldown = 5
	assert_false(AbilityCommand.new(1, dragon.id, 0, Vector2i(23, 20)).validate(w),
			"IDEA.md 4.10's 'greyed out and unclickable' -- and the server refuses it "
			+ "again, because a greyed slot is a courtesy and this is the boundary")


func test_a_unit_with_no_ability_is_refused() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	assert_false(AbilityCommand.new(1, v.id, 0, Vector2i(23, 20)).validate(w))


func test_somebody_elses_monk_is_refused() -> void:
	var monk := _monk(Vector2i(20, 20), 2)
	var hurt := _wounded(Vector2i(21, 20), 5, 2)
	assert_false(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO).validate(w))


func test_a_garrisoned_unit_cannot_use_its_ability() -> void:
	var tower := w.spawn_building(&"building.watch_tower", 1, Vector2i(20, 20))
	var monk := _monk(Vector2i(22, 22))
	assert_true(w.garrison_unit(tower, monk))
	var hurt := _wounded(Vector2i(23, 22), 5)
	assert_false(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO).validate(w),
			"it is off the map -- nothing can find it, and it cannot reach out either")


func test_range_is_deliberately_not_checked_by_the_command() -> void:
	# The unit WALKS there, so a distance test in validate would refuse orders that are
	# perfectly good one step later -- the same reason no other order-then-arrive command
	# checks it.
	var monk := _monk(Vector2i(2, 2))
	var hurt := _wounded(Vector2i(45, 45), 5)
	assert_true(AbilityCommand.new(1, monk.id, hurt.id, Vector2i.ZERO).validate(w))


# ── the wire ────────────────────────────────────────────────────────────────

func test_the_cooldown_is_on_the_wire_only_while_it_is_running() -> void:
	var monk := _monk()
	assert_false(monk.to_snapshot().has("ability_cooldown"),
			"absence is a correct reading of ready, and most units never have one")
	monk.ability_cooldown = 7
	assert_eq(int(monk.to_snapshot()["ability_cooldown"]), 7)


func test_the_wire_form_round_trips() -> void:
	var c := AbilityCommand.new(2, 11, 0, Vector2i(6, 7), 33)
	var back := Command.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_true(back is AbilityCommand)
	assert_eq((back as AbilityCommand).unit_id, 11)
	assert_eq((back as AbilityCommand).target_tile, Vector2i(6, 7))
	assert_eq(back.player_id, 2)
	assert_eq(back.issued_tick, 33)
