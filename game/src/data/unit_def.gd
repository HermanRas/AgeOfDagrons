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

	var armor: Dictionary = d.get("armor", {})
	u.armor_melee = int(armor.get("melee", 0))
	u.armor_pierce = int(armor.get("pierce", 0))

	u.carry_cap = GameDefs.int_map(d.get("carry_cap", {}))
	u.gather_rate = GameDefs.int_map(d.get("gather_rate", {}))
	u.trainable_at = GameDefs.name_list(d.get("trainable_at", []))
	u.age_required = int(d.get("age_required", 1))
	return u


## Units gathered per tick, as the rate is authored per 100 ticks. Returns a
## float deliberately: rounding here would quietly make every gather rate under
## 100 collapse to zero.
func gather_per_tick(kind: StringName) -> float:
	return float(gather_rate.get(kind, 0)) / 100.0
