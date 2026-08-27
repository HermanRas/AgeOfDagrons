## Reacts to hp reaching 0 (PLAN.md 4.7, 5.5, 5.6). Nothing currently deals
## damage except the debug destroy command -- combat lands later and will drive
## the same `alive` flag SimEntity.take_damage() already sets, so this system
## needs no changes when it does.
##
## Runs last in SimWorld.setup()'s system order: everything else this tick has
## already acted on a unit or building while it still could.
class_name DeathSystem
extends SimSystem

func process_tick(w: SimWorld) -> void:
	var to_despawn: Array[int] = []
	var carcasses: Array[Array] = []          # [def_id, tile]
	for e in w.entities.values():
		if e is SimUnit:
			if _process_wildlife(w, e as SimUnit, to_despawn, carcasses):
				continue
			_process_unit(e as SimUnit, to_despawn)
		elif e is SimBuilding:
			_process_building(w, e as SimBuilding, to_despawn)

	# Despawn BEFORE spawning the carcass. Both want the same tile, and
	# `spawn_resource_node` refuses ground that is already claimed -- so the other
	# order silently drops every carcass and the hunt yields nothing.
	for id in to_despawn:
		w.despawn(id)
	for c in carcasses:
		w.spawn_resource_node(c[0], c[1], 0)


## A dead animal becomes a CARCASS rather than a corpse, and the difference is that a
## carcass is a thing you can eat (PLAN.md 4.13, and the hunt half of 6.1a). True when
## this unit was handled here, so the caller skips the ordinary corpse path.
##
## NO CORPSE PHASE AT ALL. A villager's death takes seventy seconds to clear -- die,
## lie there, decay, despawn (4.7) -- and that is right for a body nobody wants. But
## the wolf's body is the reward for killing it, and a hunter standing over a fresh
## kill for a minute waiting for permission to butcher it is not a delay anybody would
## read as deliberate. So the unit leaves the moment it dies and the node takes its
## place on the same tile, in the same tick.
##
## The animal crosses from `SimUnit` to `SimResourceNode` here, which sounds violent
## and is in fact the only way the two capabilities can meet: `CombatSystem` iterates
## units and `GatherSystem.is_harvestable` accepts nodes, with no shared interface
## between them. A thing that is both hunted and harvested has to be one and then the
## other, and its death is the seam.
##
## WILDLIFE THAT NAMES NO CARCASS falls through to the ordinary corpse path, so a
## future harmless animal can die like anything else without special-casing.
func _process_wildlife(w: SimWorld, u: SimUnit, to_despawn: Array[int],
		carcasses: Array[Array]) -> bool:
	if u.alive:
		return false
	var def := w.unit_def(u.def_id)
	if def == null or not def.is_wildlife or def.carcass_def == &"":
		return false
	# `corpse_ticks_left` is the "already handled" sentinel everywhere else in this
	# file; reuse it so a second pass over the same dead wolf cannot queue a second
	# carcass. It never counts down -- the despawn below happens this tick.
	if u.corpse_ticks_left >= 0:
		return true
	u.corpse_ticks_left = 0
	u.stop()
	to_despawn.append(u.id)
	carcasses.append([def.carcass_def, u.tile()])
	return true


## A unit's death plays out over time -- die anim, drop cargo, corpse, decay,
## then gone -- rather than vanishing the tick hp hits 0 (4.7). `corpse_ticks_left`
## starting at -1 is what tells a fresh death (set it up) from one already under
## way (just count it down); `alive` itself only ever goes false once and cannot
## carry that distinction.
func _process_unit(u: SimUnit, to_despawn: Array[int]) -> void:
	if u.alive:
		return

	if u.corpse_ticks_left < 0:
		u.anim = &"die"
		# A dead villager has nothing left to deliver -- MVP has no resource pile
		# to drop it into, so the load is simply lost rather than teleporting home.
		u.carry_amount = 0
		u.carry_kind = &""
		# AND IT STOPS WALKING (project owner, 2026-08-20). Death has to cancel the
		# ORDER, not merely mark the unit: `MovementSystem` drives anything with a
		# waypoint left to walk, and a corpse still had one -- so a villager killed
		# in mid-stride carried on to wherever it had been sent and only came to rest
		# on arriving. The same leftover task would have had it gathering and
		# building from the grave.
		#
		# Nothing needs to cancel its queued path search: `PathService.process()`
		# already drops a request whose unit has died rather than writing a route
		# onto it.
		u.stop()
		u.corpse_ticks_left = SimUnit.CORPSE_TOTAL_TICKS
		return

	u.corpse_ticks_left -= 1
	if u.corpse_ticks_left == SimUnit.CORPSE_FADE_TICKS:
		u.anim = &"decay"          # the last 10 s, fading out (4.7)
	if u.corpse_ticks_left <= 0:
		to_despawn.append(u.id)


