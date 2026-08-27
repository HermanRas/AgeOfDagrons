## Units going into buildings, and what happens to them while they are in there
## (PLAN.md 4.8). Three jobs, in this order:
##
##   1. **admit** whoever has walked up to the building they were ordered into
##   2. **heal** everybody already inside, 1 hp per 5 ticks
##   3. **prune** entries whose unit has gone
##
## Runs in the same slot as GatherSystem and BuildSystem and for the same reason
## those two give: a unit that arrived last tick acts THIS tick rather than standing
## outside the door for one. It sits before CombatSystem, so an archer admitted this
## tick is already adding its damage to the tower's shot on this tick -- which is the
## visible difference between "the reinforcements arrived" and "the reinforcements
## arrived a moment ago".
##
## THE ARRIVAL CHECK IS THIS SYSTEM'S AND NOT TaskSystem'S. `TaskSystem` retires a
## finished MOVE; GATHER, RETURN, BUILD and now GARRISON each own their own arrival,
## because arriving there means "start doing the thing", not "go idle". Copied from
## `BuildSystem._process` almost line for line, including the `alive` test, which
## that file explains: a unit killed by a command this tick is already dead when this
## runs and DeathSystem has not cleared its task yet. Nobody garrisons from the grave.
class_name GarrisonSystem
extends SimSystem

## 1 hp every 5 ticks, i.e. 2 hp a second (project owner, 2026-08-27). A 30 hp archer
## is back to full in 15 seconds and a 100 hp knight in 50.
##
## A CONSTANT AND NOT A DATA FIELD, which is the one place this feature departs from
## "prefer extending data over hardcoding" (PLAN.md 1). It is a single global rule
## rather than a property of any entity: no building declares a heal rate, no unit
## declares a heal resistance, and nothing has asked for either. Putting it in
## buildings.json would mean the same number copied onto three defs with nothing able
## to disagree with it. When a monastery or a tech wants its own rate, that is when
## the number moves into the data -- and the day it does, this constant is where the
## default lives.
const HEAL_TICKS := 5
const HEAL_AMOUNT := 1

## Adjacency, as a Chebyshev gap in tiles against the FOOTPRINT: 1 is touching. Same
## number `BuildSystem._adjacent_to_rect` uses, and it has to be a footprint rather
## than a centre for the same reason combat reach does -- a unit standing against a
## [7, 7] castle is 3 tiles from its middle and touching its wall.
const ENTRY_REACH := 1


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if entry is SimUnit and entry.alive and entry.task == SimUnit.Task.GARRISON:
			_admit(w, entry)

	# SECOND, over the buildings, so a unit admitted above starts healing on the tick
	# it goes in rather than the next one.
	#
	# ONE MODULO OVER THE WORLD CLOCK rather than a per-unit counter, which is both
	# cheaper and one less field to hash: `tick % HEAL_TICKS` is the same answer on
	# every host by construction, where a counter would be one more thing two clients
	# could disagree about. The cost is that everybody inside heals on the same tick
	# and a unit garrisoned on tick 4 gets its first hp on tick 5 -- a fifth of a
	# second of favour that nothing can perceive.
	var healing := w.tick % HEAL_TICKS == 0
	for entry in w.entities.values():
		if not (entry is SimBuilding):
			continue
		var b: SimBuilding = entry
		if b.garrison.is_empty():
			continue
		_prune(w, b)
		if healing:
			_heal(w, b)


## Step a unit inside if it has got there; retire the order if the destination has
## stopped being one.
##
## A FULL BUILDING RETIRES THE ORDER RATHER THAN QUEUEING. The unit walked all the
## way to a tower that filled up while it was walking, and the honest answer is to
## stand it down where it is: waiting would be a unit loitering on an order the player
## cannot see, and `ProductionSystem`'s "retry every tick until room opens up" is the
## opposite call for a case where nothing is standing around visibly doing nothing.
## The player still has the unit, still selected, and can send it somewhere else.
func _admit(w: SimWorld, u: SimUnit) -> void:
	if u.path_pending or u.has_waypoint():
		return

	var b := w.get_entity(u.task_target_id) as SimBuilding
	if b == null or not b.alive or not b.is_complete() or b.owner_id != u.owner_id:
		u.stop()
		return
	if CombatSystem.tile_gap(u.tile(), b.footprint_rect()) > ENTRY_REACH:
		# Never got there -- the route ran out short, which `set_path` reports by
		# rewriting `task_target_tile` to wherever it really ended (4.1). Standing down
		# is the same answer BuildSystem gives a builder that did not reach its site.
		u.stop()
		return

	if not w.garrison_unit(b, u):
		u.stop()


## 1 hp per HEAL_TICKS to everybody inside, capped at their own max.
##
## THE UNIT'S OWN `max_hp`, not the building's, and it is worth saying because both
## are to hand: a garrisoned unit heals toward what it was built with, and a damaged
## tower does not repair itself by having archers in it. Repair is still the disabled
## placeholder it has always been (`SelectionActions`).
func _heal(w: SimWorld, b: SimBuilding) -> void:
	for entry in b.garrison:
		var u := w.get_entity(int(entry["id"])) as SimUnit
		if u == null or not u.alive:
			continue
		u.hp = mini(u.hp + HEAL_AMOUNT, u.max_hp)


## Drop entries whose unit is gone or dead.
##
## Nothing should reach this today -- a garrisoned unit is out of the spatial index so
## nothing can target it, and the one thing that kills a garrison (its building
## falling, DeathSystem) empties the list itself. It exists because the failure it
## prevents is silent and permanent: `SimBuilding.attack_bonus` prices the garrison
## from each ENTRY's own `def_id` rather than from the live entity, so a stale entry
## would go on adding damage to the tower's shot forever with no unit anywhere to
## explain it. One scan over a list that is empty for 28 of 31 buildings is a cheap
## way to make that class of bug impossible rather than merely unlikely.
func _prune(w: SimWorld, b: SimBuilding) -> void:
	for i in range(b.garrison.size() - 1, -1, -1):
		var u := w.get_entity(int(b.garrison[i]["id"])) as SimUnit
		if u == null or not u.alive:
			b.garrison.remove_at(i)
