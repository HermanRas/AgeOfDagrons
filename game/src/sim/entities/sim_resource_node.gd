## A gatherable resource node -- tree, gold mine, deer (PLAN.md 6.2). Phase 2.3.
##
## One class for all three because they differ only in data: `kind` decides which
## stockpile a load lands in, `amount` how much is left, `gather_slots` how many
## villagers fit. The deer additionally roams and flees, but that is 6.1b and lives
## in a system, not here.
##
## `size_class` is 0 small / 1 medium / 2 large and selects the starting amount
## from `ResourceDef.amounts` -- and, since 2026-08-17, the SPRITE too, from
## `ResourceDef.visuals`. It was a data distinction only for months, and that was
## the complaint behind the whole ore request: a 200-gold seam and an 800-gold seam
## were pixel-identical, so the player could not tell a rich node from a poor one
## and the size classes were data nobody could act on.
##
## Nodes occupy grid tiles like buildings do, so a villager cannot walk through a
## tree. Unlike buildings their footprint is always a single tile -- 6.3's forest
## clustering makes a wood by placing many one-tile trees, which is also how the
## partial-depletion look comes for free as individual trees vanish.
class_name SimResourceNode
extends SimEntity

var kind: StringName = &""
var amount: int = 0
var starting_amount: int = 0
var size_class: int = 0
var gather_slots: int = 1

## Tiles claimed, from `ResourceDef.footprint_for_size`. ONE for a tree, a bush and
## every animal; 4x4 for the big gold seam and the quarry (project owner,
## 2026-08-17: "for trees it makes sense, for stone and gold it does not").
##
## `pos` is the footprint's CENTRE, exactly as SimBuilding's is, so `tile()` returns
## the middle tile and `origin_tile()` recovers the corner. For everything 1x1 the
## two are the same tile and nothing about a forest changed.
var footprint: Vector2i = Vector2i.ONE

## Wildlife (the deer) must be killed before it yields food, and the corpse is
## what gets gathered.
##
## The live-animal / carcass / depleted state machine is **6.1a's**, not this
## class's, and is deliberately not modelled here. It does not fit `alive`: a
## carcass is not alive yet must still be drawn and still be gatherable, whereas a
## depleted tree is neither. Inventing a third state now would mean guessing how
## SnapshotSystem should treat it before anything gathers, so this phase carries
## only the flag saying which nodes need that treatment.
var is_wildlife: bool = false


## Take up to `requested` units and return what was actually available -- less than
## requested on the last gather of a nearly-empty node. The caller must credit the
## **return value**, not the request, or a nearly-empty tree yields infinite wood.
##
## Removal on depletion is the gather system's call (6.4), not this method's:
## despawning here would drop the node out from under the villager that is
## mid-swing at it, in the middle of another system's loop over `entities`.
## GatherSystem sweeps for empty nodes at the end of its own tick instead.
func gather(requested: int) -> int:
	var taken := clampi(requested, 0, amount)
	amount -= taken
	return taken


func is_depleted() -> bool:
	return amount <= 0


## Remaining fraction, for a depletion visual later (a stump, a thinned mine).
func remaining_fraction() -> float:
	if starting_amount <= 0:
		return 0.0
	return clampf(float(amount) / float(starting_amount), 0.0, 1.0)


func to_snapshot() -> Dictionary:
	var d := super()
	d["kind"] = kind
	d["amount"] = amount
	d["remaining"] = remaining_fraction()
	# Sent because the size classes now pick the SPRITE as well as the amount
	# (2026-08-17: three gold actors, two stone). It cannot be derived on the far
	# side -- `amount` runs down as the node is worked, so a nearly-spent large
	# node and a fresh small one carry the same number.
	d["size_class"] = size_class
	# Same key and same {x, y} shape SimBuilding sends, so the view's depth sort,
	# picking and occlusion all treat a 4x4 rock exactly as they treat a 4x4
	# building -- none of them needed changing. What DID need changing is anything
	# that used the presence of this key to mean "this is a building".
	d["footprint"] = {"x": footprint.x, "y": footprint.y}
	return d


func origin_tile() -> Vector2i:
	var half := Vector2i(footprint.x * SimWorld.SUBTILE, footprint.y * SimWorld.SUBTILE) / 2
	return (pos - half) / SimWorld.SUBTILE


func footprint_rect() -> Rect2i:
	return SimMap.footprint_rect(origin_tile(), footprint)
