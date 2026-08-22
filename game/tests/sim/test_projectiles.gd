## Phase 4.13: arrows, bolts and stones -- entities that fly, are looked at, and do
## nothing else.
##
## THE CENTRAL CLAIM IS A NEGATIVE ONE. A projectile carries no damage: the hit lands
## the instant it is fired, exactly as it did before these existed. Most of what is
## asserted here is therefore that adding a flying sprite changed nothing about combat,
## because the moment one of these can hurt somebody, every ranged number in units.json
## becomes wrong by the flight time.
extends TestCase

var w: SimWorld
var archer: SimUnit
var target: SimUnit


## A world with an archer of player 1's and something of player 2's to shoot at.
##
## ONE FUNCTION, so the twin-world determinism test below builds both copies the same
## way. Doing it inline twice is how the first version diverged on tick 1 -- the second
## world never got player 2 added, and `state_hash` folds in the player list, so it
## was reporting a fixture difference as a desync.
static func _a_shooting_range() -> SimWorld:
	var world := SimWorld.new()
	world.setup(MatchConfig.debug_single_player())
	# `debug_single_player` gives one player; the second is added the way MapGen would,
	# because `AttackCommand` refuses a target that is gaia's or your own.
	if world.player_for(2) == null:
		var p := SimPlayer.new()
		p.id = 2
		p.colour = 1
		world.players.append(p)
	world.spawn_unit(&"unit.archer", 1, Vector2i(10, 10))
	world.spawn_unit(&"unit.militia", 2, Vector2i(13, 10))
	return world


func before_each() -> void:
	w = _a_shooting_range()
	archer = w.get_entity(1) as SimUnit
	target = w.get_entity(2) as SimUnit


func _projectiles() -> Array[SimProjectile]:
	var out: Array[SimProjectile] = []
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		if w.entities[id] is SimProjectile:
			out.append(w.entities[id])
	return out


## Order the shot and step until at least one arrow exists, or give up.
func _loose() -> SimProjectile:
	w.queue_command(AttackCommand.new(1, [archer.id], target.id))
	for i in range(200):
		w.step()
		var flying := _projectiles()
		if not flying.is_empty():
			return flying[0]
	return null


# ── it exists at all ────────────────────────────────────────────────────────

func test_a_ranged_attack_looses_a_projectile() -> void:
	# The whole complaint 4.13's last item was about: ranged combat resolved with no
	# visible cause, and `vis.projectile_arrow` was staged and referenced by nothing.
	var arrow := _loose()
	assert_not_null(arrow, "the archer's shot put something in the air")
	assert_eq(arrow.def_id, &"vis.projectile_arrow", "and it is the archer's own")


func test_the_projectile_is_the_shooter_s_and_not_the_target_s() -> void:
	# So the fog sends it to its owner even where they cannot see the far end of the
	# shot, the same rule every other entity of theirs follows.
	var arrow := _loose()
	assert_eq(arrow.owner_id, archer.owner_id)


func test_a_melee_unit_looses_nothing() -> void:
	# `attack.projectile` is absent for every melee unit, and absence is the switch --
	# there is no rule inferring one from range or damage type.
	var swordsman := w.spawn_unit(&"unit.swordsman", 1, Vector2i(12, 10))
	w.queue_command(AttackCommand.new(1, [swordsman.id], target.id))
	for i in range(200):
		w.step()
	assert_true(_projectiles().is_empty(), "a sword throws nothing")


func test_the_dragon_throws_nothing_despite_being_ranged_and_pierce() -> void:
	# The case that would have been caught by any rule clever enough to infer a
	# projectile from the stats: range 3, type pierce, and it breathes fire. There is
	# no bake for that, and a dragon spitting arrows is worse than one spitting
	# nothing.
	var d: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	assert_true(d.attack_range > 0 and d.attack_type == &"pierce",
			"it really does look ranged in the data")
	assert_eq(d.attack_projectile, &"", "and still throws nothing")


# ── it carries no damage ────────────────────────────────────────────────────

func test_the_damage_lands_on_the_tick_it_is_fired_not_on_arrival() -> void:
	# THE DESIGN, stated as a test. If this ever fails because somebody made the arrow
	# carry the hit, every ranged cooldown in units.json needs re-tuning.
	w.queue_command(AttackCommand.new(1, [archer.id], target.id))
	var hp_before := target.hp
	for i in range(200):
		w.step()
		if target.hp < hp_before:
			# The hit has landed. The arrow must still be in the air.
			assert_false(_projectiles().is_empty(),
					"damage and the arrow appear on the same tick")
			return
	assert_true(false, "the archer never hit anything")


func test_an_arrow_in_flight_cannot_hurt_anybody() -> void:
	# A bystander standing directly under the flight path takes nothing.
	var bystander := w.spawn_unit(&"unit.militia", 2, Vector2i(11, 10))
	var hp := bystander.hp
	_loose()
	for i in range(60):
		w.step()
	assert_eq(bystander.hp, hp, "an arrow passing overhead is scenery")


