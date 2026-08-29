## Phase 4.8/4.9: units going into buildings, and towers shooting harder for it.
##
## The load-bearing cases are the ones nothing else in the sim has an equivalent for:
##
##   - **A unit off the map that is not dead.** `garrisoned_in` is the first field in
##     the project that takes an entity out of `SpatialHash` while leaving it in
##     `entities`, so the tests that matter most are the ones pinning which queries
##     can still find it (population: yes) and which cannot (everything else).
##   - **A building that attacks.** Before this, `CombatSystem` was unit-only from its
##     `process_tick` filter down, and a building was only ever a target.
##   - **The owner's numbers.** Capacities and the range ladder are pinned as data
##     assertions, because they are decisions (2026-08-27) and not tuning: the reason
##     siege out-ranges a tower and infantry does not is a design rule, and a silent
##     edit to buildings.json would otherwise be invisible.
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


## Every entity the spatial index can currently find, which is the question
## "what is on the map" -- as opposed to `w.entities`, which is "what exists".
func _ids_on_the_map() -> Array:
	var out: Array = []
	for e in w.entities_in_rect(Rect2i(Vector2i.ZERO, w.map.size)):
		out.append(int(e.id))
	return out


func _tower(owner: int = 1, at: Vector2i = Vector2i(20, 20)) -> SimBuilding:
	return w.spawn_building(&"building.watch_tower", owner, at)


# ── walking in ──────────────────────────────────────────────────────────────

func test_a_unit_ordered_into_a_tower_walks_there_and_goes_inside() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(10, 20))

	assert_true(GarrisonCommand.new(1, [archer.id], tower.id).validate(w))
	w.queue_command(GarrisonCommand.new(1, [archer.id], tower.id))
	var ticks := _run_until(func(): return archer.garrisoned_in != 0, 600)

	assert_true(ticks > 0, "it closed the distance and went in")
	assert_eq(archer.garrisoned_in, tower.id)
	assert_eq(tower.garrison.size(), 1)
	assert_eq(int(tower.garrison[0]["id"]), archer.id)
	assert_eq(StringName(tower.garrison[0]["def_id"]), &"unit.archer",
			"the entry carries the def id, because to_snapshot() cannot look one up")


func test_a_garrisoned_unit_is_off_the_map_but_has_not_been_despawned() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))

	assert_true(w.entities.has(archer.id), "it still exists")
	assert_true(archer.alive, "and it is not dead")
	assert_false(_ids_on_the_map().has(archer.id),
			"but nothing can find it -- that is the whole mechanism, and it is one "
			+ "spatial.remove() without a despawn()")
	assert_false(w.removed_this_tick.has(archer.id),
			"and it was never reported as removed, which would tell every client it died")


func test_it_still_costs_population_while_it_is_inside() -> void:
	# Hiding fifteen units in a castle must not buy fifteen free villagers.
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	w.step()
	var before := w.player_for(1).pop_used

	assert_true(w.garrison_unit(tower, archer))
	w.step()
	assert_eq(w.player_for(1).pop_used, before,
			"population is recounted from `entities`, which it never left")


func test_a_route_that_never_arrives_stands_the_unit_down() -> void:
	# The same answer BuildSystem gives a builder that did not reach its site: a unit
	# left in GARRISON with no route looks ordered and never arrives.
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(10, 20))
	w.queue_command(GarrisonCommand.new(1, [archer.id], tower.id))
	w.step()
	assert_eq(archer.task, SimUnit.Task.GARRISON)

	# Move the goalposts: the tower is gone before it gets there.
	tower.take_damage(tower.hp, 0)
	assert_true(_run_until(func(): return archer.is_idle(), 600) > 0,
			"it stopped rather than walking to a building that is not there")
	assert_eq(archer.garrisoned_in, 0)


# ── capacity ────────────────────────────────────────────────────────────────

