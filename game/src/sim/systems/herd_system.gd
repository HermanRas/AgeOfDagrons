## Livestock changing hands (PLAN.md 6.5). Walk a unit past a sheep and it follows your
## orders; walk somebody else's unit closer and it follows theirs.
##
## THE ONE IDEA IS THAT HERDING IS NOT OWNING. A claimed sheep stays gaia's -- only
## `SimUnit.herded_by` moves -- and keeping those two apart is what made this a small
## system instead of a large one:
##
##   - `GatherSystem` never had to learn about units. Its `is_harvestable` and its five
##     sibling dispatchers accept nodes and buildings and nothing else; a live sheep
##     that could be eaten would have meant a `SimUnit` branch in all six, in the one
##     system the whole villager economy runs through.
##   - `WinConditionSystem` cannot be kept alive by a flock. It counts living units by
##     owner, so a real transfer would let a wiped-out player survive on a sheep.
##   - THE HERDER CAN STILL ATTACK IT, because `Diplomacy` makes any gaia unit a legal
##     target. That is how the animal becomes food: order it home, kill it, gather the
##     carcass. Had the sheep become yours, `AttackCommand` would have refused it and
##     slaughtering your own livestock would have needed a command of its own.
##
## The cost is one extra tap against the game this borrows from -- kill, then gather,
## where AoE folds both into one order. The project owner chose that trade knowing it.
class_name HerdSystem
extends SimSystem

## How near a unit has to be, in tiles, to take an animal over. Generous on purpose:
## claiming should feel like walking past a flock rather than like hitting a target.
const CLAIM_RADIUS := 4

## Ticks between sweeps. A flock is not urgent, and this is a rect query per animal.
const THINK_INTERVAL_TICKS := 5


func process_tick(w: SimWorld) -> void:
	if w.tick % THINK_INTERVAL_TICKS != 0:
		return
	# Sorted for determinism, as everywhere in this folder: two hosts disagreeing about
	# who owns a cow is a desync, and a cow is worth 500 food.
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Variant = w.entities.get(id)
		if not (e is SimUnit):
			continue
		var u := e as SimUnit
		if not u.alive or u.owner_id != 0:
			continue
		var def := w.unit_def(u.def_id)
		if def == null or not def.is_herdable:
			continue
		var claimant := _nearest_claimant(w, u)
		# NOT CLEARED WHEN NOBODY IS NEAR. Sticky ownership is what lets a player pen a
		# flock at home and walk away from it; releasing on distance would mean a herd
		# reverted to gaia the moment its shepherd went back to work.
		if claimant != 0:
			u.herded_by = claimant


## The player whose unit is standing nearest, or 0.
##
## ANY unit, not just a villager: a scout that rides past a flock has plainly found it,
## and making the claim a villager's privilege would be a rule with nothing behind it.
##
## Ties go to the lowest ENTITY id rather than the lowest player id -- so a contest is
## settled by which unit actually got there, and player 1 does not quietly win every
## standoff by virtue of being player 1.
func _nearest_claimant(w: SimWorld, animal: SimUnit) -> int:
	var here := animal.tile()
	var span := CLAIM_RADIUS * 2 + 1
	var rect := Rect2i(here - Vector2i(CLAIM_RADIUS, CLAIM_RADIUS), Vector2i(span, span))

	var best_owner := 0
	var best_gap := 1 << 30
	var best_id := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit) or not e.alive or e.owner_id == 0:
			continue
		var gap := CombatSystem.tile_gap(here, Rect2i(e.tile(), Vector2i.ONE))
		if gap > CLAIM_RADIUS:
			continue          # the rect is square; the radius is meant to be round
		if best_id == 0 or gap < best_gap or (gap == best_gap and int(e.id) < best_id):
			best_gap = gap
			best_id = int(e.id)
			best_owner = e.owner_id
	return best_owner
