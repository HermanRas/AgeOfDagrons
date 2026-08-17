## The gather loop (PLAN.md 6.4): walk to a node, take from it on a cooldown,
## carry up to cap, walk a load home, deposit, repeat until the node is empty --
## at which point the node itself goes, which is also this system's job
## (PLAN.md's system table gives it "depletion", and SimResourceNode.gather()
## defers removal here rather than deciding it under a working villager).
##
## A DEPLETED NODE IS DESPAWNED OUTRIGHT, not left standing as a husk. Its tile is
## claimed occupancy (2.3), so a chopped-out forest that stayed in `entities`
## would leave a dozen unwalkable, unbuildable holes in the ground looking exactly
## like trees -- which is what it did until 2026-08-16. `remaining_fraction()`
## survives for the depletion VISUAL a stump would need; there is no stump art yet
## (PLAN.md A.4), and fading a full-size tree to nothing is not an improvement on
## removing it.
## `gather_slots` (PLAN.md 6.3) caps how many units can be drawing from one
## node at once -- an arrived unit past the cap holds its ground rather than
## gathering, so ten villagers sent at one tree do not all extract at once.
##
## Runs after TaskSystem and before MovementSystem -- same slot TaskSystem itself
## occupies, and for the same reason. A unit that arrived last tick (no waypoint
## left, no path pending) is either put to work or turned around for home THIS
## tick, and if that starts a new route MovementSystem walks it the same tick
## rather than paying an extra tick of visible delay.
##
## `gather_cooldown` counts DOWN in whole ticks, not a fractional accumulator: a
## float accruing `gather_rate` here would round differently on different
## machines and desync (PLAN.md 7.1). `gather_rate` is authored per 100 ticks
## (units.json), so the ticks a single unit costs is a ceiling division done in
## pure integers -- rate 25 gives 4.
class_name GatherSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	var emptied: Array[int] = []
	for entry in w.entities.values():
		if entry is SimResourceNode:
			if (entry as SimResourceNode).is_depleted():
				emptied.append(entry.id)
			continue
		if entry is SimBuilding:
			# A harvested-out field goes the same way an emptied tree does. It is
			# removed rather than left as rubble: a spent crop is not wreckage,
			# and the player paid 60 wood for ground they should get back at once.
			if (entry as SimBuilding).is_spent():
				emptied.append(entry.id)
			continue
		if not (entry is SimUnit):
			continue
		var u: SimUnit = entry
		if u.task == SimUnit.Task.GATHER:
			_process_gather(w, u)
		elif u.task == SimUnit.Task.RETURN:
			_process_return(w, u)

	# AFTER the unit loop, and out of a list rather than inside it: despawn()
	# mutates `entities`, which cannot be done while iterating it, and a villager
	# that filled its last load this tick has already been turned for home above.
	# Its final delivery still lands -- _process_return() deposits before it looks
	# for the node to go back to, and finds it gone only then.
	for id in emptied:
		w.despawn(id)


func _process_gather(w: SimWorld, u: SimUnit) -> void:
	# Still walking there -- nothing to do until it arrives.
	if u.path_pending or u.has_waypoint():
		return

	var node := w.get_entity(u.task_target_id)
	if node == null or not is_harvestable(node, u.owner_id):
		u.stop()
		return
	if not _adjacent_to_rect(u.tile(), harvest_rect(node)):
		# The substituted walk-up tile should always be adjacent (4.1); if it is
		# not, the order cannot be honoured rather than gathering through a wall.
		u.stop()
		return

	var kind := harvest_kind(node)

	# A unit still holding a different kind from an earlier, since-changed order
	# must drop that load off before it can start a new one -- carrying two kinds
	# at once has no slot to represent it.
	if u.carry_amount > 0 and u.carry_kind != kind:
		_start_return(w, u)
		return

	if not _holds_gather_slot(w, node, u):
		# Every slot is taken by a lower-id competitor. Look next door before
		# giving up the tick: standing in a queue behind one bush while the one
		# beside it is untouched is what the project owner watched happen
		# (2026-08-16). Waiting is still the fallback when there is nothing
		# nearby -- better a queue than a villager walking off the map.
		_retarget_near(w, u, kind, node.id)
		return

	var def := w.unit_def(u.def_id)
	var sched := take_schedule(harvest_rate(w, node, u, kind))
	if sched.y <= 0:
		u.stop()          # nothing here yields to this unit at all
		return

	if u.gather_cooldown > 0:
		u.gather_cooldown -= 1
		return

	var cap := int(def.carry_cap.get(kind, 0)) if def != null else 0
	u.carry_kind = kind
	# Never past the carry cap. With one unit per take this always landed exactly
	# on it; a field at age 4 takes four at a time, and a villager walking home
	# with 13 of a 10 cap would be carrying a load it has no room for. The short
	# last take costs a full interval, which is the honest reading -- you cannot
	# fill a basket beyond its size however fast the crop comes in.
	u.carry_amount += harvest_take(node, mini(sched.x, maxi(0, cap - u.carry_amount)))
	u.gather_cooldown = sched.y - 1

	if u.carry_amount >= cap or not is_harvestable(node, u.owner_id):
		_start_return(w, u)


