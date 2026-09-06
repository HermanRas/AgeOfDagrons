## PLAN.md 13.2's claim, built as 13.2b: kill the mother, hold the nest, get a dragon.
##
## 13.2a put her and her nest on every generated map and killing her dropped nothing.
## What is exercised here is the rest of it -- `NestSystem`, the hatchling, the 360 s
## window, and the two ways a rival can deny it.
##
## ⚠️ **THE FIXTURE PLACES THE NEST WITH `force`, AND THE DEBUG MAP IS WHY.** 13.2a tried
## and failed to put a nest on `MatchConfig.debug_single_player()`'s fixed 64x64 board: a
## 10x10 patch of OCCUPIED ground is the largest obstacle that map has ever carried, and
## four unrelated test files scan it for clear ground (`test_walls`' own header records
## that assuming a clear strip there "cost two tests at once"). So the nest goes down here
## by force, in a corner nothing else uses, and nothing about that map changes for anybody
## else.
extends TestCase

const NEST_DEF := &"building.dragon_nest"
const BABY_DEF := &"unit.dragon_baby"

## Far enough from the debug map's town centre and its villagers that no other rule --
## `WildlifeSystem`'s settlement retreat, a tower's reach, `SeparationSystem` -- has an
## opinion about anything this file does.
const NEST_ORIGIN := Vector2i(46, 46)

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


## A nest and its gaia mother, ready to be killed. Returns [nest, mother].
##
## SHE IS PUT ONE TILE OFF THE FOOTPRINT, exactly as `MapGenerator._place_guardian` does
## it and for the reason recorded there: a unit sharing a tile with a building is an
## overlap `MapValidator` rejects, so a guardian cannot stand ON the thing she guards.
func _nest_and_mother() -> Array:
	var nest := w.spawn_building(NEST_DEF, 0, NEST_ORIGIN,
			SimBuilding.Phase.COMPLETE, true)
	var mother := w.spawn_unit(&"unit.dragon", 0, NEST_ORIGIN + Vector2i(-1, 5))
	return [nest, mother]


func _run(ticks: int) -> void:
	for i in range(ticks):
		w.step()


## Everything alive of one def, which is how this file counts hatchlings and dragons
## without caring what id they were given.
func _count(def_id: StringName) -> int:
	var n := 0
	for e in w.entities.values():
		if e is SimUnit and e.def_id == def_id and e.alive:
			n += 1
	return n


func _first(def_id: StringName) -> SimUnit:
	for e in w.entities.values():
		if e is SimUnit and e.def_id == def_id and e.alive:
			return e
	return null


# ── the claim opens ────────────────────────────────────────────────────────

func test_killing_the_mother_leaves_a_hatchling_at_the_nest() -> void:
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	var mother: SimUnit = pair[1]
	assert_eq(_count(BABY_DEF), 0, "nothing before she dies")

	mother.take_damage(9999, 0, 1)
	w.step()

	var baby := _first(BABY_DEF)
	assert_not_null(baby, "her death drops a hatchling")
	# AT THE NEST'S CENTRE, not at the tile she happened to fall on. The prize belongs
	# to the place, which is the whole reason the nest is the thing a rival attacks.
	assert_eq(baby.tile(), nest.tile(), "it hatches in the nest, not where she fell")
	assert_eq(nest.claim_baby_id, baby.id)


func test_the_hatchling_is_gaias_and_the_claim_is_only_recorded() -> void:
	# ⚠️ THE POINT OF THE WHOLE DESIGN. PLAN.md 13.2 gives the GROWN dragon to the
	# claimant; handing the baby over now would let player 1 walk it out of reach and
	# there would be nothing left to hold and nothing for a rival to deny.
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()

	assert_eq(_first(BABY_DEF).owner_id, 0, "the hatchling is gaia's until it grows")
	assert_eq(nest.claim_owner, 1, "and the claim is a note on the nest")


func test_a_mother_killed_by_nothing_traceable_drops_nothing() -> void:
	# A debug destroy, a scuttled transport, a building falling on her. Nobody killed
	# her, so nobody claims her -- and `NO_ATTACKER` is what says so.
	var pair := _nest_and_mother()
	(pair[1] as SimUnit).take_damage(9999, 0, SimEntity.NO_ATTACKER)
	_run(3)
	assert_eq(_count(BABY_DEF), 0)
	assert_eq((pair[0] as SimBuilding).claim_owner, 0, "and the nest is still unclaimed")