func test_a_sixth_unit_cannot_enter_a_five_slot_tower() -> void:
	var tower := _tower()
	var six: Array[SimUnit] = []
	for i in range(6):
		six.append(w.spawn_unit(&"unit.archer", 1, Vector2i(21 + i, 24)))

	for u in six:
		w.garrison_unit(tower, u)

	assert_eq(tower.garrison.size(), 5, "the watch tower's cap, per the owner")
	assert_eq(six[5].garrisoned_in, 0, "the sixth is still outside")
	assert_true(_ids_on_the_map().has(six[5].id), "and still on the map")


func test_a_unit_that_walks_up_to_a_tower_that_filled_up_is_stood_down() -> void:
	# The case the command deliberately does NOT refuse at issue time: capacity is
	# checked on arrival, several seconds later, where the answer is current.
	var tower := _tower()
	var late := w.spawn_unit(&"unit.archer", 1, Vector2i(12, 20))
	w.queue_command(GarrisonCommand.new(1, [late.id], tower.id))
	w.step()

	for i in range(5):
		w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 1, Vector2i(24 + i, 24)))
	assert_eq(tower.garrison.size(), 5)

	assert_true(_run_until(func(): return late.is_idle(), 600) > 0,
			"it arrived, found no room, and stood down where it was")
	assert_eq(late.garrisoned_in, 0)
	assert_true(_ids_on_the_map().has(late.id), "the player still has the unit")


func test_the_same_unit_cannot_be_in_two_buildings() -> void:
	var first := _tower(1, Vector2i(20, 20))
	var second := _tower(1, Vector2i(30, 30))
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))

	assert_true(w.garrison_unit(first, archer))
	assert_false(w.garrison_unit(second, archer))
	assert_false(GarrisonCommand.new(1, [archer.id], second.id).validate(w),
			"and the command refuses it too, since its `pos` is stale and a route "
			+ "planned for it would be planned from nowhere")


# ── coming back out ─────────────────────────────────────────────────────────

func test_ungarrison_puts_a_unit_back_beside_the_building() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))

	w.queue_command(UngarrisonCommand.new(1, tower.id, 0))
	w.step()

	assert_eq(archer.garrisoned_in, 0)
	assert_true(tower.garrison.is_empty())
	assert_true(_ids_on_the_map().has(archer.id), "back in the spatial index")
	assert_eq(CombatSystem.tile_gap(archer.tile(), tower.footprint_rect()), 1,
			"and standing against the building it came out of")


func test_ungarrison_all_empties_the_tower_in_one_command() -> void:
	# Turning everybody out is what a player does when the raid is over, and it must
	# not be five taps.
	var tower := _tower()
	var inside: Array[SimUnit] = []
	for i in range(5):
		var u := w.spawn_unit(&"unit.archer", 1, Vector2i(21 + i, 24))
		inside.append(u)
		assert_true(w.garrison_unit(tower, u))

	w.queue_command(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL))
	w.step()

	assert_true(tower.garrison.is_empty(), "all five, not one")
	for u in inside:
		assert_eq(u.garrisoned_in, 0)
		assert_true(_ids_on_the_map().has(u.id))


func test_ungarrison_by_index_takes_the_one_named() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	var sword := w.spawn_unit(&"unit.swordsman", 1, Vector2i(22, 22))
	var militia := w.spawn_unit(&"unit.militia", 1, Vector2i(23, 22))
	for u in [archer, sword, militia]:
		assert_true(w.garrison_unit(tower, u))

	w.queue_command(UngarrisonCommand.new(1, tower.id, 1))
	w.step()

	assert_eq(tower.garrison.size(), 2)
	assert_eq(sword.garrisoned_in, 0, "slot 1 was the swordsman")
	assert_eq(archer.garrisoned_in, tower.id)
	assert_eq(militia.garrisoned_in, tower.id)


func test_ejecting_everybody_does_not_skip_every_other_occupant() -> void:
	# The bug a forward walk over a shrinking array produces, and the reason
	# UngarrisonCommand.apply walks backwards. Five is enough to expose it: a forward
	# walk would leave two behind.
	var tower := _tower()
	for i in range(5):
		assert_true(w.garrison_unit(tower,
				w.spawn_unit(&"unit.archer", 1, Vector2i(21 + i, 24))))

	UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL).apply(w)
	assert_eq(tower.garrison.size(), 0)


