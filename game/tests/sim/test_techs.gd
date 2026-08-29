## Phase 9.3: technologies are bought at a building, and they change the numbers.
##
## Driven through the real `SimWorld.step()` rather than by calling `grant_tech`
## everywhere, because the part worth testing is that a research is an ordinary
## production-queue entry -- it competes for the one line, it refunds on cancel, and
## it lands through `ProductionSystem` on the tick its counter runs out. The effects
## are then asserted at the systems that read them, since an effect nobody reads is
## exactly the failure mode `GameDataRegistry.validate` was extended to catch.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = SimWorld.new()
	w.setup(MatchConfig.debug_single_player())


## Ages gate half the roster, and every tech worth testing is age 2 or later. Set
## directly rather than through `AdvanceAgeCommand`, which would cost a research timer
## per age and is 9.2's test's job, not this one's.
func _age(n: int) -> void:
	w.player_for(1).age = n


func _rich() -> void:
	for kind in [&"food", &"wood", &"gold", &"stone"]:
		w.player_for(1).stock[kind] = 5000


func _blacksmith() -> SimBuilding:
	_age(2)
	_rich()
	return w.spawn_building(&"building.blacksmith", 1, Vector2i(30, 30))


func _research(b: SimBuilding, tech: StringName) -> ResearchCommand:
	return ResearchCommand.new(1, b.id, tech)


## Run until `tech` is held, or give up. Returns whether it landed, so a test can say
## which of the two it meant rather than looping and asserting nothing.
func _run_until_researched(tech: StringName, budget: int = 800) -> bool:
	for i in range(budget):
		w.step()
		if w.player_for(1).has_tech(tech):
			return true
	return false


# ── the data itself ─────────────────────────────────────────────────────────

func test_every_tech_is_reachable_from_the_building_that_offers_it() -> void:
	# The check `validate()` cannot make, because it is about the MENU: a tech whose
	# building is not in `techs_at` has a home in the data and no button in the game.
	var seen := 0
	for id in GameDataRegistry.tech_ids():
		var t: TechDef = GameDataRegistry.tech(id)
		for b in t.researched_at:
			assert_true(GameDataRegistry.techs_at(b).has(id),
					"%s is offered by %s and appears in its menu" % [id, b])
			seen += 1
	assert_true(seen >= 20, "the roster is populated, not two placeholder entries")


func test_a_prerequisite_is_never_bought_at_a_different_building() -> void:
	# A ladder split across two buildings is legal in the schema and is a trap in play:
	# the second rung would sit greyed at the blacksmith naming a tech the blacksmith
	# does not sell, with nothing on the tile to say where it is.
	for id in GameDataRegistry.tech_ids():
		var t: TechDef = GameDataRegistry.tech(id)
		for req in t.requires:
			var r: TechDef = GameDataRegistry.tech(req)
			assert_eq(r.researched_at, t.researched_at,
					"%s and its prerequisite %s are bought in the same place" % [id, req])


# ── buying one ──────────────────────────────────────────────────────────────

func test_a_research_is_queued_paid_for_and_lands_on_its_own_tick() -> void:
	var b := _blacksmith()
	var t: TechDef = GameDataRegistry.tech(&"tech.forging")
	var before := int(w.player_for(1).stock[&"food"])

	w.queue_command(_research(b, &"tech.forging"))
	w.step()
	assert_eq(b.queue.size(), 1, "it is on the building's own production queue")
	assert_eq(int(w.player_for(1).stock[&"food"]), before - int(t.cost[&"food"]),
			"and was paid for when it was ordered, not when it finished")
	assert_false(w.player_for(1).has_tech(&"tech.forging"), "not yet held")

	assert_true(_run_until_researched(&"tech.forging"), "it completes")
	assert_true(b.queue.is_empty(), "and leaves the queue")


func test_a_cancelled_research_refunds_exactly_what_it_cost() -> void:
	# `CancelProductionCommand` never asks what kind an entry is -- it refunds the
	# `cost` recorded on it. This is what pins that a tech records one.
	var b := _blacksmith()
	var before := int(w.player_for(1).stock[&"food"])
	w.queue_command(_research(b, &"tech.forging"))
	w.step()
	w.step()
	w.queue_command(CancelProductionCommand.new(1, b.id, 0))
	w.step()

	assert_true(b.queue.is_empty())
	assert_eq(int(w.player_for(1).stock[&"food"]), before, "whole, despite two ticks of work")
	assert_false(w.player_for(1).has_tech(&"tech.forging"))