## A destroyed building becomes rubble, then clears itself away a minute later
## (5.5, amended by the project owner 2026-08-16). `free_footprint()` frees its
## tiles the same tick it falls, so a new building can go up on the ground it
## held without waiting for the wreckage to go.
##
## RUBBLE USED TO BE PERMANENT, which is what PLAN.md 5.5 said and what the art
## note justified: 0 A.D.'s rubble has no decay animation to play. But permanence
## is not what "no decay clip" implies -- it only means the fade has to be an
## alpha ramp rather than an animation, which is exactly what a corpse's last ten
## seconds already are (4.7). Left forever, a razed settlement silted the map up
## with debris that nothing could remove and that sat on ground already rebuilt.
##
## Structured exactly like _process_unit's corpse, one sentinel and one counter,
## because they are the same problem: something dies, is still drawn for a while,
## and then is not.
func _process_building(w: SimWorld, b: SimBuilding, to_despawn: Array[int]) -> void:
	if b.alive:
		return

	if b.phase != SimBuilding.Phase.DESTROYED:
		b.phase = SimBuilding.Phase.DESTROYED
		b.rubble_ticks_left = SimBuilding.RUBBLE_TOTAL_TICKS
		w.free_footprint(b.id)
		# THE GARRISON DIES WITH IT (project owner, 2026-08-27: "units garrisoned when
		# a building is destroyed is killed with building"). Deliberately not an
		# auto-eject: a castle holding fifteen is a real commitment, and that is what
		# makes out-ranging it with siege worth doing rather than merely possible.
		#
		# AFTER `free_footprint`, so the ground they are put out onto is no longer
		# claimed by the building that is killing them.
		_kill_garrison(w, b)
		return

	# A building already DESTROYED when this system first sees it -- one spawned
	# straight into the phase, or loaded from a save -- gets its timer started
	# here rather than sitting at the -1 sentinel forever.
	if b.rubble_ticks_left < 0:
		b.rubble_ticks_left = SimBuilding.RUBBLE_TOTAL_TICKS
		return

	b.rubble_ticks_left -= 1
	if b.rubble_ticks_left <= 0:
		to_despawn.append(b.id)


## Everybody inside a building that has just fallen, put out and then killed
## (PLAN.md 4.8).
##
## PUT OUT FIRST, AND THAT IS THE WHOLE TRICK. A corpse has to be somewhere: while a
## unit is garrisoned it is out of `SpatialHash` and its `pos` is wherever it last
## stood, so killing it in place would leave a body lying at the tile it walked in
## from -- possibly on the far side of the map from the tower it died in, and
## possibly under a building somebody has since put there. `ungarrison_unit` places
## it beside the wreckage and puts it back in the index, and only then does it die.
## The result on screen is a tower falling with bodies appearing around it, which is
## what the event actually was.
##
## Killed by `take_damage(hp)` rather than by setting `alive` directly, so the
## ordinary corpse path in `_process_unit` picks them up on the NEXT tick and they
## die, decay and despawn exactly like anything else. That is also why this does not
## touch `corpse_ticks_left`: leaving it at -1 is what tells that function these are
## fresh deaths it has not seen.
##
## A UNIT IT CANNOT PUT OUT IS STILL KILLED. `ungarrison_unit` refuses when there is
## nowhere legal to stand -- a tower walled in by its own owner -- and the alternative
## to killing it anyway is a unit alive inside a building that no longer exists,
## unreachable and un-selectable for the rest of the match. It stays where it is,
## which is a corpse at a stale tile: the wrong body in the wrong place beats a unit
## the player owns and can never find.
func _kill_garrison(w: SimWorld, b: SimBuilding) -> void:
	# Backwards, because `ungarrison_unit` removes the entry it is handed and a
	# forward walk over a shrinking array skips every other occupant.
	for i in range(b.garrison.size() - 1, -1, -1):
		var u := w.get_entity(int(b.garrison[i]["id"])) as SimUnit
		if u == null:
			b.garrison.remove_at(i)
			continue
		if not w.ungarrison_unit(b, u):
			# Could not be placed. Drop the entry by hand so the list does not keep a
			# unit that is about to be a corpse, and let it die where it stands.
			b.garrison.remove_at(i)
			u.garrisoned_in = 0
		if u.alive:
			u.take_damage(u.hp, 0)