# ── healing (1 hp per 5 ticks, project owner 2026-08-27) ────────────────────

func test_a_garrisoned_unit_heals_one_hp_every_five_ticks() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	archer.hp = 1
	assert_true(w.garrison_unit(tower, archer))

	for _i in range(50):
		w.step()
	assert_eq(archer.hp, 11, "50 ticks at 1 hp per 5 = 10 hp, and it started at 1")


func test_healing_stops_at_the_units_own_maximum() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	archer.hp = archer.max_hp - 1
	assert_true(w.garrison_unit(tower, archer))

	for _i in range(100):
		w.step()
	assert_eq(archer.hp, archer.max_hp, "capped, not overflowing")


func test_a_damaged_tower_does_not_repair_itself_by_holding_archers() -> void:
	# Both maximums are to hand in `_heal`, and it uses the unit's. Repair is still
	# the disabled placeholder it has always been.
	var tower := _tower()
	tower.hp = tower.max_hp / 2
	var was := tower.hp
	assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))))

	for _i in range(50):
		w.step()
	assert_eq(tower.hp, was)


func test_a_unit_standing_outside_does_not_heal() -> void:
	_tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	archer.hp = 1
	for _i in range(50):
		w.step()
	assert_eq(archer.hp, 1, "healing is a property of being INSIDE, not of being near")


# ── dying with the building (project owner: "killed with building") ─────────

func test_the_garrison_dies_with_the_building() -> void:
	var tower := _tower()
	var inside: Array[SimUnit] = []
	for i in range(3):
		var u := w.spawn_unit(&"unit.archer", 1, Vector2i(21 + i, 24))
		inside.append(u)
		assert_true(w.garrison_unit(tower, u))

	tower.take_damage(tower.hp, 0)
	w.step()

	assert_true(tower.garrison.is_empty())
	for u in inside:
		assert_false(u.alive, "no auto-eject: a castle at 15 is a real commitment")
		assert_eq(u.garrisoned_in, 0)
		assert_eq(u.hp, 0)


func test_the_bodies_appear_beside_the_wreckage_rather_than_where_they_walked_in() -> void:
	# A corpse has to be SOMEWHERE. Killing them in place would leave bodies at the
	# tile each walked in from -- possibly across the map, possibly under a building
	# somebody has since put there.
	var tower := _tower(1, Vector2i(30, 30))
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(4, 4))
	archer.pos = SimUnit.centre_of_tile(Vector2i(4, 4))
	assert_true(w.garrison_unit(tower, archer))

	tower.take_damage(tower.hp, 0)
	w.step()

	assert_false(u_far(archer, tower), "the body is against the tower, not at (4, 4)")
	# The SPATIAL INDEX itself rather than `_ids_on_the_map()`, which goes through
	# `entities_in_rect` and filters out anything not `alive` -- so a corpse is
	# correctly absent from that and present here. Being in the index is what makes
	# DeathSystem's corpse a body somebody can see.
	assert_true(w.spatial.query_rect(Rect2i(Vector2i.ZERO, w.map.size)).has(archer.id),
			"it was put back in the index before it was killed")


func u_far(u: SimUnit, b: SimBuilding) -> bool:
	return CombatSystem.tile_gap(u.tile(), b.footprint_rect()) > 2


# ── the tower's own attack (4.9) ────────────────────────────────────────────

func test_an_empty_tower_still_defends() -> void:
	# The owner's choice between two readings of the spec. It matters most for the
	# case nobody plans for: a raid arriving while every unit you own is out mining.
	var tower := _tower()
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))
	assert_true(tower.garrison.is_empty())

	w.step()
	assert_eq(raider.hp, raider.max_hp - 6, "the watch tower's own 6 damage")


func test_each_garrisoned_archer_adds_half_its_own_damage() -> void:
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(20, 20))
	for i in range(3):
		assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 1, Vector2i(28 + i, 28))))
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))

	assert_eq(tower.attack_bonus(w), 6, "three archers at 4 damage, halved and floored")
	w.step()
	assert_eq(raider.hp, raider.max_hp - 14, "the guard tower's 8 plus the garrison's 6")