func test_research_and_training_share_the_one_production_line() -> void:
	# A town centre can do both, and it is the only building that can. Genre-standard,
	# and it falls out of research sharing the queue rather than being a rule.
	_age(2)
	_rich()
	var tc := w.spawn_building(&"building.town_center", 1, Vector2i(10, 10))
	w.queue_command(_research(tc, &"tech.wheelbarrow"))
	w.queue_command(TrainCommand.new(1, tc.id, &"unit.villager"))
	w.step()

	assert_eq(tc.queue.size(), 2, "both are on it")
	assert_eq(tc.queue[0]["kind"], SimBuilding.KIND_TECH, "the research is in front")
	assert_eq(tc.queue[1]["kind"], SimBuilding.KIND_UNIT)


# ── what is refused ─────────────────────────────────────────────────────────

func test_a_tech_is_refused_at_a_building_that_does_not_offer_it() -> void:
	_age(4)
	_rich()
	var house := w.spawn_building(&"building.house", 1, Vector2i(40, 40))
	assert_false(_research(house, &"tech.forging").validate(w),
			"a house does not sell Blast Furnace, whatever the client says")


func test_a_tech_above_the_owners_age_is_refused() -> void:
	var b := _blacksmith()          # age 2
	assert_true(_research(b, &"tech.forging").validate(w))
	assert_false(_research(b, &"tech.iron_casting").validate(w),
			"Iron Casting is age 3 and the menu is only the courtesy half")


func test_a_tech_whose_prerequisite_is_missing_is_refused() -> void:
	var b := _blacksmith()
	_age(3)
	assert_false(_research(b, &"tech.iron_casting").validate(w),
			"Forging first")
	w.grant_tech(1, &"tech.forging")
	assert_true(_research(b, &"tech.iron_casting").validate(w))


## THE DOUBLE TAP, which is the expensive one: research takes up to a minute, so a
## second copy would complete against a tech already held and refund nothing.
func test_a_tech_already_in_the_queue_cannot_be_ordered_twice() -> void:
	var b := _blacksmith()
	w.queue_command(_research(b, &"tech.forging"))
	w.step()
	assert_false(_research(b, &"tech.forging").validate(w))


func test_a_tech_already_held_cannot_be_bought_again() -> void:
	var b := _blacksmith()
	w.grant_tech(1, &"tech.forging")
	assert_false(_research(b, &"tech.forging").validate(w))


func test_a_foundation_researches_nothing() -> void:
	_age(2)
	_rich()
	var b := w.spawn_building(&"building.blacksmith", 1, Vector2i(30, 30),
			SimBuilding.Phase.FOUNDATION)
	assert_false(_research(b, &"tech.forging").validate(w))


func test_somebody_elses_blacksmith_researches_nothing_for_you() -> void:
	var b := _blacksmith()
	b.owner_id = 2
	assert_false(_research(b, &"tech.forging").validate(w))


func test_a_tech_that_cannot_be_afforded_is_refused() -> void:
	var b := _blacksmith()
	w.player_for(1).stock[&"food"] = 0
	assert_false(_research(b, &"tech.forging").validate(w))


# ── the effects, at the systems that read them ──────────────────────────────

func test_forging_puts_damage_on_a_soldier_and_not_on_a_villager() -> void:
	# The worker exclusion is the one balance decision inside `TechMods`, and it is
	# invisible in the data -- a villager's attack_type is melee like a swordsman's.
	_age(2)
	var soldier := w.spawn_unit(&"unit.swordsman", 1, Vector2i(20, 20))
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(21, 20))
	var enemy := w.spawn_unit(&"unit.militia", 2, Vector2i(22, 20))

	var mods_before := w.mods_of(1)
	var soldier_def := w.unit_def(soldier.def_id)
	var villager_def := w.unit_def(villager.def_id)
	assert_eq(TechMods.for_unit(mods_before, soldier_def, &"attack_damage"), 0)

	w.grant_tech(1, &"tech.forging")
	assert_eq(TechMods.for_unit(w.mods_of(1), soldier_def, &"attack_damage"), 1,
			"the swordsman swings harder")
	assert_eq(TechMods.for_unit(w.mods_of(1), villager_def, &"attack_damage"), 0,
			"the villager does not -- twenty villagers are not an army")
	assert_true(enemy.alive, "nothing was actually hit; this is about the lookup")


