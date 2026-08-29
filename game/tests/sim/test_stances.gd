## Phase 4.12: units starting fights nobody ordered, within the limits the player set.
##
## `CombatSystem` refused auto-acquire for four phases and named this as where it would
## come from, so the cases that matter most are the ones pinning that the refusal is now
## a DECISION rather than an omission -- and, just as much, the ones pinning what it still
## refuses. Three things are load-bearing:
##
##   - **A default that is derived, not authored.** No unit in units.json declares a
##     stance; `SimUnit.default_stance_for` reads three existing fields to decide. A
##     silent edit to any of them -- giving a monk an attack, taking a villager's gather
##     rate away -- changes what a whole class of unit does when left alone, and nothing
##     else in the game would report it.
##   - **The leash's ONE number.** `GUARD_RADIUS` is both how far a defender looks and
##     how far it will chase, and the two being one value is what stops a defender from
##     acquiring a target it must immediately abandon, or being walked off its post one
##     tile at a time. Two constants would drift; a test is what says they are one.
##   - **What must NOT acquire.** Every exclusion here was a live failure mode: a
##     villager abandoning an economy, a trebuchet folding and unfolding all match, a
##     tower shooting a herded sheep. The green case is one test; the refusals are most
##     of the file.
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


func _soldier(owner: int, at: Vector2i, stance: int = SimUnit.Stance.DEFENSIVE) -> SimUnit:
	var u := w.spawn_unit(&"unit.militia", owner, at)
	u.stance = stance
	return u


# ── the default, which is derived rather than authored ──────────────────────

func test_a_soldier_is_born_defensive() -> void:
	var u := w.spawn_unit(&"unit.militia", 1, Vector2i(10, 10))
	assert_eq(u.stance, SimUnit.Stance.DEFENSIVE,
			"the project owner's call, 2026-08-29: fight back, chase a little, return")


func test_a_villager_is_born_passive_because_she_has_a_gather_rate() -> void:
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(10, 10))
	assert_eq(v.stance, SimUnit.Stance.PASSIVE)
	# The WHY, pinned separately from the WHAT: the rule reads `is_worker()`, so this
	# stays right if a second worker is ever added and breaks loudly if the villager's
	# gather rate is ever moved somewhere else.
	assert_true(GameDataRegistry.unit(&"unit.villager").is_worker(),
			"and it is the gather rate that decides it, not the unit's name")


func test_a_siege_engine_is_born_passive_because_deploying_is_expensive() -> void:
	var t := w.spawn_unit(&"unit.trebuchet", 1, Vector2i(10, 10))
	assert_eq(t.stance, SimUnit.Stance.PASSIVE,
			"an engine that deployed for every passing scout would spend the match "
			+ "folding and unfolding -- 4.13 prices that at 8 seconds each way")
	assert_true(GameDataRegistry.unit(&"unit.trebuchet").packs())


func test_a_unit_with_no_attack_is_born_passive() -> void:
	var m := w.spawn_unit(&"unit.monk", 1, Vector2i(10, 10))
	assert_eq(m.stance, SimUnit.Stance.PASSIVE)
	assert_eq(GameDataRegistry.unit(&"unit.monk").attack_damage, 0,
			"a stance would send it to stand next to something it cannot hurt")


func test_every_unit_in_the_roster_gets_a_stance_and_it_is_one_of_the_four() -> void:
	# A sweep rather than a list, so a unit added later cannot quietly fall outside the
	# rule. The interesting half is the SECOND assertion: `default_stance_for` returns a
	# plain int, so a typo'd branch would produce a value no stance names and a unit that
	# answers to none of them.
	var seen := {}
	for id in GameDataRegistry.unit_ids():
		var d: UnitDef = GameDataRegistry.unit(id)
		var s := SimUnit.default_stance_for(d)
		assert_true(s >= SimUnit.Stance.AGGRESSIVE and s <= SimUnit.Stance.PASSIVE,
				"%s got a stance outside the enum" % id)
		seen[s] = true
	assert_true(seen.has(SimUnit.Stance.DEFENSIVE),
			"and the roster really does contain fighters, or this file proves nothing")
	assert_true(seen.has(SimUnit.Stance.PASSIVE))