func test_the_bonus_floors_rather_than_rounding() -> void:
	# Integer division, like every other number spent inside a state transition: an
	# ARM phone and an x86 host must agree to the last hit point.
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(20, 20))
	assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.crossbowman", 1, Vector2i(28, 28))))
	assert_eq(tower.attack_bonus(w), 2, "crossbowman damage 5, halved to 2 and not 3")


func test_swordsmen_and_spearmen_inside_add_nothing() -> void:
	# The owner named pikemen and swordsmen; the rule is `attack_range > 0`, so every
	# melee unit in the roster is covered without anybody maintaining a list.
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(20, 20))
	for def_id in [&"unit.swordsman", &"unit.spearman", &"unit.militia"]:
		assert_true(w.garrison_unit(tower, w.spawn_unit(def_id, 1, Vector2i(28, 28))))
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))

	assert_eq(tower.attack_bonus(w), 0)
	w.step()
	assert_eq(raider.hp, raider.max_hp - 8, "the tower's own damage and not a point more")


func test_every_melee_unit_in_the_roster_adds_nothing() -> void:
	# The claim above, checked against the data rather than against three examples --
	# a new melee unit shipped with `range: 1` by mistake would show up here.
	var tower := w.spawn_building(&"building.castle", 1, Vector2i(20, 20))
	for id in GameDataRegistry.unit_ids():
		var ud: UnitDef = GameDataRegistry.unit(id)
		if ud == null or ud.attack_range > 0:
			continue
		tower.garrison = [{"id": 0, "def_id": id}]
		assert_eq(tower.attack_bonus(w), 0, "%s is melee and must add nothing" % id)


func test_a_garrisoned_archer_does_not_also_shoot_on_its_own() -> void:
	# Fifteen archers in a castle are one heavier arrow every two seconds, not
	# sixteen arrows. The unit is IDLE and out of the spatial index, so CombatSystem
	# never looks at it -- this pins that rather than assuming it.
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(20, 20))
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(28, 28))
	assert_true(w.garrison_unit(tower, archer))
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))

	w.step()
	# 8 + 2 exactly. A second, independent archer shot would take four more off.
	assert_eq(raider.hp, raider.max_hp - 10)
	assert_eq(archer.task, SimUnit.Task.IDLE)


func test_a_tower_fires_on_its_cooldown_and_not_every_tick() -> void:
	var tower := _tower()
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))
	raider.hp = 300
	raider.max_hp = 300

	for _i in range(20):
		w.step()
	# 20 ticks at a 20-tick cooldown: the shot on tick 1, and the next is due on 21.
	assert_eq(raider.hp, 300 - 6, "one shot in twenty ticks, not twenty")


func test_a_tower_shoots_the_nearest_of_two_enemies() -> void:
	var tower := _tower()
	var near := w.spawn_unit(&"unit.villager", 2, Vector2i(23, 21))
	var far := w.spawn_unit(&"unit.villager", 2, Vector2i(25, 21))

	w.step()
	assert_true(near.hp < near.max_hp, "the near one was hit")
	assert_eq(far.hp, far.max_hp, "and the far one was not")


func test_a_tower_does_not_shoot_past_its_range() -> void:
	var tower := _tower()
	# Range 6 from the footprint, which ends at x = 22 for a [3, 2] at (20, 20).
	var outside := w.spawn_unit(&"unit.villager", 2, Vector2i(40, 21))
	for _i in range(30):
		w.step()
	assert_eq(outside.hp, outside.max_hp)
	assert_eq(tower.attack_cooldown, 0, "and it never fired, so nothing is counting down")


func test_a_tower_does_not_shoot_its_owners_own_units() -> void:
	_tower()
	var mine := w.spawn_unit(&"unit.villager", 1, Vector2i(24, 21))
	for _i in range(30):
		w.step()
	assert_eq(mine.hp, mine.max_hp)


func test_a_tower_leaves_the_trees_alone_and_shoots_a_wolf() -> void:
	# Gaia owns the trees AND the wolf, so the test cannot be about owner 0. A bear
	# wandering into a settlement is what a watch tower is for.
	_tower()
	var tree := w.spawn_resource_node(&"res.tree", Vector2i(24, 21), 0)
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(23, 22))
	assert_not_null(tree)

	assert_true(_run_until(func(): return wolf.hp < wolf.max_hp, 60) > 0)
	assert_eq(tree.hp, tree.max_hp, "a tree is scenery, not a belligerent")


