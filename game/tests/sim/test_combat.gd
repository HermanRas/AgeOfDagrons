## Phase 4.13: AttackCommand + CombatSystem -- walk to an enemy, stand at reach,
## strike on a cooldown until it dies.
##
## The load-bearing cases are the two that have no equivalent anywhere else in
## the sim: REACH is measured against a footprint rather than a centre (or no
## melee unit can ever touch a building it is standing against), and a kill has
## to hand off cleanly to DeathSystem, which has only ever been driven by a debug
## command until now.
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


# ── the happy path ──────────────────────────────────────────────────────────

func test_a_knight_walks_to_an_enemy_and_kills_it() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(20, 10))

	w.queue_command(AttackCommand.new(1, [knight.id], victim.id))
	var ticks := _run_until(func(): return not victim.alive, 600)

	assert_true(ticks > 0, "it closed the distance and finished the job")
	assert_eq(victim.hp, 0)
	assert_true(knight.is_idle(), "and retires once there is nothing left to hit")


# ── re-acquiring after a kill (project owner, 2026-08-20) ───────────────────

func test_a_killer_takes_the_next_enemy_standing_beside_the_corpse() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var first := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	var second := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))

	w.queue_command(AttackCommand.new(1, [knight.id], first.id))
	assert_true(_run_until(func(): return not first.alive, 600) > 0, "the first one died")

	assert_true(_run_until(func(): return second.hp < second.max_hp, 600) > 0,
			"and it moved on to the one beside it rather than standing over the corpse")


func test_it_prefers_a_unit_over_a_building_within_reach() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var first := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	# The house is CLOSER than the other villager (its 3x3 reaches to gap 1, where
	# the villager is at gap 2), so distance alone would pick it.
	var house := w.spawn_building(&"building.house", 2, Vector2i(9, 11))
	var other := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))

	w.queue_command(AttackCommand.new(1, [knight.id], first.id))
	assert_true(_run_until(func(): return not first.alive, 600) > 0, "the first one died")

	assert_eq(knight.task_target_id, other.id,
			"units come before buildings even when the building is nearer")
	assert_eq(house.hp, house.max_hp, "and the house was left alone")


func test_it_stands_down_when_nothing_is_left_within_the_box() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	# Well outside the 5x5: a re-acquire must not reach across the map.
	var far := w.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))

	w.queue_command(AttackCommand.new(1, [knight.id], victim.id))
	assert_true(_run_until(func(): return not victim.alive, 600) > 0, "the victim died")

	assert_true(knight.is_idle(), "it retired rather than setting off across the map")
	assert_eq(far.hp, far.max_hp)


func test_a_re_acquire_never_turns_on_gaia() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(11, 11))

	w.queue_command(AttackCommand.new(1, [knight.id], victim.id))
	assert_true(_run_until(func(): return not victim.alive, 600) > 0, "the victim died")

	assert_true(knight.is_idle(), "a tree is not an enemy")
	assert_true(tree.alive)


func test_two_worlds_re_acquiring_stay_identical() -> void:
	# The choice must not depend on `entities_in_rect`'s order, which is not sorted.
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	for world: SimWorld in [w, other]:
		var knight: SimUnit = world.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
		var first: SimUnit = world.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
		world.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))
		world.spawn_unit(&"unit.villager", 2, Vector2i(10, 12))
		world.queue_command(AttackCommand.new(1, [knight.id], first.id))

	for i in range(400):
		w.step()
		other.step()
	assert_eq(w.state_hash(), other.state_hash())


func test_an_archer_kills_from_range_without_closing_to_touch() -> void:
	# The whole point of `attack_range`: 4 tiles for the archer (units.json), so
	# it must stop short rather than walking up to the target like a knight.
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 10))

	w.queue_command(AttackCommand.new(1, [archer.id], victim.id))
	var ticks := _run_until(func(): return victim.hp < victim.max_hp, 600)
	assert_true(ticks > 0, "the first arrow landed")

	var gap := CombatSystem.tile_gap(archer.tile(), Rect2i(victim.tile(), Vector2i.ONE))
	assert_true(gap > 1, "it shot from a distance rather than walking into melee (gap %d)" % gap)
	assert_true(gap <= GameDataRegistry.unit(&"unit.archer").attack_range,
			"and from inside its own range")


