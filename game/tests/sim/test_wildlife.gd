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
	assert_false(Diplomacy.is_enemy(tree, 1, w.teams), "a swordsman may not be sent at an oak")
	assert_true(Diplomacy.is_enemy(wolf, 1, w.teams), "but may be sent at a wolf")


func test_a_wolf_is_not_its_own_enemy() -> void:
	# Asked from the pack's side: owner 0 looking at owner 0. Nothing says "wolves are
	# friendly to wolves" anywhere -- it falls out of the owner clause.
	var a := w.spawn_unit(&"unit.wolf", 0, Vector2i(10, 10))
	assert_false(Diplomacy.is_enemy(a, 0, w.teams))


func test_the_dead_and_the_typeless_are_never_enemies() -> void:
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(10, 10))
	wolf.take_damage(9999, 0)
	assert_false(Diplomacy.is_enemy(wolf, 1, w.teams), "a carcass is not a fight")
	assert_false(Diplomacy.is_enemy(null, 1, w.teams), "and null is not a crash")


func test_the_view_and_the_sim_answer_the_same_question() -> void:
	# These two used to be unrelated lines in unrelated layers. When they drift, the
	# tap offers an attack the sim then refuses and the game does nothing, silently.
	for owner_id in [0, 1, 2]:
		for is_unit in [true, false]:
			var f := {"owner_id": owner_id, "is_unit": is_unit, "alive": true}
			var expected: bool = (owner_id != 1) and (owner_id != 0 or is_unit)
			assert_eq(Diplomacy.is_enemy_fact(f, 1, w.teams), expected,
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


## "It did not pick a fight." NOT `task == IDLE`, which is what these said until 6.1b
## gave predators a `roam_radius` -- a wolf with nothing to hunt now wanders, so its
## task is MOVE and the old assertion started failing on a feature working correctly.
func _assert_not_hunting(u: SimUnit, why: String) -> void:
	assert_true(u.task != SimUnit.Task.ATTACK, why)


func test_a_wolf_ignores_a_villager_beyond_its_aggro_radius() -> void:
	# Otherwise it is not a hazard you can walk around, it is a hazard that owns the
	# map. aggro_radius is the entire aggression of the thing.
	var pair := _pair(20)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	_assert_not_hunting(pair[0] as SimUnit, "20 tiles is out of range")


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
	_assert_not_hunting(a, "a pack does not turn on itself")
	_assert_not_hunting(b, "either way round")


func test_a_wolf_does_not_gnaw_buildings() -> void:
	# `Diplomacy` would allow it -- a town centre is a legal target for anybody. The
	# filter is WildlifeSystem's, because a wolf parked on a granary for four hundred
	# bites is not wildlife, it is a siege engine.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	w.spawn_building(&"building.house", 1, Vector2i(41, 40))
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	_assert_not_hunting(wolf, "a wolf is not a siege engine")


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


# ── a settlement drives predators off (project owner, 2026-08-28) ──────────
#
# "if a wolf, bear, boar gets within 15 tiles of a building it should retreat to a
# random spot opposite direction from the building and reset agro, so early game the
# player can manually run villagers back town to save them, at this stage 1 wolf eats
# 4 villagers before they get to kill it."
#
# The numbers behind that: a wolf deals 20 to a 30 hp villager who deals 3 back. The
# fight is unwinnable one-to-one and always was; what was missing was the OUT.

func test_a_wolf_that_wanders_into_a_settlement_turns_around() -> void:
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	w.spawn_building(&"building.town_center", 1, Vector2i(48, 40),
			SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)

	_assert_not_hunting(wolf, "the villager beside it is not on the menu here")
	assert_true(wolf.flee_ticks > 0, "it is leaving")


func test_it_leaves_ON_THE_OPPOSITE_SIDE_rather_than_anywhere() -> void:
	# "a random spot opposite direction from the building". Retreating toward the town
	# would satisfy "it stopped attacking" and be worse than doing nothing.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(48, 40),
			SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)

	var away := wolf.tile() - tc.tile()
	var heading := wolf.roam_home - tc.tile()
	assert_true(heading.length() > away.length(), "further out than it started")
	assert_true(Vector2(heading).dot(Vector2(away)) > 0.0,
			"and on the wolf's side of the town, not through it")