func test_a_null_def_is_passive_rather_than_an_error() -> void:
	# `spawn_unit` has a fallback branch for an unknown def id and this is the stance
	# half of it. Passive is the safe answer: a unit the data does not describe must not
	# go looking for a fight it cannot be balanced for.
	assert_eq(SimUnit.default_stance_for(null), SimUnit.Stance.PASSIVE)


# ── acquiring ───────────────────────────────────────────────────────────────

func test_a_defensive_soldier_attacks_an_enemy_that_walks_within_the_guard_radius() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	var theirs := _soldier(2, Vector2i(20, 20 + StanceSystem.GUARD_RADIUS))

	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK, "nobody ordered this")
	assert_eq(mine.task_target_id, theirs.id)
	assert_eq(mine.guard_post, Vector2i(20, 20),
			"and it remembers where it was standing, which is what it owes a return to")


func test_a_defensive_soldier_ignores_an_enemy_one_tile_beyond_the_radius() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	_soldier(2, Vector2i(20, 20 + StanceSystem.GUARD_RADIUS + 1))

	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE)
	assert_eq(mine.guard_post, SimUnit.NO_POST)


func test_a_passive_soldier_ignores_an_enemy_standing_next_to_it() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.PASSIVE)
	_soldier(2, Vector2i(21, 20))

	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE,
			"which is exactly what every unit in the game did before 4.12")


func test_an_aggressive_soldier_never_reaches_less_far_than_a_defensive_one() -> void:
	# THIS TEST FOUND A REAL BUG ON ITS FIRST RUN and is kept in the shape that found it.
	# It was written as `d.los > GUARD_RADIUS` on the assumption that a fighter's line of
	# sight comfortably exceeds five tiles. `unit.militia` declares `los: 4` -- so an
	# aggressive militia noticed LESS than a defensive one, and the stance a player picks
	# to start more fights started fewer. `_sight_of` now floors AGGRESSIVE at
	# GUARD_RADIUS; what is pinned here is the ORDERING, which is the actual rule.
	var swept := 0
	for id in GameDataRegistry.unit_ids():
		var d: UnitDef = GameDataRegistry.unit(id)
		if d.attack_damage <= 0:
			continue
		var u := SimUnit.new()
		u.stance = SimUnit.Stance.AGGRESSIVE
		var aggressive := StanceSystem._sight_of(u, d)
		u.stance = SimUnit.Stance.DEFENSIVE
		assert_true(aggressive >= StanceSystem._sight_of(u, d),
				"%s: aggressive reaches %d against defensive's %d" \
				% [id, aggressive, StanceSystem.GUARD_RADIUS])
		swept += 1
	assert_true(swept > 5, "sanity: the sweep really did cover the fighters")

	# And the end-to-end half, on a unit whose `los` genuinely does exceed the radius,
	# so the two stances are actually distinguishable in the world.
	var archer_def: UnitDef = GameDataRegistry.unit(&"unit.archer")
	assert_true(archer_def.los > StanceSystem.GUARD_RADIUS, "the archer sees further")
	var mine := w.spawn_unit(&"unit.archer", 1, Vector2i(20, 20))
	mine.stance = SimUnit.Stance.AGGRESSIVE
	var far := _soldier(2, Vector2i(20, 20 + StanceSystem.GUARD_RADIUS + 1),
			SimUnit.Stance.PASSIVE)
	w.step()
	assert_eq(mine.task_target_id, far.id,
			"beyond a defender's radius and inside an aggressive archer's sight")


func test_an_aggressive_soldier_takes_no_guard_post() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.AGGRESSIVE)
	_soldier(2, Vector2i(24, 20))
	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK)
	assert_eq(mine.guard_post, SimUnit.NO_POST,
			"aggressive has no leash -- it is the stance for an army you have decided "
			+ "to spend, and a post would quietly give it one")


