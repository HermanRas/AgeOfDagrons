## Siege engines travel packed and fight deployed (PLAN.md 4.13, 9.2.1).
##
## Three units in the roster ship as a `_packed`/`_unpacked` actor PAIR in 0 A.D. --
## ballista, onager, trebuchet -- and this is the state machine between them: a wagon
## that rolls and cannot shoot, an engine that shoots and cannot move, and a few seconds
## of crew work between the two that is the whole cost of changing your mind.
##
## **IT IS AUTOMATIC, AND THAT IS A DESIGN CALL RATHER THAN A SHORTCUT.** AoE2 makes the
## trebuchet's pack a button; here an order implies its own state, so ordering a move
## folds the engine up and ordering an attack sets it down once it is in range. Three
## reasons. This is a PHONE, and a verb that must be pressed before another verb works
## is the class of interface a small screen punishes hardest. `SelectionActions` is
## already at `MAX_ACTIONS` on the castle, so the button would have cost a real order
## somewhere. And the game has no auto-acquire on purpose (4.13), so there is no
## defensive posture a manual deploy would serve -- a deployed engine with nothing
## ordered would just be a wagon standing in a field with its legs out.
##
## The cost is still paid, which is the point: `pack_ticks` is dead time at both ends,
## so walking a trebuchet two tiles to the left is sixteen seconds of not shooting.
##
## RUNS BEFORE `CombatSystem` AND `MovementSystem`, so an engine that finishes its
## transition on this tick acts on this tick rather than standing through another one.
## It reads `has_waypoint()`/`path_pending`, both of which `CommandSystem` and
## `PathSystem` have already settled higher up the tick.
##
## In `src/sim/` and touching no Node, no texture and no `Iso` -- the visual swap is the
## client reading `packed` off the snapshot and picking `UnitDef.packed_visual`, which
## is the allowed direction (PLAN.md 4).
class_name SiegeSystem
extends SimSystem


func process_tick(w: SimWorld) -> void:
	for entry in w.entities.values():
		if not (entry is SimUnit):
			continue
		var u: SimUnit = entry
		# A CORPSE DOES NOT DEPLOY, the same invariant every other system that acts on
		# units states -- `DeathSystem` runs later, so a unit killed this tick is still
		# alive-shaped to everything above it.
		if not u.packs or not u.alive:
			continue
		var def := w.unit_def(u.def_id)
		if def == null:
			continue

		if u.pack_ticks_left > 0:
			u.pack_ticks_left -= 1
		else:
			_decide(w, u, def)

		# SPEED IS DERIVED, EVERY TICK, and that is what keeps `MovementSystem` free of
		# any of this: a deployed or mid-transition engine simply has nothing to spend,
		# so the walker's ordinary budget loop does nothing and no gate had to be added
		# to a function every unit in the game goes through.
		#
		# It also fixes something that was quietly broken before packing existed. All
		# three engines carried `speed: 0` and NOTHING refused them a move order, so one
		# sent across the map took a route from `PathService` and held it, unwalked,
		# forever -- ordered, pathed, and standing still with no way to tell it had
		# failed. Now that order means "fold up first".
		u.speed = def.packed_speed if u.can_move() else 0


## Whether this engine should be starting a transition, given what it has been told to
## do. Only reached when it is settled, so nothing here can interrupt a fold in progress
## -- an order given mid-transition takes effect when the crew finish, which is both
## simpler than unwinding and what a crew would actually do.
func _decide(w: SimWorld, u: SimUnit, def: UnitDef) -> void:
	# WANTING TO WALK IS THE PACK TRIGGER, and it is read off the ROUTE rather than off
	# the task: MOVE, ATTACK-from-range, GATHER and a rally-point walk all travel, and
	# `is_travel_task()` exists precisely so nothing has to list them. A route it cannot
	# use is the unambiguous statement that it is trying to be somewhere else.
	if u.has_waypoint() or u.path_pending:
		u.begin_packing(true, def.pack_ticks)
		return

	# STANDING STILL WITH SOMETHING TO SHOOT. Deployed only once it is actually in
	# range, so an engine ordered across the map at a distant castle unpacks at the
	# wall and not at home -- `CombatSystem._close_in` gives it the route that keeps
	# it packed until it arrives, and `halt()` takes that route away on arrival, which
	# is the tick this sees.
	if u.task == SimUnit.Task.ATTACK:
		var target := w.get_entity(u.task_target_id)
		if target != null and target.alive \
				and CombatSystem._within_reach(u, target, def.attack_range):
			u.begin_packing(false, def.pack_ticks)