func test_the_target_dying_mid_flight_leaves_the_arrow_alone() -> void:
	# The arrow is aimed at where the target WAS, captured at spawn. It must not curve
	# to follow a corpse, and it must not crash when the entity it was aimed at has
	# been despawned out from under it.
	var arrow := _loose()
	assert_not_null(arrow)
	var aimed_at := arrow.target_pos
	w.despawn(target.id)
	for i in range(30):
		w.step()
	assert_eq(arrow.target_pos, aimed_at, "still going where it was pointed")


# ── flight ──────────────────────────────────────────────────────────────────

func test_it_starts_at_the_shooter_and_ends_at_the_target() -> void:
	var arrow := _loose()
	assert_eq(arrow.origin_pos, archer.pos, "loosed from the archer")
	# Within a tile: the target may have taken a separation nudge on the tick it was
	# shot, and the arrow captured wherever it actually was.
	assert_true((arrow.target_pos - target.pos).length() < SimWorld.SUBTILE,
			"aimed at the target")


func test_it_despawns_when_it_lands() -> void:
	var arrow := _loose()
	assert_not_null(arrow)
	var id := arrow.id
	var total := arrow.total_ticks
	# It was spawned this tick and has not moved yet -- ProjectileSystem runs BEFORE
	# CombatSystem precisely so that it is still here to be drawn.
	assert_eq(arrow.elapsed_ticks, 0, "not advanced on the tick it was created")

	var gone_after := -1
	for i in range(total + 4):
		w.step()
		if w.get_entity(id) == null:
			gone_after = i + 1
			break
	assert_true(gone_after > 0, "the arrow landed and was despawned")
	assert_eq(gone_after, total, "on the tick its flight was up, not later")


func test_a_longer_shot_is_longer_in_the_air() -> void:
	# Fixed speed rather than fixed duration, so a trebuchet's twelve-tile lob visibly
	# takes longer than an archer's four-tile shot.
	var near := SimProjectile.flight_ticks(Vector2i.ZERO,
			Vector2i(4 * SimWorld.SUBTILE, 0))
	var far := SimProjectile.flight_ticks(Vector2i.ZERO,
			Vector2i(12 * SimWorld.SUBTILE, 0))
	assert_true(far > near, "twelve tiles takes longer than four")


func test_a_point_blank_shot_still_exists_for_a_tick() -> void:
	# Otherwise it spawns and despawns inside one tick and is never drawn at all --
	# which is the state the feature was added to get out of.
	assert_true(SimProjectile.flight_ticks(Vector2i.ZERO, Vector2i.ZERO) >= 1)


func test_it_points_the_way_it_is_going() -> void:
	# The art is baked at five directions mirrored to eight; an arrow that carried no
	# facing would fly east whichever way it was actually loosed.
	var east := w.spawn_projectile(&"vis.projectile_arrow", 1, Vector2i.ZERO,
			Vector2i(5 * SimWorld.SUBTILE, 0))
	var west := w.spawn_projectile(&"vis.projectile_arrow", 1,
			Vector2i(5 * SimWorld.SUBTILE, 0), Vector2i.ZERO)
	assert_ne(east.facing, west.facing, "opposite shots point opposite ways")


func test_a_shot_shorter_than_a_tile_still_points_somewhere_sensible() -> void:
	# `facing_toward` is handed the RAW sub-tile delta. Dividing down to tiles first
	# collapses every sub-tile shot to (0, 0), which is due east whichever way the
	# archer was actually aiming.
	var north := w.spawn_projectile(&"vis.projectile_arrow", 1, Vector2i(1000, 1000),
			Vector2i(1000, 900))
	var south := w.spawn_projectile(&"vis.projectile_arrow", 1, Vector2i(1000, 1000),
			Vector2i(1000, 1100))
	assert_ne(north.facing, south.facing, "a short shot still has a direction")


# ── it stays out of everything else's way ───────────────────────────────────

func test_a_projectile_claims_no_ground() -> void:
	# It is in neither the spatial hash nor the occupancy grid. If it were in the grid,
	# `despawn()` would mark its tile dirty for the pathfinder every time a shot
	# landed -- a full-rate path invalidation driven by archery.
	var here := Vector2i(30, 30)
	w.spawn_projectile(&"vis.projectile_arrow", 1, here * SimWorld.SUBTILE,
			(here + Vector2i(3, 0)) * SimWorld.SUBTILE)
	assert_true(w.map.is_passable(here), "you can walk under an arrow")
	assert_true(w.map.can_place_building(SimMap.footprint_rect(here, Vector2i.ONE)),
			"and build there")