func test_the_melee_ladder_stacks_and_lands_on_a_real_blow() -> void:
	_age(4)
	var attacker := w.spawn_unit(&"unit.swordsman", 1, Vector2i(20, 20))
	var target := w.spawn_unit(&"unit.militia", 2, Vector2i(21, 20))
	var def := w.unit_def(attacker.def_id)
	var base := CombatSystem._damage_against(w, attacker, target, def)

	for tech in [&"tech.forging", &"tech.iron_casting", &"tech.blast_furnace"]:
		w.grant_tech(1, tech)
	assert_eq(CombatSystem._damage_against(w, attacker, target, def), base + 4,
			"1 + 1 + 2 over three ages")


func test_armour_techs_blunt_every_kind_of_blow_including_an_ability() -> void:
	# One function carries armour for a sword, a tower volley and a dragon's breath,
	# which is why the armour half of the tech went there and the attack half did not.
	#
	# The DEFENDER's owner is what is asked, and the defender here belongs to player 1
	# -- `debug_single_player()` has exactly one player, so a target owned by 2 would
	# have no `SimPlayer` to hold a tech and this would pass by measuring nothing.
	_age(3)
	var target := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var base := CombatSystem._damage_after_armour(w, target, 20, &"melee")
	w.grant_tech(1, &"tech.scale_mail")
	assert_eq(CombatSystem._damage_after_armour(w, target, 20, &"melee"), base - 1)
	# And the pierce ladder is separate: scale mail does nothing against arrows.
	var pierce := CombatSystem._damage_after_armour(w, target, 20, &"pierce")
	w.grant_tech(1, &"tech.padded_armour")
	assert_eq(CombatSystem._damage_after_armour(w, target, 20, &"pierce"), pierce - 1)


func test_a_villager_IS_protected_by_armour_even_though_she_is_not_armed() -> void:
	# The deliberate asymmetry: `for_unit` excludes workers and `for_all` does not.
	_age(2)
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var base := CombatSystem._damage_after_armour(w, villager, 20, &"melee")
	w.grant_tech(1, &"tech.scale_mail")
	assert_eq(CombatSystem._damage_after_armour(w, villager, 20, &"melee"), base - 1)


func test_ballistics_widens_an_archers_reach_and_leaves_a_swordsman_alone() -> void:
	_age(3)
	var archer := w.spawn_unit(&"unit.archer", 1, Vector2i(20, 20))
	var sword := w.spawn_unit(&"unit.swordsman", 1, Vector2i(21, 20))
	var archer_def := w.unit_def(archer.def_id)
	var sword_def := w.unit_def(sword.def_id)

	assert_eq(CombatSystem.reach_of(w, archer, archer_def), archer_def.attack_range)
	w.grant_tech(1, &"tech.ballistics")
	assert_eq(CombatSystem.reach_of(w, archer, archer_def), archer_def.attack_range + 1)
	assert_eq(CombatSystem.reach_of(w, sword, sword_def), sword_def.attack_range,
			"there is no attack_range.melee, and melee reach is a floor of 1 anyway")


func test_a_gathering_tech_speeds_up_both_a_tree_and_a_field() -> void:
	# The mill ladder and the field's per-age yield are two numbers behind one function,
	# and Horse Collar has to move both -- a mill upgrade that improved hand-gathered
	# food and not the farm would be a rule nobody could guess.
	_age(2)
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var bush := w.spawn_resource_node(&"res.berry_bush", Vector2i(21, 20))
	var field := w.spawn_building(&"building.field", 1, Vector2i(40, 40))

	var bush_before := GatherSystem.harvest_rate(w, bush, villager, &"food")
	var field_before := GatherSystem.harvest_rate(w, field, villager, &"food")
	assert_true(bush_before > 0 and field_before > 0, "both yield something to start with")

	w.grant_tech(1, &"tech.horse_collar")
	assert_eq(GatherSystem.harvest_rate(w, bush, villager, &"food"),
			bush_before * 115 / 100, "+15% on the bush")
	assert_eq(GatherSystem.harvest_rate(w, field, villager, &"food"),
			field_before * 115 / 100, "and the same +15% on the crop")


func test_a_wood_tech_does_nothing_to_food() -> void:
	_age(2)
	var villager := w.spawn_unit(&"unit.villager", 1, Vector2i(20, 20))
	var bush := w.spawn_resource_node(&"res.berry_bush", Vector2i(21, 20))
	var before := GatherSystem.harvest_rate(w, bush, villager, &"food")
	w.grant_tech(1, &"tech.double_bit_axe")
	assert_eq(GatherSystem.harvest_rate(w, bush, villager, &"food"), before)