func test_the_nearest_of_two_enemies_is_chosen_and_it_does_not_depend_on_spawn_order() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	var far := _soldier(2, Vector2i(23, 20))
	var near := _soldier(2, Vector2i(21, 20))
	assert_true(far.id < near.id, "the far one has the LOWER id, so id order is not distance order")

	w.step()
	assert_eq(mine.task_target_id, near.id,
			"a strict minimum over (is_building, gap, id) -- if this ever returns the "
			+ "far one, two hosts can pick different targets and the match diverges")


func test_a_unit_is_preferred_over_a_building_at_the_same_distance() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	w.spawn_building(&"building.house", 2, Vector2i(22, 20))
	var them := _soldier(2, Vector2i(20, 22))

	w.step()
	assert_eq(mine.task_target_id, them.id,
			"a building cannot run away and will still be there afterwards")


# ── what must not be acquired ───────────────────────────────────────────────

func test_a_grazing_sheep_is_never_attacked_unasked() -> void:
	# 4.9's bug, arriving at a second mechanism. `Diplomacy.is_enemy` says a sheep MAY be
	# attacked, because hunting is how a deer becomes food -- and a stance that used it
	# would have every soldier in the game slaughtering the livestock, including its own
	# player's herd.
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.AGGRESSIVE)
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(21, 20))
	sheep.herded_by = 1

	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE)
	assert_true(Diplomacy.is_enemy(sheep, 1),
			"and the point is that the OTHER predicate still says yes -- this test is "
			+ "worthless if the two ever agree")


func test_a_wolf_is_attacked_unasked_because_it_is_a_predator() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.AGGRESSIVE)
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(22, 20))

	w.step()
	assert_eq(mine.task_target_id, wolf.id,
			"`aggro_radius > 0` is the data already saying which animals pick fights")


func test_gaia_itself_never_acquires_anything() -> void:
	# A wolf's aggression is WildlifeSystem's, through `aggro_radius`, and giving it a
	# stance as well would be two mechanisms answering one question -- the duplication
	# `Diplomacy`'s header is a standing warning about. The guard is `owner_id == 0`.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(20, 20))
	wolf.stance = SimUnit.Stance.AGGRESSIVE
	_soldier(1, Vector2i(21, 20))

	var before := wolf.task
	w.step()
	# WildlifeSystem may well have given it a task of its own; what must be true is that
	# StanceSystem did not, so the post it would have taken is absent.
	assert_eq(wolf.guard_post, SimUnit.NO_POST,
			"a post is StanceSystem's fingerprint, and gaia must not carry one")
	assert_true(before == SimUnit.Task.IDLE, "sanity: it started idle")


func test_a_busy_villager_does_not_down_tools_however_her_stance_is_set() -> void:
	# ONLY AN IDLE UNIT ACQUIRES, and this is the whole safety property: no stance can
	# countermand an order the player gave. It is also why there is no retaliation.
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(24, 20))
	var v := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	v.stance = SimUnit.Stance.AGGRESSIVE
	w.queue_command(GatherCommand.new(1, [v.id], tree.id))
	w.step()
	assert_true(v.task == SimUnit.Task.GATHER or v.task == SimUnit.Task.RETURN)

	_soldier(2, Vector2i(21, 20))
	for i in range(20):
		w.step()
		assert_ne(v.task, SimUnit.Task.ATTACK,
				"she is working; being shot at does not turn her round either (4.13)")


func test_a_packed_engine_does_not_volunteer_even_if_a_player_sets_a_stance_on_it() -> void:
	var t := w.spawn_unit(&"unit.trebuchet", 1, Vector2i(20, 20))
	t.stance = SimUnit.Stance.AGGRESSIVE
	assert_true(t.packed, "a siege engine is trained packed (4.13)")
	_soldier(2, Vector2i(22, 20))

	w.step()
	assert_eq(t.task, SimUnit.Task.IDLE,
			"acquiring would start an 8-second deploy for a target free to keep walking")