func test_gaia_cannot_claim_a_dragon_from_itself() -> void:
	# ⚠️ 0 IS A REAL ATTACKER EVERYWHERE ELSE IN THE SIM -- a wolf killing a villager is
	# owner 0 landing a blow -- which is exactly why `NO_ATTACKER` is -1 and not 0, and
	# why `NestSystem` tests `> 0` rather than `!= NO_ATTACKER`. Getting this wrong gives
	# the wilderness a dragon.
	var pair := _nest_and_mother()
	(pair[1] as SimUnit).take_damage(9999, 0, 0)
	_run(3)
	assert_eq(_count(BABY_DEF), 0)


func test_an_ordinary_animal_dying_at_the_nest_claims_nothing() -> void:
	# `guards_post` is the switch and not "a gaia unit died nearby". A wolf shot beside
	# the henge must not hatch a dragon.
	var pair := _nest_and_mother()
	var wolf := w.spawn_unit(&"unit.wolf", 0, NEST_ORIGIN + Vector2i(2, 2))
	wolf.take_damage(9999, 0, 1)
	_run(3)
	assert_eq(_count(BABY_DEF), 0)
	assert_eq((pair[0] as SimBuilding).claim_owner, 0)


# ── the claim matures ──────────────────────────────────────────────────────

func test_the_hatchling_becomes_the_killers_dragon_after_the_window() -> void:
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()
	var at := _first(BABY_DEF).tile()

	_run(NestSystem.GROW_TICKS)

	assert_eq(_count(BABY_DEF), 0, "the hatchling is gone")
	var grown := _first(&"unit.dragon")
	assert_not_null(grown, "and a dragon stands in its place")
	assert_eq(grown.owner_id, 1, "owned by whoever killed the mother")
	assert_eq(grown.tile(), at, "at the nest it grew in")
	assert_eq(nest.claim_ticks_left, -1, "and the countdown is spent")


func test_it_is_still_a_hatchling_the_tick_before() -> void:
	# The half of a timer nobody writes a test for, and the half that catches an
	# off-by-one paying out early -- which on a 3600-tick window nobody would notice.
	_nest_and_mother()
	(_first(&"unit.dragon") as SimUnit).take_damage(9999, 0, 1)
	w.step()

	_run(NestSystem.GROW_TICKS - 1)
	assert_eq(_count(BABY_DEF), 1, "still growing")
	w.step()
	assert_eq(_count(BABY_DEF), 0, "and grown on the next tick")


func test_the_grown_dragon_is_a_real_dragon_and_not_a_re_owned_hatchling() -> void:
	# ⚠️ THE HATCHLING IS REPLACED, NOT RELABELLED. Mutating `def_id` and `owner_id` in
	# place would leave a 300 hp dragon that cannot fly: hp, armour, speed, domain and
	# pop cost are all copied off the def by `spawn_unit` and by nothing else.
	_nest_and_mother()
	(_first(&"unit.dragon") as SimUnit).take_damage(9999, 0, 1)
	w.step()
	_run(NestSystem.GROW_TICKS)

	var grown := _first(&"unit.dragon")
	var def := w.unit_def(&"unit.dragon")
	assert_eq(grown.hp, def.hp, "full dragon health, not the hatchling's")
	assert_eq(grown.speed, def.speed, "and it can fly")
	assert_true(grown.speed > 0, "a dragon that cannot move is the bug this pins")


func test_a_nest_gives_up_one_dragon_and_only_one() -> void:
	# ⚠️ `claim_owner` IS NEVER CLEARED, and this is what that buys. PLAN.md 13.2's "one
	# dragon per map" was 13.2a's placement rule; this is the other half of it -- a
	# second guardian dying at the same nest, for any reason, claims nothing.
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()
	_run(NestSystem.GROW_TICKS)
	assert_eq(_count(&"unit.dragon"), 1, "one claim paid out")

	var second := w.spawn_unit(&"unit.dragon", 0, NEST_ORIGIN + Vector2i(-1, 5))
	second.roam_home = nest.tile()
	second.take_damage(9999, 0, 2)
	_run(3)
	assert_eq(_count(BABY_DEF), 0, "the nest has nothing left to give")
	assert_eq(nest.claim_owner, 1, "and the record still names the first claimant")


# ── the claim is denied ────────────────────────────────────────────────────