func test_a_tower_does_not_slaughter_the_livestock() -> void:
	# FOUND BY `preview_garrison` AND NOT BY THIS SUITE. `Diplomacy.is_enemy` answers
	# "may I attack this", and for a sheep the answer is yes -- hunting is how a deer
	# becomes food. A tower's auto-acquire needs the other question, "who am I at war
	# with", which is why `AISystem._nearest_enemy` keeps its own copy too.
	#
	# Worse than cosmetic: the tower spent every shot on the nearest animal and never
	# touched the raider behind it, so it read as a tower that did not work at all.
	_tower()
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(23, 21))
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(23, 22))
	var cow := w.spawn_unit(&"unit.cattle", 0, Vector2i(24, 21))

	for _i in range(60):
		w.step()
	for animal in [sheep, deer, cow]:
		assert_eq(animal.hp, animal.max_hp,
				"%s carries aggro_radius 0 and is nobody's enemy" % animal.def_id)


func test_a_tower_does_not_shoot_its_owners_own_herd() -> void:
	# A HERDED SHEEP IS STILL GAIA'S -- `herded_by` is deliberately separate from
	# `owner_id` (6.5) -- so an owner comparison alone would have a player's tower
	# gunning down the player's own flock.
	var tower := _tower()
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(23, 21))
	sheep.herded_by = tower.owner_id

	for _i in range(60):
		w.step()
	assert_eq(sheep.hp, sheep.max_hp)


func test_a_grazing_animal_does_not_shield_a_raider_standing_behind_it() -> void:
	# The way the bug actually presented: nearest-target-wins, and the animal was
	# always nearer.
	_tower()
	w.spawn_unit(&"unit.sheep", 0, Vector2i(23, 21))
	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(25, 21))

	assert_true(_run_until(func(): return raider.hp < raider.max_hp, 60) > 0,
			"the tower looked past the sheep")


func test_a_foundation_neither_garrisons_nor_shoots() -> void:
	var tower := w.spawn_building(&"building.watch_tower", 1, Vector2i(20, 20),
			SimBuilding.Phase.FOUNDATION)
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(24, 21))
	# PASSIVE, added 2026-08-29 with stances (4.12). The second half of this test asks
	# whether the FOUNDATION defends you, and on the default stance the archer standing
	# beside it does -- so the raider lost 8 hp and the assertion caught its own fixture
	# rather than the tower. The archer is here only for the garrison refusals above.
	archer.stance = SimUnit.Stance.PASSIVE

	assert_false(tower.has_garrison_room(), "a foundation is a hole in the ground")
	assert_false(w.garrison_unit(tower, archer))
	assert_false(GarrisonCommand.new(1, [archer.id], tower.id).validate(w))

	var raider := w.spawn_unit(&"unit.villager", 2, Vector2i(23, 22))
	for _i in range(30):
		w.step()
	assert_eq(raider.hp, raider.max_hp,
			"a tower you have not finished paying for does not defend you")


func test_a_tower_does_not_shoot_buildings() -> void:
	# A building cannot walk into range, so the only way a tower could be shooting one
	# is that somebody built next door -- and a tower opening fire on a newly placed
	# house is a border war nobody declared.
	_tower(1, Vector2i(20, 20))
	var theirs := w.spawn_building(&"building.house", 2, Vector2i(24, 20))
	assert_not_null(theirs)
	for _i in range(30):
		w.step()
	assert_eq(theirs.hp, theirs.max_hp)


# ── the owner's numbers, pinned as data ─────────────────────────────────────

func test_only_the_two_towers_and_the_castle_hold_anybody() -> void:
	var holders: Array[String] = []
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd != null and bd.garrison_cap > 0:
			holders.append("%s=%d" % [id, bd.garrison_cap])
	holders.sort()
	assert_eq(holders, [
		"building.castle=15", "building.guard_tower=5", "building.watch_tower=5",
	], "project owner 2026-08-27: 'only guard & watch towers x5 and castle x15'")