func test_the_retreat_clears_the_target_and_not_just_the_path() -> void:
	# "reset agro". Without the stop, CombatSystem keeps the wolf's target and
	# `_close_in` walks it straight back to the villager it was told to leave.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task_target_id, villager.id, "it had one to begin with")

	w.spawn_building(&"building.town_center", 1, Vector2i(48, 40),
			SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_ne(wolf.task_target_id, villager.id, "the wolf has forgotten her")


func test_a_villager_who_runs_home_survives_and_that_is_the_whole_point() -> void:
	# The report, as a test. She is bitten out in the field and stops being bitten once
	# she is standing in the town -- which is what "the player can manually run villagers
	# back to town to save them" means.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	# Stopped on the FIRST bite rather than after a fixed run: a wolf deals 20 to a
	# 30 hp villager, so two of them kill her and a test that let that happen would
	# then be comparing 0 against 0 and passing for the wrong reason.
	for i in range(60):
		w.step()
		if villager.hp < villager.max_hp:
			break
	assert_true(villager.hp < villager.max_hp, "the wolf got its teeth in first")
	assert_true(villager.alive, "and she is still standing, which the rest needs")

	w.spawn_building(&"building.town_center", 1, Vector2i(45, 40),
			SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 2)
	var safe := villager.hp
	assert_true(wolf.flee_ticks > 0, "the wolf is leaving")
	_run(60)
	assert_eq(villager.hp, safe, "not bitten again once the town was there")


func test_a_deer_is_not_driven_off_by_a_farm() -> void:
	# Predators only (`aggro_radius > 0`), the same line the towers use to decide which
	# animals they shoot. Emptying the map of herds around every settlement would take
	# the food with them, and a deer grazing by a granary is nobody's problem.
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(40, 40))
	w.spawn_building(&"building.house", 1, Vector2i(42, 40), SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(deer.flee_ticks, 0, "nothing frightened it")


func test_gaia_owns_no_sanctuary() -> void:
	# `owner_id == 0` is excluded so that the day a map carries ruins or a neutral
	# market, they do not silently become places wolves refuse to go.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	w.spawn_building(&"building.house", 0, Vector2i(43, 40), SimBuilding.Phase.COMPLETE, true)
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task_target_id, villager.id, "a gaia hut protects nobody")


func test_a_building_far_enough_away_changes_nothing() -> void:
	# The radius is a real bound. A settlement on the far side of the map must not
	# pacify the whole wilderness.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	# A HOUSE AND NOT A TOWN CENTRE, and the distance is measured off its far edge.
	# The first draft put a town centre at radius + 4 and the wolf retreated anyway,
	# because the radius is measured from the FOOTPRINT and a town centre is eight
	# tiles of it -- so "four tiles clear" was really four tiles inside. The bound is
	# real; the fixture was wrong about where the building ended.
	var far := w.spawn_building(&"building.house", 1,
			Vector2i(40 - WildlifeSystem.SETTLEMENT_RADIUS - 6, 40),
			SimBuilding.Phase.COMPLETE, true)
	assert_true(CombatSystem.tile_gap(wolf.tile(), far.footprint_rect())
			> WildlifeSystem.SETTLEMENT_RADIUS, "the fixture really is out of range")
	_run(WildlifeSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.task_target_id, villager.id, "still hunting, out in the wild")


# ── roaming and fleeing (6.1b) ─────────────────────────────────────────────

func test_a_predator_with_nothing_to_hunt_wanders() -> void:
	# The whole of 6.1b's first half, and the reason `res.deer`'s roam_radius was dead
	# data for months: roaming needs MovementSystem, which moves units and skips nodes.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var start := wolf.tile()
	_run(WildlifeSystem.ROAM_INTERVAL_TICKS + 40)
	assert_true(wolf.tile() != start, "it went somewhere, from %s" % start)