func test_razing_the_nest_kills_the_hatchling() -> void:
	# PLAN.md 13.2's headline rule, and what makes 1200 hp of stone a target rather than
	# scenery: "killing it kills the baby, so a claim must be HELD and a rival can deny
	# it."
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()
	assert_eq(_count(BABY_DEF), 1)

	nest.take_damage(9999, 0, 2)
	_run(3)
	assert_eq(_count(BABY_DEF), 0, "the hatchling dies with the nest")

	_run(NestSystem.GROW_TICKS)
	assert_eq(_count(&"unit.dragon"), 0, "and nobody ever gets the dragon")


func test_killing_the_hatchling_denies_the_claim_by_the_shorter_road() -> void:
	# The other denial, which needs no rule of its own: a claim with nothing left to
	# mature simply does not.
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()

	(_first(BABY_DEF) as SimUnit).take_damage(9999, 0, 2)
	_run(3)
	assert_eq(nest.claim_ticks_left, -1, "the countdown is abandoned")
	_run(NestSystem.GROW_TICKS)
	assert_eq(_count(&"unit.dragon"), 0)


func test_the_hatchling_is_no_pushover_and_the_nest_is_the_softer_target() -> void:
	# ⚠️ THIS IS THE BALANCE OF THE WHOLE FEATURE AND IT IS A PAIR OF NUMBERS, NOT A
	# RULE. If a hatchling died to four spearmen, nobody would ever raze 1200 hp of
	# stone and PLAN.md's headline denial would be decorative -- the "a declared row in
	# a table is indistinguishable from a working one" trap 13.1 already paid for.
	#
	# ASSERTED AS AN ORDERING RATHER THAN AS FIGURES, because both are provisional and
	# want the owner's eye. What must survive a retune is that a militia's swing is
	# blunted to the floor while the nest takes it whole.
	var baby := GameDataRegistry.unit(BABY_DEF)
	var militia := GameDataRegistry.unit(&"unit.militia")
	var nest := GameDataRegistry.building(NEST_DEF)
	assert_true(baby.armor_melee >= militia.attack_damage,
			"a militia should be chipping at the hatchling, not butchering it")
	assert_true(nest.hp > baby.hp,
			"the nest is the bigger job in hp -- and the one that takes full damage")


func test_a_defeated_claimant_is_paid_nothing() -> void:
	# ⚠️ THE CASE THAT WOULD HAVE UN-ENDED A FINISHED MATCH. `WinConditionSystem` decides
	# who is standing by counting what a player OWNS, so a dragon handed to somebody
	# knocked out four minutes ago puts them back on the board -- 360 s after anyone was
	# still watching. Reachable by killing the mother and then losing inside six minutes.
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()
	assert_eq(_count(BABY_DEF), 1)

	w.player_for(1).defeat(SimPlayer.Defeat.RESIGNED)
	_run(3)
	assert_eq(_count(BABY_DEF), 0, "the hatchling goes with the claim")
	_run(NestSystem.GROW_TICKS)
	assert_eq(_count(&"unit.dragon"), 0, "and no dragon arrives for a dead player")


# ── the hatchling itself ───────────────────────────────────────────────────

func test_the_hatchling_neither_wanders_nor_fights() -> void:
	# Both are zeros in `units.json` and both are load-bearing: `WildlifeSystem._roam`
	# returns on radius 0 and `_hunt` is skipped on aggro 0, so the hatchling needs no
	# rule of its own and no exception in that file. A prize that wandered off would take
	# the contest with it.
	var def := GameDataRegistry.unit(BABY_DEF)
	assert_true(def.is_wildlife, "wildlife, which is how it is exempt from 'trains nowhere'")
	assert_eq(def.roam_radius, 0)
	assert_eq(def.aggro_radius, 0)
	assert_false(def.guards_post, "a post is for an animal that patrols one")
	assert_eq(def.carcass_def, &"", "denying a claim does not feed you")
	assert_true(def.trainable_at.is_empty(), "nobody trains a hatchling either")


func test_the_hatchling_stays_where_it_hatched() -> void:
	_nest_and_mother()
	(_first(&"unit.dragon") as SimUnit).take_damage(9999, 0, 1)
	w.step()
	var baby := _first(BABY_DEF)
	var at := baby.tile()
	_run(WildlifeSystem.THINK_INTERVAL_TICKS * 5)
	assert_eq(baby.tile(), at, "still in the nest")