func test_a_foundation_is_not_a_reason_to_start_a_border_war() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.AGGRESSIVE)
	w.spawn_building(&"building.house", 2, Vector2i(22, 20), SimBuilding.Phase.FOUNDATION)

	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE,
			"the same exclusion `CombatSystem._process_building` makes, and for its reason")


# ── the leash ───────────────────────────────────────────────────────────────

func test_a_defender_drawn_past_the_leash_breaks_off_and_walks_home() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	var them := _soldier(2, Vector2i(22, 20))
	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK)
	var post := mine.guard_post

	# Teleport the defender well past its leash, which is what a long chase amounts to
	# and is far cheaper to arrange than one.
	w.spatial.remove(mine.id)
	mine.pos = SimUnit.centre_of_tile(Vector2i(20 + StanceSystem.GUARD_RADIUS + 3, 20))
	w.spatial.insert(mine.id, mine.tile())

	w.step()
	assert_eq(mine.task, SimUnit.Task.MOVE, "it gave up on the chase")
	assert_eq(mine.guard_post, post, "and it kept the post, which is what it is walking to")
	assert_eq(mine.task_target_tile, post, "which is where it is walking")
	# NOT asserted: that `task_target_id` was cleared. `set_task_move` has never cleared
	# it -- only `stop()` does -- and nothing reads it while the task is MOVE. Pinning
	# that here would be pinning an unrelated pre-existing detail, which is how a test
	# ends up failing for a change that was correct.
	assert_true(them.alive, "sanity: it broke off rather than winning")


func test_the_walk_home_ends_with_the_post_released() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	mine.guard_post = Vector2i(20, 20)
	# Standing already on the post and idle: the next stance tick should simply let go
	# rather than ordering a walk of zero tiles.
	w.step()
	assert_eq(mine.guard_post, SimUnit.NO_POST)
	assert_eq(mine.task, SimUnit.Task.IDLE)


func test_a_defender_idle_away_from_its_post_walks_back_before_looking_for_a_fight() -> void:
	# The ordering that stops a post ratcheting forward one fight at a time.
	var mine := _soldier(1, Vector2i(30, 20))
	mine.guard_post = Vector2i(20, 20)
	_soldier(2, Vector2i(31, 20))

	w.step()
	assert_eq(mine.task, SimUnit.Task.MOVE, "home first")
	assert_eq(mine.task_target_tile, Vector2i(20, 20))


func test_an_ordered_attack_is_never_recalled_by_a_leash() -> void:
	# `keep_post` is false for every ORDER and true for every CONTINUATION, and this is
	# the case that makes the distinction earn its keep: a soldier sent across the map
	# must not be dragged back by a post it never opted into.
	var mine := _soldier(1, Vector2i(20, 20))
	var them := _soldier(2, Vector2i(40, 20))
	mine.guard_post = Vector2i(20, 20)

	w.queue_command(AttackCommand.new(1, [mine.id], them.id))
	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK)
	assert_eq(mine.task_target_id, them.id)
	assert_eq(mine.guard_post, SimUnit.NO_POST, "the order dropped the post")


func test_a_defender_that_kills_one_raider_and_turns_on_the_next_keeps_its_post() -> void:
	# `_reacquire` passes `keep_post`. Without it, finishing off a pair would silently
	# release the leash and the second fight would be unbounded.
	var mine := _soldier(1, Vector2i(20, 20))
	# BOTH RAIDERS PASSIVE, or this is a 2-against-1 the defender loses -- and a dead
	# defender's `stop()` releases the post, which reads as the leash failing when what
	# actually happened is that the fixture killed the subject.
	var a := _soldier(2, Vector2i(21, 20), SimUnit.Stance.PASSIVE)
	var b := _soldier(2, Vector2i(21, 21), SimUnit.Stance.PASSIVE)
	w.step()
	assert_eq(mine.guard_post, Vector2i(20, 20))

	var first := mine.task_target_id
	assert_true(first == a.id or first == b.id)
	var ticks := _run_until(func(): return mine.task_target_id != first, 900)
	assert_true(ticks > 0, "it killed one and turned on the other")
	assert_true(mine.alive, "sanity: the defender is the one still standing")
	assert_eq(mine.guard_post, Vector2i(20, 20), "and it still owes the same post a return")