func test_no_wall_or_gate_holds_anybody() -> void:
	var checked := 0
	for id in GameDataRegistry.building_ids():
		if not String(id).begins_with("building.wall_"):
			continue
		checked += 1
		assert_eq(GameDataRegistry.building(id).garrison_cap, 0,
				"'walls will not be garrisoned' -- %s" % id)
	assert_eq(checked, 12, "all twelve wall and gate pieces")


func test_the_town_centre_is_not_a_refuge() -> void:
	# It carried 15 from 0.4 until 2026-08-27, on IDEA.md 4.9's sketch, and nothing
	# ever read it. The owner's "only" is exclusive: a villager under attack has
	# nowhere to hide, deliberately.
	for id in [&"building.town_center", &"building.barracks", &"building.monastery"]:
		assert_eq(GameDataRegistry.building(id).garrison_cap, 0, String(id))


func test_a_tower_out_ranges_infantry_and_siege_out_ranges_a_tower() -> void:
	# The design rule behind 6/7/8, and the reason those numbers are not converted
	# from 0 A.D. (whose archer reaches 18 tiles against our 4).
	var towers := {
		&"building.watch_tower": 6, &"building.guard_tower": 7, &"building.castle": 8,
	}
	for id in towers:
		assert_eq(GameDataRegistry.building(id).attack_range, int(towers[id]), String(id))

	# LAND ONLY. Ships are a third case and the galleon breaks the rule below on
	# purpose -- see the assertion after the loop.
	for id in GameDataRegistry.unit_ids():
		var ud: UnitDef = GameDataRegistry.unit(id)
		if ud == null or ud.attack_range <= 0 or String(ud.domain) != "land":
			continue
		for tower_id in towers:
			var reach: int = int(towers[tower_id])
			if ud.attack_range >= 9:
				assert_true(ud.attack_range > reach,
						"%s is siege and must out-range %s" % [id, tower_id])
			else:
				assert_true(ud.attack_range < reach,
						"%s must be out-ranged by %s" % [id, tower_id])

	# THE GALLEON IS THE ONE UNIT THAT OUT-REACHES A TOWER WITHOUT BEING SIEGE, at 7
	# against the watch tower's 6, and it is left that way rather than pushed under it.
	# A capital warship threatening a coastal watch tower is the right outcome -- it is
	# the naval equivalent of what siege does on land -- and it can never reach an
	# inland one at all, being domain water. Pinned so the exception is a decision on
	# record and not something that drifted in.
	assert_eq(GameDataRegistry.unit(&"unit.galleon").attack_range, 7)
	assert_eq(String(GameDataRegistry.unit(&"unit.galleon").domain), "water")
	assert_true(GameDataRegistry.unit(&"unit.galley").attack_range < 6,
			"the lesser warship is still out-ranged by every tower")


func test_every_attacking_building_names_a_projectile_and_a_cooldown() -> void:
	# A building has no arm to swing, so a shot with no projectile drops health bars
	# with nothing on screen to explain it -- and a cooldown of 0 would fire ten
	# times a second, which `CombatSystem`'s floor of 1 makes survivable and silent.
	var attackers := 0
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd == null or bd.attack_damage <= 0:
			continue
		attackers += 1
		assert_ne(bd.attack_projectile, &"", String(id))
		assert_true(bd.attack_cooldown_ticks > 0, String(id))
		assert_eq(bd.attack_type, &"pierce", "a tower shoots arrows -- %s" % id)
	assert_eq(attackers, 3, "the two towers and the castle, and nothing else")


func test_an_upgrade_re_reads_the_attack_off_the_new_def() -> void:
	# `convert_building` re-reads every def-derived field rather than patching
	# selectively, and the new attack fields have to be in that list -- a field left
	# over from the old def is exactly the kind of thing that stays wrong quietly.
	var tower := _tower()
	assert_eq(tower.attack_damage, 6)
	w.convert_building(tower, &"building.castle")
	assert_eq(tower.attack_damage, 12)
	assert_eq(tower.attack_range, 8)
	assert_eq(tower.garrison_cap, 15)


