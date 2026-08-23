## Gaia animals that come at you (PLAN.md 4.13's hostile wolf, 6.1b's roaming).
##
## THIS IS THE ONLY AUTO-ACQUIRE IN THE GAME, and `CombatSystem`'s header rules the
## behaviour out in as many words -- "a unit fights what it was ORDERED to fight and
## nothing else". That rule is about PLAYER units and the reason it exists is that
## guessing on the player's behalf means every villager charging the first enemy who
## walks past. Nobody is playing the wolf. Its whole character is that it decides, so
## the thing 4.12 must not do for a swordsman is the only thing this has to do at all.
##
## It writes ONE field and then gets out of the way: `set_task_attack`, exactly as
## `AttackCommand.apply` would. Everything after that -- walking, standing at reach,
## striking on cooldown, re-acquiring when the target dies -- is `CombatSystem` doing
## what it already did, with no idea that nobody ordered this. That is why the hostile
## wolf needed no new combat code, only a new way into it.
##
## Ordering: before `CombatSystem` in `SimWorld.setup()`, so a wolf that picks a target
## bites on the same tick rather than a tick later.
class_name WildlifeSystem
extends SimSystem

## Ticks between scans. A wolf is not a targeting computer, and this runs a rect query
## per animal -- at 10 ticks/sec, twice a second is far quicker than anything can walk
## out of an aggro radius and an eighth of the work of doing it every tick.
const THINK_INTERVAL_TICKS := 5


func process_tick(w: SimWorld) -> void:
	if w.tick % THINK_INTERVAL_TICKS != 0:
		return
	# Sorted, because the target choice below has to be identical on every machine
	# running this sim -- the same reason `AISystem` and `CombatSystem._reacquire`
	# sort. Two hosts disagreeing about what a wolf bit is a desync.
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
		if def == null or not def.is_wildlife or def.aggro_radius <= 0:
			continue
		# ALREADY BUSY IS LEFT ALONE. A wolf mid-chase must not re-target every five
		# ticks onto whoever is momentarily nearest, or it oscillates between two
		# villagers and reaches neither. `CombatSystem` drops it back to IDLE when
		# its target dies or gets away, and that is when this looks again.
		if u.task == SimUnit.Task.ATTACK and w.get_entity(u.task_target_id) != null:
			continue
		var prey := _nearest_prey(w, u, def.aggro_radius)
		if prey == 0:
			continue
		var tile: Vector2i = w.get_entity(prey).tile()
		u.set_task_attack(prey, tile)
		# The path request is not optional, for the reason `CombatSystem._reacquire`
		# spells out at length: `set_task_attack` raises `path_pending`, `_close_in`
		# reads that as "already on the way", and a wolf that skipped it would stand
		# and stare from three tiles off forever.
		if w.paths != null:
			w.paths.request(u.id, tile)


## The nearest thing this animal is willing to bite, or 0.
##
## THROUGH `Diplomacy` FROM THE WOLF'S OWN SIDE -- `is_enemy(e, 0)` -- which is what
## makes a pack not eat itself: another wolf is owner 0 and so is this one, and the
## first clause in there sends that home as "not an enemy" with nothing said specially.
## Everything a player owns comes back true, villagers and town centres alike.
##
## BUILDINGS ARE FILTERED OUT HERE, though, and deliberately: `Diplomacy` answers "may
## this be attacked", and a town centre may. A wolf gnawing the corner of a granary is
## not what anybody means by wildlife, and it would also park the animal permanently on
## a target that cannot flee and takes four hundred bites to fell.
func _nearest_prey(w: SimWorld, u: SimUnit, radius: int) -> int:
	var here := u.tile()
	var span := radius * 2 + 1
	var rect := Rect2i(here - Vector2i(radius, radius), Vector2i(span, span))

	var best := 0
	var best_gap := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit):
			continue
		if not Diplomacy.is_enemy(e, u.owner_id):
			continue
		var gap := CombatSystem.tile_gap(here, Rect2i(e.tile(), Vector2i.ONE))
		if gap > radius:
			continue          # the rect is square; the radius is meant to be too
		# Nearest wins, lowest id breaks a tie -- `CombatSystem._reacquire`'s rule,
		# and for its reason: determinism, not fairness.
		if best == 0 or gap < best_gap or (gap == best_gap and int(e.id) < best):
			best = int(e.id)
			best_gap = gap
	return best