func test_stop_releases_the_post() -> void:
	# NO ENEMY IN THE WORLD, and that is the point of the arrangement rather than a
	# convenience. With one standing two tiles away, Stop releases the post and the very
	# same tick's `_settle_or_acquire` takes a new one -- which is CORRECT (a defensive
	# unit told to stop with a raider on top of it re-engages) and makes the release
	# untestable through observation. The post is set by hand instead.
	var mine := _soldier(1, Vector2i(20, 20))
	mine.guard_post = Vector2i(15, 15)

	w.queue_command(StopCommand.new(1, [mine.id]))
	w.step()
	assert_eq(mine.guard_post, SimUnit.NO_POST,
			"stop means stand down HERE; a post would make it a verb that leaves a "
			+ "unit walking, which is the one thing it is for")


func test_stop_with_a_raider_on_top_of_you_re_engages_and_that_is_correct() -> void:
	# The companion to the test above, written because its arrangement looked like a
	# dodge and is not: this is the behaviour, and it is worth pinning rather than
	# leaving as the reason another test is shaped oddly.
	var mine := _soldier(1, Vector2i(20, 20))
	var them := _soldier(2, Vector2i(22, 20), SimUnit.Stance.PASSIVE)
	w.step()
	assert_eq(mine.task_target_id, them.id)

	w.queue_command(StopCommand.new(1, [mine.id]))
	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK, "it stood down and immediately re-engaged")
	assert_eq(mine.guard_post, Vector2i(20, 20), "with a post taken afresh")


# ── stand ground ────────────────────────────────────────────────────────────

func test_stand_ground_acquires_only_what_is_already_in_reach() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.STAND_GROUND)
	var d := GameDataRegistry.unit(&"unit.militia")
	assert_eq(d.attack_range, 0, "militia is melee, so its reach is the floor of 1")

	_soldier(2, Vector2i(23, 20))
	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE, "three tiles away is not in reach")

	var close := _soldier(2, Vector2i(21, 20))
	w.step()
	assert_eq(mine.task_target_id, close.id)


func test_stand_ground_never_asks_for_a_route() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.STAND_GROUND)
	_soldier(2, Vector2i(21, 20))
	w.step()
	assert_eq(mine.task, SimUnit.Task.ATTACK)
	assert_false(mine.path_pending,
			"anything it can acquire is already in reach, so a path request would spend "
			+ "a slot of PathService's budget on a route it is forbidden to walk")
	assert_false(mine.has_waypoint())


func test_stand_ground_stands_down_rather_than_following_a_target_out_of_reach() -> void:
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.STAND_GROUND)
	var them := _soldier(2, Vector2i(21, 20))
	w.step()
	assert_eq(mine.task_target_id, them.id)

	w.spatial.remove(them.id)
	them.pos = SimUnit.centre_of_tile(Vector2i(30, 20))
	w.spatial.insert(them.id, them.tile())

	w.step()
	assert_eq(mine.task, SimUnit.Task.IDLE, "holding the line, which is the whole stance")
	assert_eq(mine.tile(), Vector2i(20, 20), "and it did not take a step")


func test_stand_ground_refuses_an_ORDERED_chase_too() -> void:
	# Deliberate, and worth pinning because it is the surprising half: a player who has
	# set a unit to hold its ground and then orders it across the map has asked for two
	# contradictory things, and the standing instruction wins.
	var mine := _soldier(1, Vector2i(20, 20), SimUnit.Stance.STAND_GROUND)
	var them := _soldier(2, Vector2i(35, 20))

	w.queue_command(AttackCommand.new(1, [mine.id], them.id))
	w.step()
	w.step()
	assert_eq(mine.tile(), Vector2i(20, 20))
	assert_eq(mine.task, SimUnit.Task.IDLE)


# ── the command ─────────────────────────────────────────────────────────────