# ── refusals ────────────────────────────────────────────────────────────────

func test_you_cannot_garrison_into_a_building_that_holds_nobody() -> void:
	var house := w.spawn_building(&"building.house", 1, Vector2i(20, 20))
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(24, 21))
	assert_false(GarrisonCommand.new(1, [archer.id], house.id).validate(w))
	assert_false(house.has_garrison_room())


func test_you_cannot_garrison_into_somebody_elses_tower() -> void:
	# 0 A.D. allows it for an ally; we have no alliance in v1, so `Diplomacy` would
	# have to grow a "friendly but not mine" for a case nobody can reach.
	var theirs := _tower(2)
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(24, 21))
	assert_false(GarrisonCommand.new(1, [archer.id], theirs.id).validate(w))


func test_you_cannot_garrison_somebody_elses_units() -> void:
	var tower := _tower()
	var theirs := w.spawn_unit(&"unit.archer", 2, Vector2i(24, 21))
	assert_false(GarrisonCommand.new(1, [theirs.id], tower.id).validate(w))


func test_an_empty_order_is_refused() -> void:
	var tower := _tower()
	assert_false(GarrisonCommand.new(1, [], tower.id).validate(w))


func test_a_dead_unit_cannot_be_ordered_in() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(24, 21))
	archer.take_damage(archer.hp, 0)
	assert_false(GarrisonCommand.new(1, [archer.id], tower.id).validate(w))


func test_you_cannot_empty_a_tower_that_is_already_empty() -> void:
	var tower := _tower()
	assert_false(UngarrisonCommand.new(1, tower.id, UngarrisonCommand.ALL).validate(w))


func test_you_cannot_empty_somebody_elses_tower() -> void:
	var theirs := _tower(2)
	assert_true(w.garrison_unit(theirs, w.spawn_unit(&"unit.archer", 2, Vector2i(24, 21))))
	assert_false(UngarrisonCommand.new(1, theirs.id, UngarrisonCommand.ALL).validate(w))


func test_an_index_past_the_end_is_refused() -> void:
	var tower := _tower()
	assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 1, Vector2i(24, 21))))
	assert_true(UngarrisonCommand.new(1, tower.id, 0).validate(w))
	assert_false(UngarrisonCommand.new(1, tower.id, 1).validate(w))
	assert_false(UngarrisonCommand.new(1, tower.id, -2).validate(w))


# ── the wire ────────────────────────────────────────────────────────────────

func test_both_commands_survive_the_wire() -> void:
	var out := GarrisonCommand.new(4, [7, 9] as Array[int], 77, 5)
	var back := Command.from_dict(out.to_dict())
	assert_true(back is GarrisonCommand)
	assert_eq((back as GarrisonCommand).unit_ids, [7, 9])
	assert_eq((back as GarrisonCommand).target_id, 77)
	assert_eq(back.player_id, 4)
	assert_eq(back.issued_tick, 5)

	var out2 := UngarrisonCommand.new(3, 41, UngarrisonCommand.ALL, 8)
	var back2 := Command.from_dict(out2.to_dict())
	assert_true(back2 is UngarrisonCommand)
	assert_eq((back2 as UngarrisonCommand).building_id, 41)
	assert_eq((back2 as UngarrisonCommand).index, UngarrisonCommand.ALL)


func test_a_garrisoned_unit_is_not_in_the_snapshot_at_all() -> void:
	# Not even to its own owner. That is what "removed from the world map" means, and
	# it is what makes the client forget the sprite and drop it from the selection.
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	w.step()
	assert_true(_snapshot_has(1, archer.id), "on the map, it is sent")

	assert_true(w.garrison_unit(tower, archer))
	w.step()
	assert_false(_snapshot_has(1, archer.id), "inside, it is not")


func test_the_building_reports_the_headcount_and_who_is_in_it() -> void:
	var tower := _tower()
	assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))))
	w.step()

	var entry := _snapshot_entry(1, tower.id)
	assert_eq(int(entry["garrison_count"]), 1)
	assert_eq(entry["garrison"], ["unit.archer"],
			"def ids, so the panel can crop that unit's own portrait")


