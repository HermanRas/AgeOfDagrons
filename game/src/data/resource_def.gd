## One entry from data/resources.json (PLAN.md 9). Phase 0.4.
##
## `amounts` is indexed by SimResourceNode.size_class (0 small, 1 medium,
## 2 large), and since 2026-08-17 so is `visuals`: the size classes pick the
## sprite as well as the amount. That was the point of the ore request -- a
## 200-gold seam and an 800-gold seam had been pixel-identical, which made the
## size classes data no player could act on.
class_name ResourceDef
extends RefCounted

var id: StringName = &""
## food | wood | gold | stone -- which stockpile a gathered load lands in.
var kind: StringName = &""
## The node's look when nothing has said which size -- the build menu, a portrait,
## a caller that has only a def_id. Also the fallback for every size when `visuals`
## below is empty, which is every kind that has one bake for all three.
var visual: StringName = &""

## One visual per size class, small to large, or empty to use `visual` for all of
## them. Short lists are allowed and CLAMP rather than fail: stone ships two actors
## for three classes, so its medium and large share the quarry.
var visuals: Array[StringName] = []

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
	r.visuals = GameDefs.name_list(d.get("visuals", []))
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


## The sprite for a size class. Clamped for the same reason `amount_for()` is: a
## kind with two actors for three classes must draw its nearest one, not nothing.
## `size_class < 0` means "no preference" and gets the plain `visual`, which is what
## a portrait or a build-menu icon wants.
func visual_for_size(size_class: int) -> StringName:
	if visuals.is_empty() or size_class < 0:
		return visual
	return visuals[clampi(size_class, 0, visuals.size() - 1)]
