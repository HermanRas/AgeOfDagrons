## One entry from data/units.json (PLAN.md 9). Phase 0.4.
##
## A plain RefCounted, not a Resource and not a Node: these are read by `sim/`,
## which may not touch Node types (PLAN.md 4), and they are loaded from JSON
## rather than from .tres so the data stays diffable and hand-editable.
##
## Every field is read once at load and then treated as immutable. Runtime state
## belongs on SimUnit; a Def is what every instance of a kind shares.
class_name UnitDef
extends RefCounted

var id: StringName = &""
var name: String = ""
var visual: StringName = &""

var hp: int = 1
## Sub-units per tick (PLAN.md 6.2's SimUnit.speed), not pixels or tiles.
var speed: int = 0
var los: int = 0
var domain: StringName = &"land"
var pop_cost: int = 1

## kind -> amount. Absent kinds cost nothing.
var cost: Dictionary = {}
var build_time_ticks: int = 0

var attack_damage: int = 0
var attack_type: StringName = &"melee"
var attack_range: int = 0
var attack_cooldown_ticks: int = 0

## The VISUAL ID of what this unit throws, or `&""` for a unit that throws nothing
## (PLAN.md 4.13). A projectile has no def of its own -- there is nothing to say about
## an arrow beyond which sprite it is -- so this names `vis.projectile_arrow` directly
## and `SimWorld.spawn_projectile` uses it as both the def id and the visual.
##
## ABSENCE IS THE SWITCH, and it is a per-unit choice rather than a rule derived from
## `attack_range` or `attack_type`. Every melee unit correctly has none. So does the
## DRAGON, which is range 3 and type pierce and would have been given an arrow by any
## rule clever enough to infer one -- it breathes fire, there is no bake for that, and
## a dragon spitting arrows is worse than a dragon spitting nothing.
var attack_projectile: StringName = &""

var armor_melee: int = 0
var armor_pierce: int = 0

## resource kind -> units carried before returning to a drop-off.
var carry_cap: Dictionary = {}
## resource kind -> units gathered per 100 ticks.
var gather_rate: Dictionary = {}

var trainable_at: Array[StringName] = []

## The age its trainer must have reached before this unit appears in that
## building's train menu (PLAN.md 2.7). NOT an age skin -- a unit uses one actor
## in all four ages; this is purely a gate. It lives on the unit rather than as
## four per-age `trains` lists on each building, so an archery range's "archers
## from 2, crossbowmen from 3" is one number in one place.
var age_required: int = 1

## GAIA WILDLIFE (PLAN.md 4.13's hostile wolf). Present on a unit nobody trains,
## nobody owns and nobody pays population for -- the wolf today, the bear next.
##
## It lives on `UnitDef` rather than on `ResourceDef`, where `res.deer`'s long-dead
## `wildlife` block sits, because the two are answering opposite questions. A deer is
## a thing you HARVEST and so it is a resource node: static, no task, no path. A wolf
## is a thing that COMES AT YOU, which needs a task, a path, a facing and a cooldown --
## every one of which lives on `SimUnit` and none of which a node has. The audit that
## preceded this found the two capabilities sitting on disjoint classes with no shared
## interface, and that is still true; the wolf is simply on the other side of the line
## from the deer, and drops a node when it dies to get back across.
var is_wildlife: bool = false

## How far it looks for something to bite, as a Chebyshev radius in tiles. Nothing
## else in the game auto-acquires -- 4.13 rules it out for player units on purpose --
## so this number is the entire aggression of the thing.
var aggro_radius: int = 0

## The `res.*` node dropped where it dies, or `&""` for wildlife that leaves nothing.
## This is the hunt/kill/carcass flow 6.1a deferred, arriving for the predator rather
## than the deer, because a wolf has to be killed before it can be harvested and a
## deer never did.
var carcass_def: StringName = &""

## How far from where it was last settled a roaming animal will wander, in tiles, or 0
## for one that stands where it was put (PLAN.md 6.1b).
##
## THIS FIELD ALREADY EXISTED ON `ResourceDef` AND WAS READ BY NOTHING for months --
## `res.deer` declared `roam_radius: 6` and no system ever looked. It could not have:
## roaming needs `MovementSystem`, which moves `SimUnit` and skips nodes, so the data
## was on a class that was physically unable to act on it. Living here is what made it
## real, and the deer had to become a unit to get it.
var roam_radius: int = 0

## Whether being hurt makes it run (6.1b's "flee-and-relocate"). False for the three
## predators -- a wolf that bolted the first time a villager hit it would be a hazard
## nobody ever had to deal with.
var flees: bool = false


static func from_dict(p_id: StringName, d: Dictionary) -> UnitDef:
	var u := UnitDef.new()
	u.id = p_id
	u.name = str(d.get("name", String(p_id)))
	u.visual = StringName(d.get("visual", ""))

	u.hp = int(d.get("hp", 1))
	u.speed = int(d.get("speed", 0))
	u.los = int(d.get("los", 0))
	u.domain = StringName(d.get("domain", "land"))
	u.pop_cost = int(d.get("pop_cost", 1))

	u.cost = GameDefs.int_map(d.get("cost", {}))
	u.build_time_ticks = int(d.get("build_time_ticks", 0))

	var atk: Dictionary = d.get("attack", {})
	u.attack_damage = int(atk.get("damage", 0))
	u.attack_type = StringName(atk.get("type", "melee"))
	u.attack_range = int(atk.get("range", 0))
	u.attack_cooldown_ticks = int(atk.get("cooldown_ticks", 0))
	u.attack_projectile = StringName(atk.get("projectile", ""))

	var armor: Dictionary = d.get("armor", {})
	u.armor_melee = int(armor.get("melee", 0))
	u.armor_pierce = int(armor.get("pierce", 0))

	u.carry_cap = GameDefs.int_map(d.get("carry_cap", {}))
	u.gather_rate = GameDefs.int_map(d.get("gather_rate", {}))
	u.trainable_at = GameDefs.name_list(d.get("trainable_at", []))
	u.age_required = int(d.get("age_required", 1))

	var wild: Variant = d.get("wildlife")
	if wild is Dictionary:
		u.is_wildlife = true
		u.aggro_radius = int((wild as Dictionary).get("aggro_radius", 0))
		u.carcass_def = StringName((wild as Dictionary).get("carcass", ""))
		u.roam_radius = int((wild as Dictionary).get("roam_radius", 0))
		u.flees = bool((wild as Dictionary).get("flees", false))
	return u


## Units gathered per tick, as the rate is authored per 100 ticks. Returns a
## float deliberately: rounding here would quietly make every gather rate under
## 100 collapse to zero.
func gather_per_tick(kind: StringName) -> float:
	return float(gather_rate.get(kind, 0)) / 100.0


## Whether this unit works for a living -- true for the villager and nothing else
## in the v1 roster. The mirror of `BuildingDef.is_gatherable()`, and the same
## reason for existing: it is what the idle badge counts, and asking the DATA
## keeps `unit.villager` out of the view layer. A later fishing boat or trade
## cart earns its place in that count by carrying a gather rate, which is also
## the honest answer -- an idle economic unit is the mistake the badge is for,
## whatever it happens to be called.
func is_worker() -> bool:
	for kind in gather_rate:
		if int(gather_rate[kind]) > 0:
			return true
	return false