func _process_return(w: SimWorld, u: SimUnit) -> void:
	if u.path_pending or u.has_waypoint():
		return

	var bld := w.get_entity(u.task_target_id) as SimBuilding
	if bld == null or not bld.alive or not bld.is_complete():
		u.stop()
		return
	if not _adjacent_to_rect(u.tile(), bld.footprint_rect()):
		u.stop()
		return

	var player := w.player_for(u.owner_id)
	if player != null and u.carry_amount > 0:
		player.add_resource(u.carry_kind, u.carry_amount)
	u.carry_amount = 0

	# Back to the same node if there is anything left in it; otherwise look for
	# another of the same kind where that one stood, and only then give up. The
	# load just deposited is already banked either way.
	var kind := u.carry_kind
	var node := w.get_entity(u.gather_node_id)
	if node != null and is_harvestable(node, u.owner_id):
		u.set_task_gather(node.id, harvest_spot(node, u.id))
		if w.paths != null:
			w.paths.request(u.id, u.task_target_tile)
		return

	if not _retarget_near(w, u, kind, u.gather_node_id):
		u.stop()


## How far around a spent or crowded node a villager will look for the next one,
## in tiles. 1 is the 3x3 ring the project owner asked for, and the tightness is
## the point: a worker should carry on with the wood it was already standing in
## rather than set off across the map on its own initiative, which is an order
## the player did not give and cannot see coming.
const RESCAN_RADIUS := 1


## Send `u` to another `kind` source beside where its last one stood. Returns
## false when there is nothing to move to, which leaves the caller to decide
## between waiting and retiring -- the two triggers want different answers.
##
## Only somewhere with room: hopping to a node whose slots are also full would
## trade one queue for another and look like indecision. `exclude_id` is the node
## it is leaving, which may already be despawned.
##
## Deterministic, and it has to be: nearest by squared distance, ties broken by
## the lower entity id, over a SORTED id walk -- the same convention
## `nearest_drop_off()` uses. Two clients sending one villager to different
## bushes is a desync.
func _retarget_near(w: SimWorld, u: SimUnit, kind: StringName, exclude_id: int) -> bool:
	var around := u.gather_node_tile
	var ids := w.entities.keys()
	ids.sort()

	var best: SimEntity = null
	var best_d := -1
	for id in ids:
		if id == exclude_id:
			continue
		var e: SimEntity = w.entities[id]
		if not is_harvestable(e, u.owner_id) or harvest_kind(e) != kind:
			continue
		var rect := harvest_rect(e).grow(RESCAN_RADIUS)
		if not rect.has_point(around):
			continue
		if _holders_of(w, e.id).size() >= harvest_slots(e):
			continue          # also full; swapping one queue for another helps nobody
		var d := (e.tile() - around).length_squared()
		if best == null or d < best_d:
			best = e
			best_d = d

	if best == null:
		return false
	u.set_task_gather(best.id, harvest_spot(best, u.id))
	if w.paths != null:
		w.paths.request(u.id, u.task_target_tile)
	return true


func _start_return(w: SimWorld, u: SimUnit) -> void:
	var bld := w.nearest_drop_off(u.owner_id, u.carry_kind, u.tile())
	if bld == null:
		u.stop()          # nowhere to take the load; better idle than stuck walking
		return
	u.set_task_return(bld.id, bld.tile())
	if w.paths != null:
		w.paths.request(u.id, bld.tile())


# ── what counts as something to harvest ─────────────────────────────────────
#
# Two kinds of thing can be worked: a resource node, and a FIELD, which is a
# building that is placed and built like a building and then harvested like a
# berry bush (PLAN.md 6.5). Rather than duck-typing on matching member names,
# the type is branched on HERE, in four small functions, and nothing downstream
# has to know which it got. `is_harvestable` is public because GatherCommand
# validates against exactly the same test the system runs -- two answers to
# "can this be gathered?" would disagree the first time either changed.


