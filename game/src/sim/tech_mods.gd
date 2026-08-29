## What a player's researched technologies DO (PLAN.md 9.3). Phase 9.3.
##
## ## Why this is not a `SimSystem`
##
## PLAN.md's system table has listed a `TechSystem` — "research timers, stat
## modifiers" — as unbuilt since 0.4. The timers turned out not to need one: a
## research is an entry in the building's own production queue, which
## `ProductionSystem` has advanced one entry per tick since 5.4, and a second system
## ticking the same queue would be two owners of one counter. What was left is the
## modifiers, and those are a pure function of which techs a player holds — so this
## is a static resolver in the shape of `Formation` and `WallPlan`, not a per-tick
## pass over the world that would have nothing to do on 99.9% of ticks.
##
## ## The effect vocabulary
##
## An effect key is `stat.scope` and every stat names a lookup the sim ALREADY makes
## **per use** — `techs.json`'s own note carries the table and the reasoning. That is
## the load-bearing property: a tech never has to reach back and rewrite units that
## already exist, so there is no retroactivity pass, no "what happens to current hp",
## and no ordering question about a unit trained mid-research.
##
## `unit_hp`, `building_hp`, `speed` and `los` are the four obvious stats this does
## NOT offer, and `techs.json` records why each is harder than it looks.
##
## ## Determinism
##
## `SimPlayer.tech_mods` is summed here and folded into `state_hash()` by way of the
## sorted `researched` list it is derived from. Addition commutes, so the order techs
## are granted in cannot change the total — which is why `researched` is hashed and
## this is not.
class_name TechMods
extends RefCounted

## Scope for anything that applies to every unit its stat can reach.
const ALL := &"all"

## The two `UnitDef.attack_type` values, used as scopes by the attack lines so a
## tech's audience is read off data that already exists rather than off a unit
## class field the roster does not have.
const MELEE := &"melee"
const PIERCE := &"pierce"


## EVERY EFFECT KEY THE SIM ACTUALLY READS, and the reason it is a closed list: an
## effect nobody reads is a tech that silently does nothing, which is indistinguishable
## from a tech nobody has got round to. `GameDataRegistry.validate()` checks
## `techs.json` against this, so a mistyped `attack_damge.melee` fails the suite
## instead of costing a playtest.
##
## One entry per (stat, scope) pair that has a call site, NOT a cross product: there is
## no `attack_range.melee` because a melee unit's reach is the floor of 1
## `CombatSystem._within_reach` documents, and widening it would mean something quite
## different from widening an archer's.
const KNOWN_EFFECTS: Array[StringName] = [
	&"attack_damage.melee",
	&"attack_damage.pierce",
	&"attack_range.pierce",
	&"armor_melee.all",
	&"armor_pierce.all",
	&"carry_cap.all",
	&"gather_rate.food",
	&"gather_rate.wood",
	&"gather_rate.gold",
	&"gather_rate.stone",
	&"ability_amount.heal",
	&"ability_amount.damage",
]


## The effect key for one stat and scope. One function so a writer and a reader
## cannot spell the same effect two ways -- the keys are strings in JSON and a typo
## there is a tech that silently does nothing.
static func key(stat: StringName, scope: StringName) -> StringName:
	return StringName("%s.%s" % [stat, scope])


## Sum every researched tech's effects into one `stat.scope -> int` table.
##
## Rebuilt WHOLE rather than added to incrementally, and the cost is nothing: it runs
## once when a research completes, over a set that never exceeds the roster. An
## incremental version would be a second way for the same total to be reached, and
## the two would disagree the first time a tech was ever removed -- which nothing
## does today and `SimWorld.grant_tech`'s header does not promise never will.
static func sum(researched: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	# SORTED, so the traversal order does not depend on Dictionary insertion order.
	# Addition commutes so the TOTAL cannot differ either way -- this is here because
	# a future effect that is not a sum (a max, a multiply) would silently start
	# depending on it, and the sort costs nothing at this size.
	var ids: Array[String] = []
	for id in researched:
		if bool(researched[id]):
			ids.append(String(id))
	ids.sort()

	for id in ids:
		var t: TechDef = GameDataRegistry.tech(StringName(id)) if GameDataRegistry != null else null
		if t == null:
			continue
		for k in t.effects:
			out[StringName(k)] = int(out.get(StringName(k), 0)) + int(t.effects[k])
	return out


## One modifier off a summed table. 0 for anything not researched, which is what
## makes every call site a plain `base + mod` with no "has this player got techs at
## all" branch.
static func of(mods: Dictionary, stat: StringName, scope: StringName) -> int:
	return int(mods.get(key(stat, scope), 0))


## The attack/armour bonus a UNIT gets, or 0 for one that should not get it.
##
## **WORKERS ARE EXCLUDED, and this is the only place that says so.** A villager's
## `attack_type` is melee, so an unscoped Blast Furnace would take her from 3 damage
## to 7 and turn twenty villagers into an army — a real balance change hiding inside
## a smithing upgrade. AoE does not arm the peasants either. Resolved here rather
## than declared per tech in `techs.json`, because it is a fact about who the tech is
## FOR and would otherwise be twelve copies of one rule.
##
## A null def gets 0 rather than the `all` bonus: an unknown unit is a data error,
## and quietly handing it every upgrade in the game is the wrong way to fail.
static func for_unit(mods: Dictionary, def: UnitDef, stat: StringName) -> int:
	if def == null or def.is_worker():
		return 0
	return of(mods, stat, def.attack_type)


## The same question for a stat that applies to every unit regardless of how it
## fights — armour, carry capacity, build rate. Split from `for_unit` because the
## worker exclusion is exactly wrong here: a wheelbarrow is FOR the villager.
static func for_all(mods: Dictionary, stat: StringName) -> int:
	return of(mods, stat, ALL)


## A percentage effect applied to `base`, floored. Percent rather than a flat number
## for the rates, because +15 on a gather rate of 25 per 100 ticks would be a 60%
## improvement on wood and a 12% one on a field, and the tech means the same thing on
## both.
##
## INTEGER ARITHMETIC THROUGHOUT, for the reason `SimBuilding.attack_bonus` gives:
## the result is spent inside a state transition that has to be bit-identical on an
## ARM phone and an x86 host, so 25 * 115 / 100 is 28 and never 28.75.
static func scaled(base: int, percent: int) -> int:
	if percent == 0:
		return base
	return base * (100 + percent) / 100
