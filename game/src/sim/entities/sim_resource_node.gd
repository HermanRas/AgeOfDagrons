## A gatherable resource node -- tree, gold mine, deer (PLAN.md 6.2). Phase 2.3.
##
## One class for all three because they differ only in data: `kind` decides which
## stockpile a load lands in, `amount` how much is left, `gather_slots` how many
## villagers fit. The deer additionally roams and flees, but that is 6.1b and lives
## in a system, not here.
##
## `size_class` is 0 small / 1 medium / 2 large and selects the starting amount
## from `ResourceDef.amounts`. It is a **data** distinction only: every size draws
## the same sprite (ASSET_MISSING.md 1.3), so nothing here picks art by size.
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
	return d
