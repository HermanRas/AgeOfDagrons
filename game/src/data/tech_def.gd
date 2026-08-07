## One entry from data/techs.json (PLAN.md 9). Phase 0.4.
##
## Near-empty by design: TechSystem is phase 9.3 and no tech is in MVP scope
## (PLAN.md 10). This exists now so the registry loads the full set of data files
## from day one and 9.3 is a data change plus a system, not a schema change.
class_name TechDef
extends RefCounted

var id: StringName = &""
var name: String = ""
var cost: Dictionary = {}
var research_time_ticks: int = 0
var researched_at: Array[StringName] = []
var age_required: int = 1
## Tech IDs that must be researched first.
var requires: Array[StringName] = []
## Free-form stat modifiers, applied by TechSystem at 9.3. Left untyped until
## that phase decides the modifier vocabulary -- inventing one now would be
## guessing at a design that has not been done.
var effects: Dictionary = {}


static func from_dict(p_id: StringName, d: Dictionary) -> TechDef:
	var t := TechDef.new()
	t.id = p_id
	t.name = str(d.get("name", String(p_id)))
	t.cost = GameDefs.int_map(d.get("cost", {}))
	t.research_time_ticks = int(d.get("research_time_ticks", 0))
	t.researched_at = GameDefs.name_list(d.get("researched_at", []))
	t.age_required = int(d.get("age_required", 1))
	t.requires = GameDefs.name_list(d.get("requires", []))
	t.effects = d.get("effects", {})
	return t
