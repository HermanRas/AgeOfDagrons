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


## IT IS SEEN ARRIVING BEFORE IT GOES, and that extra tick is a fix rather than a
## tolerance (2026-08-28). This used to assert `gone_after == total`, which meant the
## despawn happened on the very tick `advance()` clamped `pos` to `target_pos` -- so that
## position never reached a snapshot and **every arrow in the game vanished about a tile
## and a half short of what it was fired at**, `SPEED` being 384 of a 256 sub-tile. It
## went unreported for the reason such things do: an arrow is on screen for two ticks, and
## a sprite failing to appear somewhere is much harder to notice than one appearing wrongly.
##
## It is also what `SpentProjectiles` reads. The view learns where a shot ended from the
## last snapshot that carried it, so that snapshot has to be the one where it arrived.
func test_it_is_seen_arriving_and_despawns_the_tick_after() -> void:
	var arrow := _loose()
	assert_not_null(arrow)
	var id := arrow.id
	var total := arrow.total_ticks
	# It was spawned this tick and has not moved yet -- ProjectileSystem runs BEFORE
	# CombatSystem precisely so that it is still here to be drawn.
	assert_eq(arrow.elapsed_ticks, 0, "not advanced on the tick it was created")

	var gone_after := -1
	var seen_at_target := false
	for i in range(total + 4):
		w.step()
		if w.get_entity(id) != null and arrow.pos == arrow.target_pos:
			seen_at_target = true
		if w.get_entity(id) == null:
			gone_after = i + 1
			break
	assert_true(seen_at_target, "it existed, at its target, for one whole tick")
	assert_true(gone_after > 0, "the arrow landed and was despawned")
	assert_eq(gone_after, total + 1, "the tick after it arrived, not the one it arrived on")


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


# ── the tower volley (project owner, 2026-08-28) ────────────────────────────

## A guard tower of player 1's with a raider of player 2's standing in reach, and
## `garrison` archers inside it. Far from the shooting range's own pair so neither
## interferes.
var _raider: SimUnit = null


func _a_manned_tower(def_id: StringName, garrison: int) -> SimBuilding:
	var tower := w.spawn_building(def_id, 1, Vector2i(40, 40),
			SimBuilding.Phase.COMPLETE, true)
	for i in range(garrison):
		var a := w.spawn_unit(&"unit.archer", 1, Vector2i(40 + i, 45))
		tower.garrison.append({"id": a.id, "def_id": a.def_id})
	_raider = w.spawn_unit(&"unit.militia", 2, Vector2i(43, 40))
	return tower


## Step until the tower shoots, and hand back everything that was in the air on the
## tick it did. Collected on the SAME tick: `ProjectileSystem` runs before
## `CombatSystem`, so a volley loosed this tick is untouched until the next one.
func _volley_of(def_id: StringName, garrison: int) -> Array[SimProjectile]:
	_a_manned_tower(def_id, garrison)
	for i in range(200):
		w.step()
		var flying := _projectiles()
		if not flying.is_empty():
			return flying
	return []


func test_a_watch_tower_throws_five_stones() -> void:
	# The report: "watch tower is not showing 5x rocks when attacking". It was showing
	# one arrow.
	var volley := _volley_of(&"building.watch_tower", 0)
	assert_eq(volley.size(), 5)
	for p in volley:
		assert_eq(p.def_id, &"vis.projectile_stone", "a tower throws rocks now")


func test_a_guard_tower_looses_five_arrows() -> void:
	var volley := _volley_of(&"building.guard_tower", 0)
	assert_eq(volley.size(), 5)
	for p in volley:
		assert_eq(p.def_id, &"vis.projectile_arrow")


func test_each_garrisoned_archer_adds_one_of_its_own() -> void:
	# "+ X x arrows for each archer in garrison in it when attacking". The watch tower
	# is the interesting case: its own five are STONES and the garrison's three are
	# ARROWS, because the arrows come from the archers.
	var volley := _volley_of(&"building.watch_tower", 3)
	assert_eq(volley.size(), 8, "five of its own and one per archer")
	var stones := 0
	var arrows := 0
	for p in volley:
		if p.def_id == &"vis.projectile_stone":
			stones += 1
		elif p.def_id == &"vis.projectile_arrow":
			arrows += 1
	assert_eq(stones, 5)
	assert_eq(arrows, 3)


func test_a_garrisoned_swordsman_adds_nothing_to_look_at() -> void:
	# The same `attack_range > 0` line `attack_bonus` draws, so the picture and the
	# damage can never disagree about who counts as an archer.
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(40, 40),
			SimBuilding.Phase.COMPLETE, true)
	var sword := w.spawn_unit(&"unit.swordsman", 1, Vector2i(41, 45))
	tower.garrison.append({"id": sword.id, "def_id": sword.def_id})
	assert_eq(tower.garrison_projectiles(w).size(), 0, "a swordsman shoots nothing")
	assert_eq(tower.attack_bonus(w), 0, "and adds nothing, which is the same rule")


func test_the_volley_is_cosmetic_and_the_damage_is_unchanged() -> void:
	# THE POINT OF THE WHOLE FEATURE BEING SAFE. Five stones and one stone do the same
	# thing to the target, because a projectile carries no damage. If this ever fails,
	# the volley has become five attacks and every number in buildings.json is wrong.
	var tower := _a_manned_tower(&"building.watch_tower", 0)
	# The DECLARED number, which is the ceiling: the militia carries pierce armour, so
	# what actually lands is a little less. Printing both is the `preview_garrison`
	# lesson -- one number alone reads as the arithmetic being wrong.
	var expected := tower.attack_damage
	var hp := _raider.hp
	for i in range(200):
		w.step()
		if _raider.hp < hp:
			break
	assert_true(_raider.hp < hp, "it was shot at all")
	assert_true(hp - _raider.hp <= expected,
			"one shot's worth of damage, not five: lost %d against %d declared"
					% [hp - _raider.hp, expected])


func test_the_volley_fans_out_rather_than_stacking_on_one_line() -> void:
	# Five projectiles from one point to one point are one projectile as far as the
	# screen is concerned, which is the state this was meant to leave.
	var volley := _volley_of(&"building.guard_tower", 0)
	assert_eq(volley.size(), 5)
	var origins: Array[Vector2i] = []
	for p in volley:
		assert_false(origins.has(p.origin_pos), "each shot leaves from its own place")
		origins.append(p.origin_pos)
	# And parallel: every one covers the same displacement, so they travel together
	# instead of converging on a single sub-tile like a magnet.
	var span := volley[0].target_pos - volley[0].origin_pos
	for p in volley:
		assert_eq(p.target_pos - p.origin_pos, span, "the fan is parallel")


func test_a_building_with_no_volley_declared_still_looses_exactly_one() -> void:
	# The default that keeps 28 buildings out of this entirely.
	var d: BuildingDef = GameDataRegistry.building(&"building.house")
	assert_eq(d.attack_volley, 1, "declared nowhere, defaulted here")
	assert_eq(d.attack_damage, 0, "and it does not shoot at all")


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