## Whether `e` can be worked right now by `player`. A field belongs to somebody,
## so it adds an ownership rule a tree does not have: you may not farm a
## neighbour's crop. A node is gaia's and anyone may cut it.
static func is_harvestable(e: SimEntity, player: int) -> bool:
	if e == null or not e.alive:
		return false
	if e is SimResourceNode:
		return not (e as SimResourceNode).is_depleted()
	if e is SimBuilding:
		var b: SimBuilding = e
		# Complete only: a field still being ploughed has no crop, and its
		# foundation may yet be cancelled out from under the villager.
		return b.gather_kind != &"" and not b.is_spent() \
				and b.is_complete() and b.owner_id == player
	return false


static func harvest_kind(e: SimEntity) -> StringName:
	if e is SimResourceNode:
		return (e as SimResourceNode).kind
	if e is SimBuilding:
		return (e as SimBuilding).gather_kind
	return &""


static func harvest_take(e: SimEntity, amount: int) -> int:
	if e is SimResourceNode:
		return (e as SimResourceNode).gather(amount)
	if e is SimBuilding:
		return (e as SimBuilding).gather(amount)
	return 0


static func harvest_slots(e: SimEntity) -> int:
	if e is SimResourceNode:
		return (e as SimResourceNode).gather_slots
	if e is SimBuilding:
		return (e as SimBuilding).gather_slots
	return 0


## The ground a worker has to stand next to. A node holds one tile; a field
## holds 6x6, and measuring to its centre would put a villager four tiles inside
## the crop before it counted as adjacent -- the same footprint-not-centre
## mistake CombatSystem.tile_gap exists to avoid.
static func harvest_rect(e: SimEntity) -> Rect2i:
	if e is SimBuilding:
		return (e as SimBuilding).footprint_rect()
	if e is SimResourceNode:
		return (e as SimResourceNode).footprint_rect()
	return Rect2i(e.tile(), Vector2i.ONE)


## WHERE a particular worker goes to work `e`. A resource node has one answer, its
## own tile. A field has as many as it has slots, spread over the crop.
##
## Every gatherer used to be sent to `harvest_rect().position` -- the footprint's
## TOP-LEFT CORNER -- which for a one-tile tree is exactly right and for a 6x6
## field put all five villagers on the same corner tile, shoulder to shoulder
## outside the plot (project owner, 2026-08-17, screenshotted). They now stand ON
## the crop, which is only possible because a field no longer blocks movement.
##
## The spots zigzag: x spreads evenly across the width, y alternates between a
## third and two thirds of the height, so five spots on a 6x6 are five distinct
## tiles with no two in the same row. Integer arithmetic throughout, and derived
## from `seed` (the unit's id) rather than from a slot ordering that shuffles as
## workers come and go -- a spot that moved every time a neighbour stopped would
## have villagers trading places across the field for no visible reason.
##
## Two workers can still be handed the same spot, and that is fine: SeparationSystem
## pushes overlapping units apart, and the alternative is reserving spots, which is
## state to keep in sync for a cosmetic gain.
static func harvest_spot(e: SimEntity, seed: int) -> Vector2i:
	var rect := harvest_rect(e)
	var slots := maxi(1, harvest_slots(e))
	var i := posmod(seed, slots)

	# A FIELD is walked over, so its spots are ON it. A rock is solid, so a spot
	# inside it is a tile nobody can reach: those go round the OUTSIDE, spread along
	# the ring one tile out. Both cases are one gatherer per spot; only the side of
	# the edge differs, and that follows from whether the thing can be stood on.
	if e is SimBuilding:
		return rect.position + Vector2i(
			clampi((2 * i + 1) * rect.size.x / (2 * slots), 0, rect.size.x - 1),
			rect.size.y / 3 if i % 2 == 0 else (2 * rect.size.y) / 3)

	if rect.size == Vector2i.ONE:
		return rect.position          # a tree: one tile, one place to stand
	return _ring_tile(rect.grow(1), i, slots)


## The i-th of `n` tiles spread evenly clockwise round `ring`'s perimeter, starting
## at its top-left corner. Integer arithmetic only, so every client walks the same
## ring in the same order -- two clients sending one villager to different sides of
## a rock is a desync (PLAN.md 7.1).
static func _ring_tile(ring: Rect2i, i: int, n: int) -> Vector2i:
	var w := maxi(1, ring.size.x - 1)
	var h := maxi(1, ring.size.y - 1)
	var perimeter := 2 * (w + h)
	var step := posmod(i * perimeter / maxi(1, n), perimeter)

	if step < w:
		return ring.position + Vector2i(step, 0)                       # top edge
	step -= w
	if step < h:
		return ring.position + Vector2i(w, step)                       # right edge
	step -= h
	if step < w:
		return ring.position + Vector2i(w - step, h)                   # bottom edge
	step -= w
	return ring.position + Vector2i(0, h - step)                       # left edge