func test_every_building_carries_the_two_fields_even_when_it_holds_nobody() -> void:
	# A field present on some buildings and absent on others splits every building
	# into two wire shapes (12.1f), which costs more than the ints it saves.
	var house := w.spawn_building(&"building.house", 1, Vector2i(30, 30))
	w.step()
	var entry := _snapshot_entry(1, house.id)
	assert_true(entry.has("garrison_count"))
	assert_true(entry.has("garrison"))
	assert_eq(int(entry["garrison_count"]), 0)


func test_a_remembered_building_reports_neither() -> void:
	# How many units are in the enemy castle you last saw an hour ago -- and which
	# units they are -- is the same class of fact as their production queue.
	var tower := _tower(2)
	assert_true(w.garrison_unit(tower, w.spawn_unit(&"unit.archer", 2, Vector2i(24, 21))))
	var full := tower.to_snapshot()
	assert_true(full.has("garrison_count"))

	var stripped := SnapshotSystem._remembered(tower)
	assert_false(stripped.has("garrison_count"), "the headcount prices the shot on its own")
	assert_false(stripped.has("garrison"))
	assert_true(bool(stripped["remembered"]))


func _snapshot_entry(viewer: int, id: int) -> Dictionary:
	for entry in SnapshotSystem.build(w, viewer).get("updated", []):
		if int(entry["id"]) == id:
			return entry
	return {}


func _snapshot_has(viewer: int, id: int) -> bool:
	return not _snapshot_entry(viewer, id).is_empty()


# ── determinism (a desync is the only way this can go really wrong) ─────────

func test_the_garrison_and_the_cooldown_are_in_the_state_hash() -> void:
	var tower := _tower()
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	var before := w.state_hash()
	assert_true(w.garrison_unit(tower, archer))
	assert_ne(w.state_hash(), before, "a unit going indoors changes the world")

	# The SET and not merely the COUNT: two clients holding the same five slots
	# filled by different units would price the tower's shot differently.
	var swapped := w.state_hash()
	tower.garrison = [{"id": archer.id, "def_id": &"unit.swordsman"}]
	assert_ne(w.state_hash(), swapped)


func test_two_worlds_garrisoning_the_same_units_stay_identical() -> void:
	var other := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.map_size = Vector2i(48, 48)
	other.setup(cfg)
	other.map.fill_terrain(SimMap.Terrain.GRASS)

	for world in [w, other]:
		var tower: SimBuilding = world.spawn_building(&"building.guard_tower", 1,
				Vector2i(20, 20))
		var ids: Array[int] = []
		for i in range(4):
			ids.append(world.spawn_unit(&"unit.archer", 1, Vector2i(10 + i, 20)).id)
		world.spawn_unit(&"unit.villager", 2, Vector2i(24, 21))
		world.queue_command(GarrisonCommand.new(1, ids, tower.id))

	for _i in range(300):
		w.step()
		other.step()
	assert_eq(w.state_hash(), other.state_hash())

	# And they actually did the thing, or this would pass on two empty worlds.
	var tower_id := 0
	for e in w.entities.values():
		if e is SimBuilding:
			tower_id = e.id
	assert_true((w.get_entity(tower_id) as SimBuilding).garrison.size() > 0)


# ── the stale-entry guard ───────────────────────────────────────────────────

func test_an_entry_whose_unit_has_gone_stops_pricing_the_tower() -> void:
	# `attack_bonus` reads each ENTRY's own def id rather than the live entity, so a
	# stale entry would add damage forever with no unit anywhere to explain it.
	# Nothing should be able to reach this today; GarrisonSystem prunes it because the
	# failure is silent and permanent rather than because it is expected.
	var tower := w.spawn_building(&"building.guard_tower", 1, Vector2i(20, 20))
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(21, 22))
	assert_true(w.garrison_unit(tower, archer))
	assert_eq(tower.attack_bonus(w), 2)

	w.despawn(archer.id)
	w.step()
	assert_true(tower.garrison.is_empty(), "pruned")
	assert_eq(tower.attack_bonus(w), 0)