func test_the_command_sets_every_unit_it_names() -> void:
	var a := _soldier(1, Vector2i(20, 20), SimUnit.Stance.PASSIVE)
	var b := _soldier(1, Vector2i(21, 20), SimUnit.Stance.PASSIVE)
	var c := SetStanceCommand.new(1, [a.id, b.id], SimUnit.Stance.STAND_GROUND)
	assert_true(c.validate(w))
	c.apply(w)
	assert_eq(a.stance, SimUnit.Stance.STAND_GROUND)
	assert_eq(b.stance, SimUnit.Stance.STAND_GROUND)


func test_the_command_refuses_a_stance_that_is_not_one_of_the_four() -> void:
	var a := _soldier(1, Vector2i(20, 20))
	assert_false(SetStanceCommand.new(1, [a.id], 99).validate(w),
			"an out-of-range value would sit on the unit matching none of "
			+ "StanceSystem's arms -- inert, and answering to no stance the panel shows")
	assert_false(SetStanceCommand.new(1, [a.id], -1).validate(w))


func test_the_command_refuses_somebody_elses_unit() -> void:
	var theirs := _soldier(2, Vector2i(20, 20))
	assert_false(SetStanceCommand.new(1, [theirs.id], SimUnit.Stance.PASSIVE).validate(w))


func test_the_command_refuses_a_herded_sheep_where_a_move_order_would_not() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(20, 20))
	sheep.herded_by = 1
	assert_true(MoveCommand.new(1, [sheep.id], Vector2i(22, 22)).validate(w),
			"a move IS accepted for a herded animal (6.5) -- that is the contrast")
	assert_false(SetStanceCommand.new(1, [sheep.id], SimUnit.Stance.AGGRESSIVE).validate(w),
			"but a stance would be giving gaia an army")


func test_setting_a_stance_releases_the_post() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	mine.guard_post = Vector2i(15, 15)
	SetStanceCommand.new(1, [mine.id], SimUnit.Stance.PASSIVE).apply(w)
	assert_eq(mine.guard_post, SimUnit.NO_POST,
			"only StanceSystem releases a post, and it stops looking at a unit whose "
			+ "stance it no longer manages -- so this would leak forever")


func test_setting_a_stance_does_not_interrupt_an_order_in_flight() -> void:
	var mine := _soldier(1, Vector2i(20, 20))
	w.queue_command(MoveCommand.new(1, [mine.id], Vector2i(30, 20)))
	w.step()
	assert_eq(mine.task, SimUnit.Task.MOVE)

	SetStanceCommand.new(1, [mine.id], SimUnit.Stance.AGGRESSIVE).apply(w)
	assert_eq(mine.task, SimUnit.Task.MOVE, "a stance is about what to do NEXT")
	assert_eq(mine.task_target_tile, Vector2i(30, 20))


func test_the_wire_form_round_trips() -> void:
	var c := SetStanceCommand.new(3, [7, 11], SimUnit.Stance.STAND_GROUND, 42)
	var back := Command.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_true(back is SetStanceCommand, "and Command.from_dict knows the type name")
	assert_eq((back as SetStanceCommand).unit_ids, [7, 11])
	assert_eq((back as SetStanceCommand).stance, SimUnit.Stance.STAND_GROUND)
	assert_eq(back.player_id, 3)
	assert_eq(back.issued_tick, 42)


# ── the wire ────────────────────────────────────────────────────────────────

func test_the_stance_rides_on_every_unit_rather_than_only_when_it_is_unusual() -> void:
	# The shape argument (12.1f): a field carried by SOME units and not others splits the
	# roster into two wire shape tables and costs more than it saves. One int on all of
	# them keeps the single shape `task` and `facing` already share.
	var a := w.spawn_unit(&"unit.militia", 1, Vector2i(20, 20))
	var b := w.spawn_unit(&"unit.villager", 1, Vector2i(21, 20))
	assert_ne(a.stance, b.stance, "sanity: these two differ, so absence would be lossy")
	assert_true(a.to_snapshot().has("stance"))
	assert_true(b.to_snapshot().has("stance"))