func test_damage_arrives_on_the_cooldown_rather_than_every_tick() -> void:
	# A hit per tick would kill a villager in three ticks and make every cooldown
	# in units.json decorative.
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	var def := GameDataRegistry.unit(&"unit.knight")

	w.queue_command(AttackCommand.new(1, [knight.id], victim.id))
	_run_until(func(): return victim.hp < victim.max_hp, 20)
	var after_first := victim.hp

	for i in range(def.attack_cooldown_ticks - 1):
		w.step()
	assert_eq(victim.hp, after_first, "no second blow before the cooldown is up")
	w.step()
	assert_true(victim.hp < after_first, "and one the tick it is")


func test_armour_of_the_matching_type_blunts_the_hit() -> void:
	# The archer is `pierce`; the knight carries 2 pierce armour. Asserted
	# against the shipped defs rather than a fixture, so a data change that
	# breaks the arithmetic shows up here.
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(10, 10))
	var knight := w.spawn_unit(&"unit.knight", 2, Vector2i(13, 10))
	var ad := GameDataRegistry.unit(&"unit.archer")
	var kd := GameDataRegistry.unit(&"unit.knight")

	w.queue_command(AttackCommand.new(1, [archer.id], knight.id))
	_run_until(func(): return knight.hp < knight.max_hp, 200)
	assert_eq(knight.max_hp - knight.hp, ad.attack_damage - kd.armor_pierce,
			"damage minus PIERCE armour, not melee armour")


func test_a_hit_never_lands_for_nothing_however_armoured_the_target() -> void:
	# Armour must blunt, never nullify: a health bar that simply never moves
	# gives the player no way to discover their army is useless.
	var attacker := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))
	var vd := GameDataRegistry.unit(&"unit.villager")
	vd.armor_melee = 999          # local to this test's registry instance

	w.queue_command(AttackCommand.new(1, [attacker.id], victim.id))
	var ticks := _run_until(func(): return victim.hp < victim.max_hp, 200)
	vd.armor_melee = 0
	assert_true(ticks > 0, "it still did SOMETHING")


# ── reach is measured against the footprint (the buildings case) ────────────

func test_tile_gap_measures_to_the_footprint_edge_not_the_centre() -> void:
	var rect := Rect2i(Vector2i(10, 10), Vector2i(8, 8))
	assert_eq(CombatSystem.tile_gap(Vector2i(12, 12), rect), 0, "standing inside it")
	assert_eq(CombatSystem.tile_gap(Vector2i(9, 12), rect), 1, "adjacent to its west edge")
	assert_eq(CombatSystem.tile_gap(Vector2i(18, 12), rect), 1, "and to its east edge")
	assert_eq(CombatSystem.tile_gap(Vector2i(22, 12), rect), 5)


func test_a_melee_unit_can_actually_hit_a_building_it_stands_against() -> void:
	# The regression a centre-to-centre range check would cause: a knight at the
	# door of a 10x10 town centre would measure 5 tiles away, be permanently out
	# of reach at range 0, and stand there swinging at nothing.
	var tc := w.spawn_building(&"building.town_center", 2, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 24))

	w.queue_command(AttackCommand.new(1, [knight.id], tc.id))
	var ticks := _run_until(func(): return tc.hp < tc.max_hp, 800)
	assert_true(ticks > 0, "the town centre is taking damage")


func test_a_destroyed_building_retires_its_attackers() -> void:
	var house := w.spawn_building(&"building.house", 2, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	house.hp = 12
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(18, 20))

	w.queue_command(AttackCommand.new(1, [knight.id], house.id))
	var ticks := _run_until(func(): return not house.alive, 400)
	assert_true(ticks > 0, "it came down")
	w.step()
	assert_eq(house.phase, SimBuilding.Phase.DESTROYED, "DeathSystem turned it to rubble")
	assert_true(knight.is_idle(), "and the knight stopped rather than beating the rubble")


# ── death hands off to DeathSystem (4.7), which combat has never driven ─────

func test_a_unit_killed_in_battle_becomes_an_ordinary_corpse() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(11, 10))

	w.queue_command(AttackCommand.new(1, [knight.id], victim.id))
	_run_until(func(): return not victim.alive, 400)
	w.step()
	assert_eq(victim.anim, &"die", "the same corpse path the debug command uses")
	assert_true(victim.corpse_ticks_left > 0, "and it fades on the usual timer")


