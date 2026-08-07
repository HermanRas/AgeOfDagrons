## One entry from data/resources.json (PLAN.md 9). Phase 0.4.
##
## `amounts` is indexed by SimResourceNode.size_class (0 small, 1 medium,
## 2 large). The size classes are a DATA distinction, not a visual one: every
## size of gold mine draws the same sprite (ASSET_MISSING.md 1.3), so nothing
## here selects art per size.
class_name ResourceDef
extends RefCounted

var id: StringName = &""
## food | wood | gold | stone -- which stockpile a gathered load lands in.
var kind: StringName = &""
var visual: StringName = &""

## Starting amount per size class, small to large.
var amounts: Array[int] = []
## How many villagers can work this node at once.
var gather_slots: int = 1

## Wildlife only (the deer). Empty for inert nodes.
var is_wildlife: bool = false
var roam_radius: int = 0
var flees: bool = false


static func from_dict(p_id: StringName, d: Dictionary) -> ResourceDef:
	var r := ResourceDef.new()
	r.id = p_id
	r.kind = StringName(d.get("kind", ""))
	r.visual = StringName(d.get("visual", ""))
	r.amounts = GameDefs.int_list(d.get("amounts", []))
	r.gather_slots = int(d.get("gather_slots", 1))

	var w: Variant = d.get("wildlife")
	if w is Dictionary:
		r.is_wildlife = true
		r.roam_radius = int((w as Dictionary).get("roam_radius", 0))
		r.flees = bool((w as Dictionary).get("flees", false))
	return r


## Starting amount for a size class, clamped rather than out-of-range: a map
## generator asking for a size this resource does not define should get the
## nearest one, not crash the sim.
func amount_for(size_class: int) -> int:
	if amounts.is_empty():
		return 0
	return amounts[clampi(size_class, 0, amounts.size() - 1)]


func size_class_count() -> int:
	return amounts.size()