func test_a_wanderer_stays_near_the_ground_it_settled_on() -> void:
	# Otherwise it is not roaming, it is emigrating -- and a predator that drifts off
	# the map is one the player never meets.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	var home := wolf.tile()
	var radius: int = (w.unit_def(&"unit.wolf") as UnitDef).roam_radius
	for i in range(WildlifeSystem.ROAM_INTERVAL_TICKS * 6):
		w.step()
		var gap: int = maxi(absi(wolf.tile().x - home.x), absi(wolf.tile().y - home.y))
		assert_true(gap <= radius + 2, "wandered %s from home at tick %s" % [gap, i])


func test_a_deer_bolts_when_it_is_hit() -> void:
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(40, 40))
	_run(2)
	var before := deer.tile()
	deer.take_damage(5, 0)
	_run(1)
	assert_true(deer.flee_ticks > 0, "running")
	_run(WildlifeSystem.FLEE_TICKS)
	var gap: int = maxi(absi(deer.tile().x - before.x), absi(deer.tile().y - before.y))
	assert_true(gap > 1, "and got somewhere -- moved %s tiles" % gap)


func test_a_deer_runs_away_from_what_hit_it_rather_than_towards_it() -> void:
	# A flee that happened to point at the attacker would read as a charge, and this
	# animal has no attack at all.
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(40, 40))
	var hunter := w.spawn_unit(&"unit.villager", 1, Vector2i(37, 40))
	_run(2)
	var before: int = absi(deer.tile().x - hunter.tile().x)
	deer.take_damage(5, 0)
	_run(WildlifeSystem.FLEE_TICKS)
	assert_true(absi(deer.tile().x - hunter.tile().x) > before,
			"further from the villager than it started")


func test_a_hunted_deer_settles_somewhere_new() -> void:
	# "Flee-and-RELOCATE" -- the second half of 6.1b's name. A herd that gets shot at
	# should move off, not drift back to the clearing it was shot in.
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(40, 40))
	_run(2)
	var first_home := deer.roam_home
	deer.take_damage(5, 0)
	_run(WildlifeSystem.FLEE_TICKS + 2)
	assert_true(deer.roam_home != first_home,
			"home moved from %s to %s" % [first_home, deer.roam_home])


func test_a_predator_does_not_flee_when_hurt() -> void:
	# Deliberate: a wolf that bolted the first time a villager hit it would be a
	# hazard nobody ever had to deal with. `flees` is per-animal data, not a rule.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	_run(2)
	wolf.take_damage(5, 0)
	_run(3)
	assert_eq(wolf.flee_ticks, 0)


func test_a_deer_is_not_a_resource_node_any_more() -> void:
	# It carried `wildlife: { roam_radius: 6, flees: true }` in resources.json for
	# months, on a class that could not act on either field.
	assert_null(GameDataRegistry.resource_def(&"res.deer"), "gone from resources.json")
	var deer: UnitDef = GameDataRegistry.unit(&"unit.deer")
	assert_not_null(deer, "and is a unit now")
	assert_true(deer.is_wildlife)
	assert_eq(deer.roam_radius, 6)
	assert_true(deer.flees)
	assert_eq(deer.aggro_radius, 0, "it hunts nothing")
	assert_eq(deer.attack_damage, 0, "and cannot fight back")
	assert_eq(deer.carcass_def, &"res.deer_carcass")


func test_hunting_a_deer_yields_the_food_it_used_to_stand_around_holding() -> void:
	var deer := w.spawn_unit(&"unit.deer", 0, Vector2i(40, 40))
	deer.take_damage(9999, 0)
	_run(1)
	var carcass: SimResourceNode = null
	for e in w.entities.values():
		if e is SimResourceNode and (e as SimResourceNode).def_id == &"res.deer_carcass":
			carcass = e
	assert_not_null(carcass)
	assert_eq(carcass.amount, 140, "the old res.deer figure, unchanged")
	assert_true(GatherSystem.is_harvestable(carcass, 1))


# ── herding livestock (6.5) ────────────────────────────────────────────────