func test_a_target_that_dies_to_someone_else_releases_its_attackers() -> void:
	var a := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var b := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 12))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(30, 30))

	w.queue_command(AttackCommand.new(1, [a.id, b.id], victim.id))
	w.step()
	assert_eq(a.task, SimUnit.Task.ATTACK)
	assert_eq(b.task, SimUnit.Task.ATTACK)

	w.despawn(victim.id)
	w.step()
	assert_true(a.is_idle(), "no target left to walk to")
	assert_true(b.is_idle())


# ── chasing ─────────────────────────────────────────────────────────────────

func test_an_attacker_re_plans_when_its_quarry_has_moved_on() -> void:
	# The chase re-plans when its route runs OUT rather than every tick (see
	# CombatSystem._close_in for why). What matters is that it converges.
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(5, 5))
	var runner := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 5))

	w.queue_command(AttackCommand.new(1, [knight.id], runner.id))
	w.step()
	# Send the quarry away mid-chase; the knight is faster (340 vs 200), so this
	# is a chase it should win.
	w.queue_command(MoveCommand.new(2, [runner.id], Vector2i(30, 5)))

	var ticks := _run_until(func(): return runner.hp < runner.max_hp, 1200)
	assert_true(ticks > 0, "it caught up with a target that did not wait")


# ── the command's own rules ─────────────────────────────────────────────────

func test_attacking_your_own_side_is_refused() -> void:
	var mine := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var also_mine := w.spawn_unit(&"unit.villager", 1, Vector2i(11, 10))
	assert_false(AttackCommand.new(1, [mine.id], also_mine.id).validate(w),
			"no friendly fire, and no way to express it")


func test_gaia_cannot_be_attacked() -> void:
	# A tree is chopped, not fought. 4.13's hostile wolf is the case that will
	# want this relaxed, and it does not exist yet.
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(12, 10), 0)
	assert_false(AttackCommand.new(1, [knight.id], tree.id).validate(w))


func test_a_selection_that_cannot_fight_at_all_is_refused() -> void:
	var cart := w.spawn_unit(&"unit.trade_cart", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))
	assert_eq(GameDataRegistry.unit(&"unit.trade_cart").attack_damage, 0,
			"the premise: a trade cart has no attack")
	assert_false(AttackCommand.new(1, [cart.id], victim.id).validate(w),
			"better refused than accepted into an order nobody can carry out")


func test_a_mixed_selection_sends_only_the_ones_who_can_fight() -> void:
	var cart := w.spawn_unit(&"unit.trade_cart", 1, Vector2i(10, 10))
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(11, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(20, 10))

	w.queue_command(AttackCommand.new(1, [cart.id, knight.id], victim.id))
	w.step()
	assert_eq(knight.task, SimUnit.Task.ATTACK)
	assert_true(cart.is_idle(), "the cart stayed where it was rather than joining in")


func test_a_dead_target_is_refused() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var corpse := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))
	corpse.alive = false
	assert_false(AttackCommand.new(1, [knight.id], corpse.id).validate(w))


func test_an_attack_from_a_non_owner_is_refused() -> void:
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var victim := w.spawn_unit(&"unit.villager", 2, Vector2i(12, 10))
	assert_false(AttackCommand.new(2, [knight.id], victim.id).validate(w),
			"player 2 cannot order player 1's knight to kill player 2's own villager")


func test_the_wire_format_round_trips() -> void:
	var back := Command.from_dict(AttackCommand.new(1, [4, 7], 9).to_dict()) as AttackCommand
	assert_not_null(back, "attack is registered in Command.from_dict")
	assert_eq(back.player_id, 1)
	assert_eq(back.unit_ids, [4, 7] as Array[int])
	assert_eq(back.target_id, 9)


# ── determinism (7.1) ───────────────────────────────────────────────────────

func test_two_worlds_fighting_the_same_battle_stay_identical() -> void:
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	for world: SimWorld in [w, other]:
		var a: SimUnit = world.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
		var b: SimUnit = world.spawn_unit(&"unit.archer", 1, Vector2i(10, 12))
		var victim: SimUnit = world.spawn_unit(&"unit.spearman", 2, Vector2i(20, 11))
		world.queue_command(AttackCommand.new(1, [a.id, b.id], victim.id))

	for i in range(400):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))


func test_the_attack_cooldown_is_part_of_the_state_hash() -> void:
	# Two clients a tick out of step on a cooldown land their blows on different
	# ticks and disagree about who died first -- `hp` reports that only once it
	# has already happened.
	var knight := w.spawn_unit(&"unit.knight", 1, Vector2i(10, 10))
	var before := w.state_hash()
	knight.attack_cooldown = 7
	assert_ne(w.state_hash(), before)