func test_sanctity_heals_harder_and_leaves_the_dragons_breath_alone() -> void:
	# Scoped by the ABILITY's effect, not by the unit -- a monastery tech that made
	# fire breath hotter is not what "Sanctity" means.
	_age(3)
	var monk := w.unit_def(&"unit.monk")
	var dragon := w.unit_def(&"unit.dragon")
	assert_eq(TechMods.of(w.mods_of(1), &"ability_amount", monk.ability_effect), 0)

	w.grant_tech(1, &"tech.sanctity")
	assert_eq(TechMods.of(w.mods_of(1), &"ability_amount", monk.ability_effect), 3)
	assert_eq(TechMods.of(w.mods_of(1), &"ability_amount", dragon.ability_effect), 0)


func test_the_wheelbarrow_only_widens_a_cap_that_already_exists() -> void:
	# `carry_cap.all` is a flat addition applied where the def declares a cap for that
	# kind, so it cannot hand a soldier a stone allowance he never had.
	_age(2)
	w.grant_tech(1, &"tech.wheelbarrow")
	assert_eq(TechMods.for_all(w.mods_of(1), &"carry_cap"), 3)
	var sword := w.unit_def(&"unit.swordsman")
	assert_true(sword.carry_cap.is_empty(), "a swordsman carries nothing to begin with")


# ── bookkeeping ─────────────────────────────────────────────────────────────

func test_granting_the_same_tech_twice_does_not_double_it() -> void:
	# `grant_tech` is idempotent on purpose: validation happens when the command lands
	# and completion up to a minute later, so two copies that both slipped through must
	# not be worth two upgrades.
	w.grant_tech(1, &"tech.forging")
	var once := w.mods_of(1).duplicate()
	w.grant_tech(1, &"tech.forging")
	assert_eq(w.mods_of(1), once)


func test_an_unknown_tech_is_not_granted() -> void:
	w.grant_tech(1, &"tech.does_not_exist")
	assert_false(w.player_for(1).has_tech(&"tech.does_not_exist"))
	assert_true(w.mods_of(1).is_empty())


func test_a_players_techs_are_their_own() -> void:
	w.grant_tech(1, &"tech.forging")
	assert_true(w.player_for(1).has_tech(&"tech.forging"))
	var other := w.player_for(2)
	if other != null:
		assert_false(other.has_tech(&"tech.forging"))
	assert_true(w.mods_of(0).is_empty(), "and gaia has none, with no null to guard")


func test_researched_ids_are_sorted_by_content() -> void:
	# `Array[StringName].sort()` orders by identity, which is arbitrary and not stable
	# between runs -- and this list is in `state_hash()`, so an unstable order is a
	# desync. `researched_ids()` returns Strings for exactly that reason.
	for tech in [&"tech.scale_mail", &"tech.forging", &"tech.padded_armour"]:
		w.grant_tech(1, tech)
	assert_eq(w.player_for(1).researched_ids(),
			["tech.forging", "tech.padded_armour", "tech.scale_mail"] as Array[String])


func test_a_researched_tech_is_in_the_state_hash() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	assert_eq(w.state_hash(), other.state_hash(), "identical to start with")
	w.grant_tech(1, &"tech.forging")
	assert_ne(w.state_hash(), other.state_hash(),
			"two hosts that disagree about one tech disagree about every blow after it")


func test_two_worlds_researching_the_same_thing_stay_identical() -> void:
	var other := SimWorld.new()
	other.setup(MatchConfig.debug_single_player())
	for entry in [w, other]:
		var world: SimWorld = entry
		world.player_for(1).age = 2
		for kind in [&"food", &"wood", &"gold", &"stone"]:
			world.player_for(1).stock[kind] = 5000
		var b := world.spawn_building(&"building.blacksmith", 1, Vector2i(30, 30))
		world.queue_command(ResearchCommand.new(1, b.id, &"tech.forging"))

	for i in range(340):
		w.step()
		other.step()
		assert_eq(w.state_hash(), other.state_hash(), "diverged on tick %d" % (i + 1))
	assert_true(w.player_for(1).has_tech(&"tech.forging"), "and it actually landed")


func test_a_research_survives_the_wire() -> void:
	var sent := ResearchCommand.new(3, 77, &"tech.bow_saw", 12)
	var back := Command.from_dict(JSON.parse_string(JSON.stringify(sent.to_dict())))
	assert_true(back is ResearchCommand)
	assert_eq((back as ResearchCommand).building_id, 77)
	assert_eq((back as ResearchCommand).tech_id, &"tech.bow_saw")
	assert_eq(back.player_id, 3)