func test_walking_a_unit_past_a_sheep_claims_it() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	assert_eq(sheep.herded_by, 0, "nobody's to begin with")
	w.spawn_unit(&"unit.villager", 1, Vector2i(42, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1)


func test_claiming_does_not_transfer_OWNERSHIP() -> void:
	# THE DESIGN, in one assertion. A herded sheep stays gaia's, which is what kept
	# GatherSystem, WinConditionSystem and AttackCommand out of this entirely.
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1, "claimed")
	assert_eq(sheep.owner_id, 0, "and still nobody's")


func test_a_claimed_sheep_takes_move_orders_from_its_herder_and_nobody_else() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)

	var ids: Array[int] = [sheep.id]
	assert_true(MoveCommand.new(1, ids, Vector2i(30, 30)).validate(w), "its herder")
	assert_false(MoveCommand.new(2, ids, Vector2i(30, 30)).validate(w), "not player 2")


func test_an_unclaimed_sheep_takes_orders_from_nobody() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	var ids: Array[int] = [sheep.id]
	assert_false(MoveCommand.new(1, ids, Vector2i(30, 30)).validate(w))


func test_a_sheep_can_actually_be_walked_home() -> void:
	# The whole point of the feature: a food source you move rather than travel to.
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	var start := sheep.tile()
	w.queue_command(MoveCommand.new(1, [sheep.id] as Array[int], Vector2i(34, 40)))
	_run(120)
	assert_true(sheep.tile() != start, "it walked, from %s to %s" % [start, sheep.tile()])


func test_another_player_walking_closer_takes_the_sheep() -> void:
	# Exactly what the project owner asked for: "if another player walks past them
	# they claim them and they can manage them".
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	var mine := w.spawn_unit(&"unit.villager", 1, Vector2i(43, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1, "player 1 got there first")

	w.spawn_unit(&"unit.villager", 2, Vector2i(41, 40))     # nearer
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 2, "and player 2 walked closer")
	assert_true(mine.alive, "nobody had to fight over it")


func test_walking_away_does_not_give_the_sheep_back() -> void:
	# Sticky, so a flock can be penned at home and left there while the shepherd goes
	# back to work. Releasing on distance would make herding useless.
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1)

	w.despawn(villager.id)
	_run(HerdSystem.THINK_INTERVAL_TICKS * 3)
	assert_eq(sheep.herded_by, 1, "still ours")


func test_a_sheep_beyond_the_claim_radius_is_not_claimed() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(40 + HerdSystem.CLAIM_RADIUS + 3, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 0)


func test_a_predator_cannot_be_herded() -> void:
	# `herdable` is per-animal data. A tame wolf is a different feature.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(wolf.herded_by, 0)
	assert_false(MoveCommand.new(1, [wolf.id] as Array[int], Vector2i(30, 30)).validate(w))


func test_you_may_still_slaughter_the_sheep_you_are_herding() -> void:
	# The consequence of herding not being owning, and the reason it is not: had the
	# sheep become yours, `AttackCommand` would refuse it and eating your own
	# livestock would have needed a command of its own.
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1)
	assert_true(AttackCommand.new(1, [villager.id] as Array[int], sheep.id).validate(w))


func test_a_slaughtered_sheep_leaves_the_food_it_was_carrying() -> void:
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	sheep.take_damage(9999, 0)
	_run(1)
	var carcass: SimResourceNode = null
	for e in w.entities.values():
		if e is SimResourceNode and (e as SimResourceNode).def_id == &"res.sheep_carcass":
			carcass = e
	assert_not_null(carcass)
	assert_eq(carcass.amount, 100, "the old res.sheep figure, unchanged")


func test_a_flock_cannot_keep_a_defeated_player_in_the_game() -> void:
	# What a real ownership transfer would have cost. `WinConditionSystem` counts
	# living units by owner, and a sheep is owner 0 however many players have herded
	# it -- so losing your last villager to a wolf really is losing.
	var sheep := w.spawn_unit(&"unit.sheep", 0, Vector2i(40, 40))
	w.spawn_unit(&"unit.villager", 1, Vector2i(41, 40))
	_run(HerdSystem.THINK_INTERVAL_TICKS + 1)
	assert_eq(sheep.herded_by, 1)
	assert_eq(sheep.owner_id, 0, "so it counts for nobody")


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