## What rate applies to `u` working `e`, per 100 ticks. TWO DIFFERENT SOURCES, and
## which one is the point:
##
##   a resource node -- the UNIT's `gather_rate` for the kind. How fast wood comes
##     out of a tree is a property of the axe, and every unit could differ.
##   a FIELD -- the FIELD's own `gather_yield_per_age`. A farm's output belongs to
##     the farm and to how far its owner has researched (project owner,
##     2026-08-17: 1 food a tick per villager at age 2, 2.5 at age 3, 4 at age 4).
##     The villager's own food rate is deliberately NOT consulted, or advancing an
##     age would be multiplied by whoever happened to be standing in the crop.
##
## Read off the DEF rather than copied onto SimBuilding at spawn, unlike
## `gather_amount` beside it: the yield is immutable per building type, so a copy
## would be a second place for the same number to live, and this already reaches
## for `w.unit_def()` in the same breath. The crop is copied because it is the half
## that changes.
static func harvest_rate(w: SimWorld, e: SimEntity, u: SimUnit, kind: StringName) -> int:
	if e is SimBuilding:
		var bd: BuildingDef = w.building_def((e as SimBuilding).def_id)
		if bd == null:
			return 0
		var owner := w.player_for(e.owner_id)
		return bd.gather_yield_for_age(owner.age if owner != null else 1)

	var def := w.unit_def(u.def_id)
	return int(def.gather_rate.get(kind, 0)) if def != null else 0


## How `rate` per 100 ticks is actually paid out: (units per take, ticks between
## takes), which is the fraction rate/100 in LOWEST TERMS.
##
## The old form was "one unit every ceil(100/rate) ticks", and it cannot express a
## rate above 100: the interval floors at one tick, so 250 and 400 and 10000 all
## collapse to one unit a tick. A field at age 3 yields 2.5 a tick, which is 5 units
## every 2 ticks -- exactly representable as a fraction and not at all as an
## interval. Reducing by the gcd is what makes the average exact in both directions
## with no float and no accumulator to drift between clients.
##
## Every rate in the shipped data reduces to the same schedule the interval form
## gave, so this changed no existing timing: the villager's 25 is 25/100 = 1/4, one
## unit every four ticks. It is also strictly more accurate where they differ -- an
## authored 40 is 2 units per 5 ticks here against ceil(100/40) = one per 3 before,
## which was 0.33 a tick for a number that says 0.4.
static func take_schedule(rate: int) -> Vector2i:
	if rate <= 0:
		return Vector2i.ZERO
	var g := _gcd(rate, 100)
	return Vector2i(rate / g, 100 / g)


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return maxi(1, absi(a))


## Whether `u` is one of the (at most) `node.gather_slots` units currently
## drawing from it (PLAN.md 6.3's cap on simultaneous gatherers). Recomputed
## fresh every tick from live task state rather than reserved once and stored
## in a new field -- ties broken by id, the same determinism convention as
## `nearest_drop_off()` -- so a competitor stopping, dying, or being re-tasked
## frees its spot for whoever ranks next, with nothing extra to keep in sync.
##
## RETURN counts alongside GATHER: a unit walking a load home still holds its
## place at the node it is coming back to, so a slot cannot be sniped out from
## under it mid-cycle by whichever other villager happens to arrive first.
func _holds_gather_slot(w: SimWorld, node: SimEntity, u: SimUnit) -> bool:
	return _holders_of(w, node.id).find(u.id) < harvest_slots(node)


## Every unit currently claiming a place at `node_id`, lowest id first. Shared by
## the slot test and by the re-scan, which needs to know whether a candidate has
## room before sending anyone to it.
func _holders_of(w: SimWorld, node_id: int) -> Array[int]:
	var holders: Array[int] = []
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var other: SimUnit = entry
		if not other.alive or other.gather_node_id != node_id:
			continue
		if other.task == SimUnit.Task.GATHER or other.task == SimUnit.Task.RETURN:
			holders.append(other.id)
	holders.sort()
	return holders


func _adjacent_to_rect(from: Vector2i, rect: Rect2i) -> bool:
	var cx := clampi(from.x, rect.position.x, rect.end.x - 1)
	var cy := clampi(from.y, rect.position.y, rect.end.y - 1)
	return absi(from.x - cx) <= 1 and absi(from.y - cy) <= 1