func test_an_arrow_is_not_a_target_for_the_re_acquire() -> void:
	# `CombatSystem._reacquire` looks for the next thing to hit within two tiles. It
	# filters on `is SimUnit or is SimBuilding`, so a friendly arrow overhead is not a
	# candidate -- but the filter is worth pinning, because the failure would be a
	# swordsman standing still swinging at the sky.
	var arrow := w.spawn_projectile(&"vis.projectile_arrow", 2,
			Vector2i(10, 10) * SimWorld.SUBTILE, Vector2i(14, 10) * SimWorld.SUBTILE)
	var swordsman := w.spawn_unit(&"unit.swordsman", 1, Vector2i(10, 11))
	w.queue_command(AttackCommand.new(1, [swordsman.id], target.id))
	for i in range(400):
		w.step()
		assert_ne(swordsman.task_target_id, arrow.id, "never picked the arrow")
		if not target.alive:
			return


func test_it_grants_no_vision() -> void:
	# An arrow is not a scout. `VisionSystem` skips anything that is not a unit or a
	# building, and a projectile flying into the dark must not light it.
	var far := Vector2i(40, 40)
	var p := w.player_for(1)
	w.spawn_projectile(&"vis.projectile_arrow", 1, far * SimWorld.SUBTILE,
			(far + Vector2i(2, 0)) * SimWorld.SUBTILE)
	w.step()
	# `vision` empty means this world has no fog at all (`SimPlayer.vision`), in which
	# case everything is visible and there is nothing here to prove either way -- so
	# that is asserted rather than quietly returned, or the test could pass by never
	# running.
	assert_false(p.vision.is_empty(), "this world does have fog, so the check is real")
	assert_false(VisionSystem.can_see_rect(w, p, Rect2i(far, Vector2i.ONE)),
			"the arrow lit nothing")


# ── the wire ────────────────────────────────────────────────────────────────

func test_a_projectile_is_mobile_so_the_fog_never_remembers_one() -> void:
	# The bug this prevents: before `is_mobile()`, `_entry_for` tested `e is SimUnit`,
	# so a projectile took the STATIC branch and was sent REMEMBERED to anybody who had
	# ever explored the tile it was over. That is a live commentary on where a battle
	# is happening, drawn through the fog.
	var arrow := w.spawn_projectile(&"vis.projectile_arrow", 1, Vector2i.ZERO,
			Vector2i(SimWorld.SUBTILE, 0))
	assert_true(arrow.is_mobile())
	assert_true(w.spawn_unit(&"unit.archer", 1, Vector2i(5, 5)).is_mobile(),
			"as a unit is")
	var wall := w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	assert_false(wall.is_mobile(), "and a building is not")


func test_it_survives_the_snapshot_with_a_facing_and_an_anim() -> void:
	# It rides the UNIT-shaped branch on the view side (`anim` plus `facing`), so a
	# projectile needs no new drawing code at all.
	var arrow := w.spawn_projectile(&"vis.projectile_bolt", 1, Vector2i.ZERO,
			Vector2i(4 * SimWorld.SUBTILE, 0))
	var snap := arrow.to_snapshot()
	assert_eq(StringName(snap["anim"]), &"static")
	assert_eq(int(snap["facing"]), arrow.facing)
	assert_eq(StringName(snap["def_id"]), &"vis.projectile_bolt")


func test_the_def_id_resolves_through_the_seam_to_real_art() -> void:
	# A projectile's def id IS its visual id -- there is no projectile def table -- and
	# `visual_for` resolves an id that is already a declared visual to itself. If that
	# fallthrough breaks, every arrow draws as the magenta placeholder.
	for id in [&"vis.projectile_arrow", &"vis.projectile_bolt", &"vis.projectile_stone"]:
		assert_eq(GameDataRegistry.visual_for(id), id, "%s resolves to itself" % id)
		assert_false(GameDataRegistry.atlas_for(id).is_placeholder,
				"%s has real art staged" % id)


func test_an_id_that_is_neither_a_def_nor_a_visual_still_resolves_to_nothing() -> void:
	# The fallthrough must not mask a typo: it accepts ids that are DECLARED visuals,
	# not any id at all.
	assert_eq(GameDataRegistry.visual_for(&"vis.no_such_thing"), &"")


func test_every_projectile_a_unit_names_is_a_declared_visual() -> void:
	# Derived from the data rather than listed, so adding a ranged unit cannot point at
	# art that does not exist and find out on screen.
	for unit_id in GameDataRegistry.unit_ids():
		var ud: UnitDef = GameDataRegistry.unit(unit_id)
		if ud == null or ud.attack_projectile == &"":
			continue
		assert_eq(GameDataRegistry.visual_for(ud.attack_projectile), ud.attack_projectile,
				"%s throws %s, which is declared" % [unit_id, ud.attack_projectile])
		assert_true(ud.attack_range > 0,
				"%s throws something, so it had better be ranged" % unit_id)


func test_two_worlds_shooting_the_same_shot_stay_identical() -> void:
	# A projectile is in `state_hash()` even though it cannot change the outcome,
	# because it DESPAWNS -- two hosts a tick apart on a flight disagree about
	# `removed[]` on the tick it lands.
	var other := _a_shooting_range()
	w.queue_command(AttackCommand.new(1, [archer.id], target.id))
	other.queue_command(AttackCommand.new(1, [1], 2))
	for i in range(400):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