func test_an_orphaned_hatchling_does_not_outlive_its_nest() -> void:
	# The sweep, and what it defends against is a LINK breaking rather than a rule: a
	# nest removed by any route other than falling would otherwise leave a hatchling
	# standing in an empty field, gaia's, growing into nothing.
	var pair := _nest_and_mother()
	(pair[1] as SimUnit).take_damage(9999, 0, 1)
	w.step()
	assert_eq(_count(BABY_DEF), 1)

	w.despawn((pair[0] as SimBuilding).id)
	_run(3)
	assert_eq(_count(BABY_DEF), 0)


# ── rubble, or the lack of it ──────────────────────────────────────────────

func test_a_razed_nest_is_gone_rather_than_standing_there_looking_fine() -> void:
	# ⚠️ `visual_rubble` POINTS AT THE NEST ITSELF -- there is no rubble bake and a razed
	# henge is an absence rather than a pile. Left as rubble, the rival who had just
	# successfully denied a claim would watch an apparently untouched nest for a full
	# minute, which is the most misleading frame this feature could produce.
	var pair := _nest_and_mother()
	var nest: SimBuilding = pair[0]
	nest.take_damage(9999, 0, 2)
	w.step()
	assert_null(w.get_entity(nest.id), "the nest goes on the tick it falls")


func test_everything_else_still_leaves_its_rubble() -> void:
	# The flag defaults true, and this is the assertion that keeps `leaves_rubble` from
	# being read as "buildings stopped leaving rubble". One def carries it; 31 do not.
	var house := w.spawn_building(&"building.house", 1, Vector2i(20, 20),
			SimBuilding.Phase.COMPLETE, true)
	house.take_damage(9999, 0, 2)
	w.step()
	assert_not_null(w.get_entity(house.id), "a house is wreckage for a minute")
	assert_eq(house.phase, SimBuilding.Phase.DESTROYED)

	var missing := 0
	for id in GameDataRegistry.building_ids():
		if not GameDataRegistry.building(id).leaves_rubble:
			missing += 1
	assert_eq(missing, 1, "exactly one building in the roster has no rubble, and it is the nest")
	assert_false(GameDataRegistry.building(NEST_DEF).leaves_rubble)


# ── who hit me ─────────────────────────────────────────────────────────────

func test_a_blow_records_its_owner_and_a_consequence_does_not() -> void:
	# The plumbing the claim needed, asserted on its own rather than only through a
	# dragon: `WildlifeSystem._check_flee` works by watching hp precisely because
	# `take_damage` used to be handed a number and no attacker.
	var target := w.spawn_unit(&"unit.villager", 1, Vector2i(30, 30))
	assert_eq(target.last_attacker_owner, SimEntity.NO_ATTACKER, "nothing has hit it yet")
	target.take_damage(1, 0, 2)
	assert_eq(target.last_attacker_owner, 2)
	target.take_damage(1, 0, SimEntity.NO_ATTACKER)
	assert_eq(target.last_attacker_owner, 2,
			"an untraceable hit does not erase who was actually fighting it")


func test_no_attacker_is_not_gaia() -> void:
	# One line, and it is the difference between "nobody killed her" and "the wilderness
	# killed her". Every rule downstream reads owner 0 as a real player.
	assert_ne(SimEntity.NO_ATTACKER, 0)
	assert_true(SimEntity.NO_ATTACKER < 0)


func test_a_soldiers_swing_credits_the_soldiers_owner() -> void:
	# Through the real `CombatSystem` rather than by calling `take_damage` by hand,
	# because the call site is the half that can be forgotten -- and a required argument
	# only helps against a call site that is not written, not against one given the wrong
	# value.
	#
	# NOBODY ORDERS THE FIGHT and nobody has to: a military unit defaults to DEFENSIVE
	# (4.12) and a wolf is at war with everybody. This is the fixture shape §6 warns
	# about ("two hostile units near each other and expects nothing to happen") used
	# deliberately, for once, because a fight starting on its own IS the thing under test.
	var wolf := w.spawn_unit(&"unit.wolf", 0, Vector2i(30, 30))
	w.spawn_unit(&"unit.militia", 1, Vector2i(30, 31))
	_run(40)
	assert_eq(wolf.last_attacker_owner, 1, "the militia's owner, off a real exchange")
	assert_true(wolf.hp < wolf.max_hp, "and it really was hit")
